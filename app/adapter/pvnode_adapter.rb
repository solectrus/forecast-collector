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
    )
    uri.to_s
  end

  private

  def azimuth_to_orientation(azimuth)
    (azimuth.to_i + 180) % 360
  end

  def declination_to_slope(declination)
    declination.to_i
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
