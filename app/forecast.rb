require 'net/http'
require_relative 'config'

class Forecast
  BASE_URL = 'https://api.forecast.solar'.freeze

  def initialize(config:)
    @config = config
  end

  attr_reader :config

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

  def uri(index)
    URI.parse(formatted_url(index))
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
    }
  end

  def formatted_url(index)
    raw_url.tap do |url|
      parameters(index).each { |key, value| url.sub!(":#{key}", value) }
    end
  end

  def forecast_response(index)
    response = Net::HTTP.get_response(uri(index))

    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    else
      throw "Failure: #{response.value}"
    end
  end
end
