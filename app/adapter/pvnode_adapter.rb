require 'net/http'
require 'config'
require 'adapter/base_adapter'

class PvnodeAdapter < BaseAdapter # rubocop:disable Metrics/ClassLength
  BASE_URL = 'https://api.pvnode.com/v1/forecast/'.freeze

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
        temp: value_point['temp']&.round(1),
        weather_code: value_point['weather_code'],
      }.compact
    end

    result
  end

  def provider_name
    'pvnode'
  end

  def paid?
    config.pvnode_paid == true
  end

  def adapter_requests_count
    # Since pvnode supports up to 2 planes per request, we can batch them.
    # However, we can only batch planes with identical extra_params, since
    # extra_params apply to the entire request, not per plane.
    batched_planes.length
  end

  SAFETY_MARGIN_SECONDS = 5 * 60 # 5 minutes
  private_constant :SAFETY_MARGIN_SECONDS

  SECONDS_PER_DAY = 24 * 60 * 60 # 24 hours
  private_constant :SECONDS_PER_DAY

  def next_fetch_time
    unless paid?
      # For free accounts, there is a rate limit of 40 requests per month (!)
      return Time.now.utc + (SECONDS_PER_DAY * adapter_requests_count)
    end

    # pvnode has a fixed schedule with 16 updates per day:
    #   01:00, 01:30, 04:00, 04:30, 07:00, 07:30, 10:00, 10:30,
    #   13:00, 13:30, 16:00, 16:30, 19:00, 19:30, 22:00, 22:30
    # All times in UTC
    scheduled_hours = [1, 4, 7, 10, 13, 16, 19, 22]
    scheduled_minutes = [0, 30]

    now = Time.now.utc

    # Find the next scheduled time today
    scheduled_hours.each do |hour|
      scheduled_minutes.each do |minute|
        scheduled_time = Time.utc(now.year, now.month, now.day, hour, minute, 0) + SAFETY_MARGIN_SECONDS
        return scheduled_time if scheduled_time > now
      end
    end

    # If no time found today, use the first time tomorrow
    # Use Time arithmetic to handle month/year boundaries and leap years correctly
    # We fetch 5 minutes later to ensure data is ready.
    one_day_later = now + SECONDS_PER_DAY
    Time.utc(
      one_day_later.year, one_day_later.month, one_day_later.day,
      scheduled_hours.first, scheduled_minutes.first, 0,
    ) + SAFETY_MARGIN_SECONDS
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

  private

  # Groups planes into batches, where each batch contains up to 2 planes
  # with identical extra_params. Returns an array of batches.
  # Example: [[plane0, plane1], [plane2], [plane3, plane4]]
  def batched_planes
    @batched_planes ||= begin
      # Group planes by their extra_params
      grouped = config.pvnode_configurations.group_by { |plane| plane[:extra_params] }

      # For each group, split into batches of max 2 planes
      batches = []
      grouped.each_value do |planes|
        planes.each_slice(2) { |batch| batches << batch }
      end

      batches
    end
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
    'pv_watts,temp,weather_code'
  end

  def build_params(first_plane, second_plane)
    params = {
      latitude: first_plane[:latitude],
      longitude: first_plane[:longitude],
      slope: first_plane[:declination],
      orientation: first_plane[:azimuth],
      pv_power_kw: first_plane[:kwp],
      required_data:,
      clearsky_data:,
      past_days:,
      forecast_days:,
    }.compact

    # Add second plane parameters if available
    if second_plane
      params.merge!({
        second_array_slope: second_plane[:declination],
        second_array_orientation: second_plane[:azimuth],
        second_array_power_kw: second_plane[:kwp],
      }.compact)
    end

    params
  end

  def make_http_request(index)
    uri = URI(formatted_url(index))
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{config.pvnode_apikey}"
    request['User-Agent'] = user_agent

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
  end
end
