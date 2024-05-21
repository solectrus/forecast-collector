require 'net/http'
require_relative 'config'
require_relative 'forecast'

class ForecastSolar < Forecast
  BASE_URL = 'https://api.forecast.solar'.freeze

  def uri(index)
    URI.parse(formatted_url(index))
  end

  def current(index)
    # Change mapping:
    #   "result": {
    #     "watts": {
    #       "1632979620": 0,
    #       "1632984240": 28,
    #       "1632988800": 119,
    #    .....
    #   =>
    #   { 1632979620 => 0, 1632980640 => 28, 1632981600 => 119, ... }

    forecast_response(index).dig('result', 'watts').transform_keys(&:to_i)
  end

  private

  def base_url
    [BASE_URL, config.forecast_solar_apikey, 'estimate'].compact.join('/')
  end

  def raw_url
    "#{base_url}/:lat/:lon/:dec/:az/:kwp" \
      '?damping=:damping_morning,:damping_evening' \
      '&time=seconds'
  end

  def parameters(index)
    cfg = config.forecast_configurations[index]
    {
      lat: cfg[:latitude],
      lon: cfg[:longitude],
      dec: cfg[:declination],
      az: cfg[:azimuth],
      kwp: cfg[:kwp],
      damping_morning: cfg[:damping_morning],
      damping_evening: cfg[:damping_evening],
      inverter: cfg[:inverter],
      horizon: cfg[:horizon],
    }.compact
  end

  def formatted_url(index)
    result = raw_url.tap do |url|
      parameters(index).each { |key, value| url.sub!(":#{key}", value) }
    end

    # Additional parameters (if present)
    %i[inverter horizon].each do |key|
      result += "&#{key}=#{parameters(index)[key]}" if parameters(index)[key]
    end

    result
  end
end
