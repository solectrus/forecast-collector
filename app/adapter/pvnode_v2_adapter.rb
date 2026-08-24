require 'adapter/base_adapter'
require 'adapter/pvnode/authorization'
require 'adapter/pvnode/poll_schedule'
require 'adapter/pvnode/request_limit'
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
class PvnodeV2Adapter < BaseAdapter
  include Pvnode::Authorization

  # @param site_id [String] the pvnode site to request. It comes from
  #   PVNODE_SITE_ID or from the sites of the account, so the adapter takes it
  #   as an argument instead of reading it from the configuration.
  def initialize(config:, site_id:)
    super(config:)

    @site_id = site_id
  end

  attr_reader :site_id

  BASE_URL = 'https://api.pvnode.com/v2/forecast/'.freeze

  # Field groups to request (repeatable `include` parameter):
  # - default:  pv_power (W)
  # - clearsky: pv_power_clearsky (W)
  # - weather:  temp (°C), relative_humidity (%), weather_code
  INCLUDE_GROUPS = %w[default clearsky weather].freeze

  # The API returns naive site-local timestamps by default. Ask for UTC
  # instead, so the collector does not need a timezone database.
  TIMEZONE = 'utc'.freeze

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

  def pull_interval_message
    schedule.message
  end

  def fetch_data
    super.tap { report_request_limit }
  end

  # The schedule of the next request comes from the response body, so it is
  # recorded here. This keeps #parse_forecast_data free of side effects.
  def parse_json_response(http_response)
    super.tap { |data| schedule.record_recommendation(data['next_poll_at']) }
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
      *INCLUDE_GROUPS.map { |group| ['include', group] },
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
end
