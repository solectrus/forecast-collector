require 'net/http'
require_relative 'config'

class Forecast
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
    URI.parse 'https://api.forecast.solar/estimate/' \
              "#{config.forecast_latitude}/" \
              "#{config.forecast_longitude}/" \
              "#{config.forecast_declination}/" \
              "#{config.forecast_azimuth}/" \
              "#{config.forecast_kwp}" \
              '?time=seconds'
  end

  private

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
