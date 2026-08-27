require 'adapter/base_adapter'
require 'adapter/pvnode/authorization'
require 'adapter/pvnode/poll_schedule'
require 'adapter/pvnode/poll_state'
require 'adapter/pvnode/request_limit'
require 'adapter/pvnode/response_error'
require 'adapter/pvnode/timestamp'

# pvnode API v2 adapter.
#
# Unlike v1 (per-plane query parameters, batched into requests), v2 is
# site-based: the location and all PV strings are configured once on the pvnode
# site and referenced by its ID. A single request returns the full forecast.
#
# The API also plans the schedule: it says with `next_poll_at` when the next
# request is useful and reports the monthly quota in headers. The adapter
# therefore needs no knowledge about the plan of the user, unlike the v1
# adapter, which calculates its schedule from PVNODE_PAID.
#
# See https://pvnode.com/docs/v2/integrations/build-your-own
class PvnodeV2Adapter < BaseAdapter # rubocop:disable Metrics/ClassLength
  include Pvnode::Authorization

  BASE_URL = 'https://api.pvnode.com/v2/forecast/'.freeze

  # The API returns naive site-local timestamps by default. Ask for UTC
  # instead, so the collector does not need a timezone database.
  TIMEZONE = 'utc'.freeze

  # Field groups of a forecast request, sent as a repeatable `include`
  # parameter. `default` carries pv_power (W), the reason for the request, so
  # the collector never drops it. On top of it come pv_power_clearsky (W) from
  # `clearsky` and temp (°C), relative_humidity (%) and weather_code from
  # `weather`.
  BASE_GROUP = 'default'.freeze
  OPTIONAL_GROUPS = %w[clearsky weather].freeze

  # @param site_id [String] the pvnode site to request. It comes from
  #   PVNODE_SITE_ID or from the sites of the account, so the adapter takes it
  #   as an argument instead of reading it from the configuration.
  def initialize(config:, site_id:)
    super(config:)

    @site_id = site_id
  end

  attr_reader :site_id

  def provider_name
    'pvnode (v2)'
  end

  # Monthly quota reported by the last response, nil before the first request.
  def request_limit
    schedule.request_limit
  end

  def next_fetch_time
    schedule.next_fetch_time
  end

  # A restart must not repeat a request that the API already answered. If the
  # stored slot is still ahead, the collector waits for it instead of asking
  # again for the forecast that is already in InfluxDB.
  def first_fetch_time
    stored = state.next_poll_at
    return Time.now unless stored&.>(Time.now)

    schedule.record_recommendation(stored.iso8601)
    puts "Found a saved pvnode schedule, no new forecast before #{stored.localtime}"

    next_fetch_time
  end

  def pull_interval_message
    schedule.message
  end

  def fetch_data
    super.tap { report_request_limit }
  end

  # A plan can lose a field group, for example after a downgrade. The API then
  # rejects the whole request and names the group. The collector drops it and
  # asks again, so a plan change costs no forecast.
  def fetch(index)
    super
  rescue Pvnode::ResponseError::GroupRejected => e
    drop_group(e.group)

    retry
  end

  # The schedule of the next request comes from the response body, so it is
  # recorded here. This keeps #parse_forecast_data free of side effects.
  def parse_json_response(http_response)
    report_error(http_response) unless http_response.is_a?(Net::HTTPOK)

    super.tap do |data|
      schedule.record_recommendation(data['next_poll_at'])
      state.save(data['next_poll_at'])
    end
  end

  def parse_forecast_data(response_data)
    result = {}

    response_data['values']&.each do |value_point|
      timestamp = Pvnode::Timestamp.parse(value_point['timestamp']).to_i

      result[timestamp] = {
        watt: value_point['pv_power']&.round,
        watt_clearsky: value_point['pv_power_clearsky']&.round,
        temp: value_point['temp']&.round(1),
        humidity: value_point['relative_humidity']&.round(1),
        weather_code: value_point['weather_code'],
      }.compact
    end

    result
  end

  def required_requests_count
    # Site-based: all PV strings live on the pvnode site and are returned in a
    # single request, regardless of the number of planes.
    1
  end

  def formatted_url(_index)
    uri = URI("#{BASE_URL}#{site_id}")

    # Repeatable `include` parameter, one entry per field group. Built as an
    # array of pairs (not a Hash) so the duplicate `include` keys are
    # preserved.
    #
    # `forecast_days` is not sent on purpose: without it the API returns the
    # longest horizon the subscription allows. This keeps the collector free of
    # any knowledge about the plan of the user.
    params = [
      *include_groups.map { |group| ['include', group] },
      ['past_days', 0],
      ['timezone', TIMEZONE],
    ]

    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  private

  def schedule
    @schedule ||= Pvnode::PollSchedule.new(request_limit_per_month: config.pvnode_request_limit)
  end

  def state
    @state ||= Pvnode::PollState.new(site_id:)
  end

  # The attempt is recorded before the request, so a network error cannot cause
  # a fast retry loop. The quota headers come with every response, including
  # the 429 that reports an exhausted quota, so they are read before the status
  # code is evaluated.
  def make_http_request(index)
    schedule.record_attempt

    super.tap do |response|
      schedule.record_request_limit(Pvnode::RequestLimit.from_response(response))
    end
  end

  # An error that only the user can fix stops the collector. Without this the
  # collector repeats the same rejected request until somebody reads the log.
  #
  # Every other error stays with the request: the loop reports it, the forecast
  # that is already in InfluxDB stays visible, and the schedule tries again.
  def report_error(http_response)
    error = Pvnode::ResponseError.new(http_response)

    group = error.rejected_group(droppable_groups)
    raise Pvnode::ResponseError::GroupRejected, group if group

    raise error.to_s unless error.fatal?

    puts "ERROR: #{error}"
    puts error.advice
    exit 1
  end

  # The quota counts per account, not per site. If other tools use the same
  # pvnode account, their requests count too. Showing the number makes that
  # visible and explains a collector that waits.
  def report_request_limit
    return unless request_limit

    prefix = request_limit.exhausted? || request_limit.low? ? '  WARNING: ' : '  '
    puts "#{prefix}pvnode quota: #{request_limit}"

    report_ineffective_request_limit
  end

  # The self-imposed limit only has an effect below the limit of the plan. The
  # real limit is known as soon as the first response arrives. A plan without a
  # cap has no limit to compare, and the self-imposed one always has an effect.
  def report_ineffective_request_limit
    limit = config.pvnode_request_limit
    return if @ineffective_limit_reported || limit.nil?
    return unless request_limit.metered?
    return if limit < request_limit.limit

    @ineffective_limit_reported = true
    puts "  WARNING: PVNODE_REQUEST_LIMIT=#{limit} has no effect, " \
         "your plan allows #{request_limit.limit} requests per month"
  end

  # Groups of the running process. A group that the API rejected is gone, so
  # the requests that follow leave it out.
  def include_groups
    @include_groups ||= [BASE_GROUP, *OPTIONAL_GROUPS]
  end

  def droppable_groups
    include_groups - [BASE_GROUP]
  end

  def drop_group(group)
    include_groups.delete(group)

    puts "  NOTE: Your pvnode plan does not include the `#{group}` data. " \
         'Collecting the other data.'
  end
end
