require 'net/http'
require 'influxdb-client'

require 'flux_writer'

class Loop
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def self.start(config:, max_count: nil, max_wait: 12)
    new(config:).start(max_count:, max_wait:)
  end

  def start(max_count: nil, max_wait: nil)
    exit(1) unless influx_ready?(max_wait)

    self.count = 0
    sleep_until(config.adapter.first_fetch_time)

    loop do
      self.count += 1
      now = DateTime.now
      puts "##{count} Fetching forecast at #{now}"
      push_to_influx(config.adapter.fetch_data)
      break if max_count && count >= max_count

      sleep_until(config.adapter.next_fetch_time)
    end
  end

  private

  attr_accessor :count

  def influx_ready?(max_wait)
    print 'Wait until InfluxDB is ready ...'

    count = 0
    until (ready = flux_writer.ready?) || (max_wait && count >= max_wait)
      print '.'
      count += 1
      sleep 5
    end

    if ready
      puts ' OK'
      puts
      true
    else
      puts "\nInfluxDB not ready after #{count * 5} seconds - aborting."
      false
    end
  end

  def sleep_until(time)
    duration = (time - Time.now).ceil
    return unless duration.positive?

    puts "  Sleeping until #{time.localtime} ..."
    sleep duration
  end

  def push_to_influx(data)
    return unless data

    print '  Pushing forecast to InfluxDB ... '
    flux_writer.push(data)
    puts 'OK'
  end

  def flux_writer
    @flux_writer ||= FluxWriter.new(config:)
  end
end
