require 'net/http'
require 'influxdb-client'

require 'flux_writer'

class Loop
  # A write to InfluxDB can time out when the host is busy, and InfluxDB itself
  # can restart. The collector must not stop for that, so it repeats the push
  # before it gives up.
  PUSH_ATTEMPTS = 5

  # Seconds before the second attempt. Every further attempt waits twice as
  # long, which gives 5, 10, 20 and 40 seconds, or 75 seconds in total. That is
  # long enough for a restart of InfluxDB. It also stays far below the shortest
  # interval between two forecasts, so a retry never delays the next one.
  PUSH_RETRY_WAIT = 5

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

  # A failed push never stops the collector. The forecast holds timestamps in
  # the future, and the next fetch writes them again. A push that fails for
  # good therefore costs data only until the next fetch.
  def push_to_influx(data)
    return unless data

    attempt = 0

    begin
      attempt += 1
      print '  Pushing forecast to InfluxDB ... '
      flux_writer.push(data)
      puts 'OK'
    rescue StandardError => e
      puts "FAILED (#{e.message})"
      if attempt < PUSH_ATTEMPTS
        sleep PUSH_RETRY_WAIT * (2**(attempt - 1))
        retry
      end

      puts "  WARNING: Cannot push to InfluxDB after #{PUSH_ATTEMPTS} attempts, " \
           'the next forecast repairs the data.'
    end
  end

  def flux_writer
    @flux_writer ||= FluxWriter.new(config:)
  end
end
