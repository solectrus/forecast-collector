require 'net/http'
require 'config'
require 'adapter/base_adapter'

class PvnodeAdapter < BaseAdapter
  BASE_URL = 'https://api.pvnode.com/v1/forecast/'.freeze

  def parse_forecast_data(response_data)
    result = {}

    response_data['values']&.each do |value_point|
      timestamp = DateTime.parse(value_point['dtm']).to_time.to_i
      watts = value_point['pv_watts'].to_i
      result[timestamp] = watts
    end

    result
  end

  def provider_name
    'pvnode'
  end

  def adapter_configuration_count
    config.pvnode_configurations&.length || 0
  end

  SAFETY_MARGIN_SECONDS = 300 # 5 minutes
  private_constant :SAFETY_MARGIN_SECONDS

  def next_fetch_time
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
    one_day_later = now + 86_400 # 24 * 60 * 60 seconds
    Time.utc(
      one_day_later.year, one_day_later.month, one_day_later.day,
      scheduled_hours.first, scheduled_minutes.first, 0,
    ) + SAFETY_MARGIN_SECONDS
  end

  def formatted_url(index)
    uri = URI(BASE_URL)
    cfg = config.pvnode_configurations[index]
    uri.query = URI.encode_www_form(
      latitude: cfg[:latitude],
      longitude: cfg[:longitude],
      slope: declination_to_slope(cfg[:declination]),
      orientation: azimuth_to_orientation(cfg[:azimuth]),
      pv_power_kw: cfg[:kwp],
      required_data: 'pv_watts',
      past_days: 0,
    )
    uri.to_s
  end

  private

  def azimuth_to_orientation(azimuth)
    (azimuth.to_i + 180) % 360
  end

  def declination_to_slope(declination)
    declination.to_f.round(1)
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
