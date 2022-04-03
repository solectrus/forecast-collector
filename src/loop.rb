require 'net/http'
require 'influxdb-client'

require_relative 'flux_writer'
require_relative 'forecast'

class Loop
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def self.start(config:, max_count: nil)
    new(config:).start(max_count)
  end

  def start(max_count)
    self.count = 0
    loop do
      self.count += 1
      push_to_influx(data)
      break if max_count && count >= max_count

      puts 'Sleeping ...'
      sleep config.forecast_interval
    end
  end

  private

  attr_accessor :count

  def push_to_influx(data)
    return unless data

    print 'Pushing forecast to InfluxDB ... '
    FluxWriter.push(config:, data:)
    puts 'OK'
  end

  def data
    forecast = Forecast.new(config:)
    print "##{count}: Getting data from #{forecast.uri} ... "

    begin
      hash = forecast.current
      puts 'OK'
      hash
    rescue StandardError => e
      puts "Error #{e}"
    end
  end
end
