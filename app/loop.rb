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

      puts "Sleeping for #{config.forecast_interval} seconds ..."
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

    hashes = []

    (0...config.forecast_configurations.length).each do |index|
      print "##{count}.#{index}: Getting data from #{forecast.uri(index)} ... "

      begin
        hashes.append(forecast.current(index))
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
end
