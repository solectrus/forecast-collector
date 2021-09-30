require 'net/http'
require 'influxdb-client'

require_relative 'flux_writer'
require_relative 'forecast'

class Loop
  include FluxWriter

  def self.start(max_count: nil)
    new.start(max_count)
  end

  def start(max_count)
    unless interval.positive?
      puts 'Interval missing, stopping.'
      return
    end

    puts "Starting forecast collector...\n\n"

    self.count = 0
    loop do
      self.count += 1
      push_to_influx(data)
      break if max_count && count >= max_count

      puts "Sleeping #{interval} seconds ..."
      sleep interval
    end
  end

  private

  attr_accessor :count

  def push_to_influx(data)
    return unless data

    points = data.map do |key, value|
      InfluxDB2::Point.new(
        name: influx_measurement,
        time: key,
        fields: { watt: value }
      )
    end

    print 'Pushing forecast to InfluxDB ... '
    write_api.write(data: points, bucket: influx_bucket, org: influx_org)
    puts 'OK'
  end

  def data
    puts "\n-------------------------------------------------------\n"
    forecast = Forecast.new
    print "##{count}: Getting data from #{forecast.uri} ... "

    begin
      hash = forecast.current
      puts 'OK'
      hash
    rescue StandardError => e
      puts "Error #{e}"
    end
  end

  def influx_measurement
    'Forecast'
  end

  def interval
    @interval ||= ENV['FORECAST_INTERVAL'].to_i
  end
end
