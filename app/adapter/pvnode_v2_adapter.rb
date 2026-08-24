require 'adapter/pvnode/timestamp'
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

  # The API returns naive site-local timestamps by default. Ask for UTC
  # instead, so the collector does not need a timezone database.
  TIMEZONE = 'utc'.freeze

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
    uri = URI("#{BASE_URL}#{config.pvnode_site_id}")

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
end
