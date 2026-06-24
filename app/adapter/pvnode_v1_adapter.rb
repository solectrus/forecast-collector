require 'net/http'
require 'config'
require 'adapter/base_adapter'
require 'adapter/pvnode/slots'
require 'adapter/pvnode/nowcast'
require 'adapter/pvnode/request_builder'

class PvnodeV1Adapter < BaseAdapter
  include Pvnode::RequestBuilder

  BASE_URL = 'https://api.pvnode.com/v1/forecast/'.freeze

  # The slot scheduler fetches at most hourly; higher-frequency tiers rely on
  # the Nowcast scheduler for sub-hourly updates.
  MAX_SLOTS_PER_DAY = 24

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

  def next_fetch_time
    nowcast&.next_fetch_time || slots.next_fetch_time
  end

  def pull_interval_message
    if nowcast?
      "in Nowcast mode (every #{nowcast.interval_minutes} min during daylight, slot-based at night)"
    else
      'on provider schedule (auto)'
    end
  end

  private

  def slots
    @slots ||= Pvnode::Slots.new(
      max_requests_per_month:,
      required_requests_count:,
      slots_per_day:,
    )
  end

  def nowcast
    return unless nowcast?

    @nowcast ||= Pvnode::Nowcast.new(
      slots:,
      required_requests_count:,
      max_requests_per_month:,
    )
  end

  def nowcast?
    config.pvnode_nowcast == true
  end

  def paid?
    config.pvnode_paid == true
  end

  # The active subscription tier. Reads the subclass's TIERS, so v1 and v2
  # share the tier names (free/light/plus) but define their own values.
  def tier
    return self.class::TIERS.fetch(:plus) if nowcast?
    return self.class::TIERS.fetch(:light) if paid?

    self.class::TIERS.fetch(:free)
  end

  # Monthly request budget of the active subscription tier.
  def max_requests_per_month
    tier.fetch(:requests_per_month)
  end

  # How often the slot scheduler should fetch per day, capped at hourly: tiers
  # that update less often (v2 Free: once daily) fetch correspondingly less,
  # while sub-hourly nowcast updates are handled by the Nowcast scheduler. Tiers
  # without a documented update frequency fall back to the hourly grid.
  def slots_per_day
    [tier.fetch(:updates_per_day, MAX_SLOTS_PER_DAY), MAX_SLOTS_PER_DAY].min
  end

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
