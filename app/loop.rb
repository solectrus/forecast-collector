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
    forecast = Forecast.new(config:)
    loop do
      self.count += 1
      puts "##{count} Fetching forecast"
      push_to_influx(forecast.fetch_data)
      break if max_count && count >= max_count

      puts "  Sleeping for #{config.forecast_interval} seconds ..."
      sleep_with_heartbeat
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

  def sleep_with_heartbeat
    start_time = Time.now
    end_time = start_time + config.forecast_interval

    while Time.now < end_time
      heartbeat

      remaining_time = end_time - Time.now
      sleep_time = [60, remaining_time].min
      sleep(sleep_time)
    end
  end

  def heartbeat
    File.write('/tmp/heartbeat.txt', Time.now.to_i)
  end
end
