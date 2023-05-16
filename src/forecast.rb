require 'net/http'
require_relative 'config'

class Forecast
  BASE_URL = 'https://api.forecast.solar'.freeze

  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def current
    # Change mapping:
    #   "result": {
    #     "watts": {
    #       "1632979620": 0,
    #       "1632984240": 28,
    #       "1632988800": 119,
    #    .....
    #   =>
    #   { 1632979620 => 0, 1632980640 => 28, 1632981600 => 119, ... }

    forecast_response.dig('result', 'watts').transform_keys(&:to_i)
  end

  def uri
    @uri ||= URI.parse(formatted_url)
  end

  private

  def base_url
    if config.forecast_solar_apikey
      "#{BASE_URL}/#{config.forecast_solar_apikey}/estimate"
    else
      "#{BASE_URL}/estimate"
    end
  end

  def raw_url
    "#{base_url}/:lat/:lon/:dec/:az/:kwp" \
      '?damping_morning=:damping_morning' \
      '&damping_evening=:damping_evening' \
      '&time=seconds'
  end

  def parameters
    {
      lat: config.forecast_latitude,
      lon: config.forecast_longitude,
      dec: config.forecast_declination,
      az: config.forecast_azimuth,
      kwp: config.forecast_kwp,
      damping_morning: config.forecast_damping_morning,
      damping_evening: config.forecast_damping_evening,
    }
  end

  def formatted_url
    raw_url.tap do |url|
      parameters.each { |key, value| url.sub!(":#{key}", value) }
    end
  end

  def forecast_response
    response = Net::HTTP.get_response(uri)

    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    else
      throw "Failure: #{response.value}"
    end
  end
end
