require 'net/http'
require_relative 'config'

class Forecast
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def fetch_data
    hashes = []

    len =
      case config.forecast_provider
      when 'forecast.solar'
        config.forecast_configurations.length
      when 'solcast'
        config.solcast_configurations.length
      end

    (0...len).each do |index|
      print "  #{index}: #{uri(index)} ... "
      begin
        hashes.append(current(index))
        puts 'OK'
      rescue StandardError => e
        puts "Error #{e}"
      end
    end

    accumulate(hashes)
  end

  def accumulate(hashes)
    result = hashes[0]
    (1...hashes.length).each do |index|
      hashes[index].each do |k, v|
        result[k] ||= 0
        result[k] += v
      end
    end

    result
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
