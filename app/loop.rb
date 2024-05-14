require 'net/http'
require 'influxdb-client'

require_relative 'flux_writer'
require_relative 'forecast'
require_relative 'forecast_solar'
require_relative 'solcast'

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
    forecast = make_forecast
    loop do
      self.count += 1
      now = DateTime.now
      puts "##{count} Fetching forecast at #{now}"
      push_to_influx(forecast.fetch_data)
      break if max_count && count >= max_count

      next_request = DateTime.now.to_time + config.forecast_interval
      puts "  Sleeping for #{config.forecast_interval} seconds (until #{next_request}) ..."

      sleep config.forecast_interval
    end
  end

  private

  attr_accessor :count

  def push_to_influx(data)
    return unless data

    print '  Pushing forecast to InfluxDB ... '
    FluxWriter.push(config:, data:)
    puts 'OK'
  end

  def make_forecast
    case config.forecast_provider
    when 'forecast.solar'
      ForecastSolar.new(config:)
    when 'solcast'
      Solcast.new(config:)
    end
  end
end
