require 'time'
require 'tzinfo'
require 'adapter/pvnode_v1_adapter'

# pvnode API v2 adapter.
#
# Unlike v1 (per-plane query parameters, batched into requests), v2 is
# site-based: the location and all PV strings are configured once on the pvnode
# site and referenced by its ID. A single request returns the full forecast.
#
# Scheduling (slots/Nowcast), authentication and HTTP handling are inherited
# unchanged from the v1 PvnodeV1Adapter; only the URL building and response
# parsing differ.
class PvnodeV2Adapter < PvnodeV1Adapter
  BASE_URL = 'https://api.pvnode.com/v2/forecast/'.freeze

  # Field groups to request (repeatable `include` parameter):
  # - default:  pv_power (W)
  # - clearsky: pv_power_clearsky (W)
  # - weather:  temp (°C), relative_humidity (%), weather_code
  INCLUDE_GROUPS = %w[default clearsky weather].freeze

  # Subscription tiers (pvnode v2 API), selected via PVNODE_PAID:
  #   free → free, true → light, nowcast → plus
  # Free updates once daily, Light hourly, Plus every 10 min (nowcast).
  # Enterprise is custom and not represented here; PVNODE_PAID=nowcast stays
  # safely within any higher Enterprise allowance.
  TIERS = {
    free: { requests_per_month: 250, updates_per_day: 1 },
    light: { requests_per_month: 3_000, updates_per_day: 24 },
    plus: { requests_per_month: 3_000, updates_per_day: 144 },
  }.freeze

  def provider_name
    'pvnode (v2)'
  end

  def parse_forecast_data(response_data)
    timezone = TZInfo::Timezone.get(response_data['timezone'])

    result = {}

    response_data['values']&.each do |value_point|
      # pvnode returns naive local timestamps (no offset); the site timezone is
      # provided once at the top level. Convert to a UTC epoch.
      timestamp = local_to_epoch(value_point['timestamp'], timezone)

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
    uri = URI("#{BASE_URL}#{config.pvnode_site_id}")

    # Repeatable `include` parameter, one entry per field group, plus the
    # forecast/past day range. Built as an array of pairs (not a Hash) so the
    # duplicate `include` keys are preserved.
    params = [
      *INCLUDE_GROUPS.map { |group| ['include', group] },
      ['forecast_days', forecast_days],
      ['past_days', past_days],
    ]

    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  private

  # Converts a naive local timestamp (e.g. "2026-06-24T12:00:00") in the given
  # timezone to a UTC epoch.
  #
  # The wall-clock components are parsed as UTC (note the appended +0000) so the
  # result never depends on the machine's local timezone — Time.strptime without
  # a zone would apply ENV['TZ'], which differs e.g. between a developer's
  # machine and the UTC-based CI runners.
  def local_to_epoch(timestamp, timezone)
    naive = Time.strptime("#{timestamp}+0000", '%Y-%m-%dT%H:%M:%S%z')
    naive_local_to_utc(naive, timezone).to_i
  end

  # Resolves a naive local wall-clock time to UTC:
  # - Ambiguous autumn fall-back times resolve to the first (still-DST) occurrence.
  # - Non-existent spring-forward times (the clock skips an hour) are shifted past
  #   the 1-hour gap, so the conversion never raises.
  def naive_local_to_utc(naive, timezone)
    timezone.local_to_utc(naive, &:first)
  rescue TZInfo::PeriodNotFound
    naive_local_to_utc(naive + 3600, timezone)
  end
end
