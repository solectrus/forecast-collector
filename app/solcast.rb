require 'net/http'
require_relative 'config'
require_relative 'forecast'

class Solcast < Forecast
  BASE_URL = 'https://api.solcast.com.au/rooftop_sites'.freeze

  def uri(index)
    URI.parse(formatted_url(index))
  end

  def current(index)
    # Change mapping:
    # {
    #  "forecasts": [
    #    {
    #      "pv_estimate": 0.541,
    #      "pv_estimate10": 0.465,
    #      "pv_estimate90": 0.6213,
    #      "period_end": "2024-05-06T16:00:00.0000000Z",
    #      "period": "PT30M"
    #    },
    #    {
    #      "pv_estimate": 0.5552,
    #      "pv_estimate10": 0.3647,
    #      "pv_estimate90": 0.6777,
    #      "period_end": "2024-05-06T16:30:00.0000000Z",
    #      "period": "PT30M"
    #    }, ...
    #
    # => { 1715011200 => 541.0, 1715013000 => 555.2 }

    result = {}
    forecast_response(index)['forecasts'].each do |fc|
      watts = (fc['pv_estimate'] * 1000).to_i
      date = DateTime.iso8601(fc['period_end']).to_time.to_i
      result[date - 1800] = watts
    end
    result
  end

  private

  def raw_url
    "#{BASE_URL}/:site/forecasts?format=json&api_key=:api_key"
  end

  def parameters(index)
    cfg = config.solcast_configurations[index]
    {
      site: cfg[:site],
      api_key: config.solcast_apikey,
    }
  end

  def formatted_url(index)
    raw_url.tap do |url|
      parameters(index).each { |key, value| url.sub!(":#{key}", value) }
    end
  end
end
