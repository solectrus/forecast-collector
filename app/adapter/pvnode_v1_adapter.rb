require 'net/http'
require 'config'
require 'adapter/base_adapter'
require 'adapter/pvnode/scheduling'
require 'adapter/pvnode/authorization'
require 'adapter/pvnode/request_builder'

class PvnodeV1Adapter < BaseAdapter
  include Pvnode::Authorization
  include Pvnode::Scheduling
  include Pvnode::RequestBuilder

  BASE_URL = 'https://api.pvnode.com/v1/forecast/'.freeze

  # Subscription tiers (pvnode v1 API), selected via PVNODE_PAID:
  #   free → free, true → light, nowcast → plus
  # Only the monthly request budget is modelled: v1's per-tier update
  # frequencies aren't documented, so every tier uses the hourly slot grid and
  # the budget alone bounds how often the free tier actually fetches. (The
  # nowcast tier's 10-min cadence is driven by the Nowcast scheduler, not here.)
  TIERS = {
    free: { requests_per_month: 40 },
    light: { requests_per_month: 1_000 },
    plus: { requests_per_month: 3_000 },
  }.freeze

  def parse_forecast_data(response_data)
    result = {}

    response_data['values']&.each do |value_point|
      # Extract four columns:
      # - 'dtm' (datetime in ISO 8601 format)
      # - 'pv_watts' (predicted power in watts)
      # - 'pv_watts_clearsky' (clearsky power in watts)
      # - 'temp' (temperature in °C)

      timestamp = DateTime.parse(value_point['dtm']).to_time.to_i
      result[timestamp] = {
        watt: value_point['pv_watts']&.round,
        watt_clearsky: value_point['pv_watts_clearsky']&.round,
        watt_nosnow: value_point['pv_watts_nosnow']&.round,
        temp: value_point['temp']&.round(1),
        weather_code: value_point['weather_code'],
      }.compact
    end

    result
  end

  def provider_name
    'pvnode (v1)'
  end

  def required_requests_count
    # Since pvnode supports up to 2 planes per request, we can batch them.
    # However, we can only batch planes with identical extra_params, since
    # extra_params apply to the entire request, not per plane.
    batched_planes.length
  end

  def formatted_url(index)
    uri = URI(BASE_URL)

    # Get the batch of planes for this request index
    planes_batch = batched_planes[index]
    first_plane = planes_batch[0]
    second_plane = planes_batch[1] # may be nil

    params = build_params(first_plane, second_plane)
    uri.query = URI.encode_www_form(params)

    # Append extra parameters if provided (same for all planes in batch)
    extra_params = first_plane[:extra_params]
    uri.query += "&#{extra_params}" if extra_params

    uri.to_s
  end

  def fetch_data
    # Derive sunrise/sunset from clearsky data for Nowcast scheduling
    super.tap { |data| nowcast&.update_daylight(data) }
  end

  private

  def past_days
    0
  end

  def forecast_days
    paid? ? 7 : 1
  end

  def clearsky_data
    'true'
  end

  def required_data
    'pv_watts,pv_watts_nosnow,temp,weather_code'
  end
end
