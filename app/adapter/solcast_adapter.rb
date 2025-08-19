require 'net/http'
require 'config'
require 'adapter/base_adapter'

class SolcastAdapter < BaseAdapter
  BASE_URL = 'https://api.solcast.com.au/rooftop_sites'.freeze

  def parse_forecast_data(response_data)
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
    response_data['forecasts'].each do |fc|
      watts = (fc['pv_estimate'] * 1000).to_i
      date = DateTime.iso8601(fc['period_end']).to_time.to_i
      result[date - 1800] = watts
    end
    result
  end

  def provider_name
    'Solcast'
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

  def adapter_configuration_count
    config.solcast_configurations.length
  end
end
