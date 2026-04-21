# Scheduling logic for pvnode Nowcast mode
#
# Nowcast enables high-frequency fetching during daylight hours, aligned to the
# 4th minute of each 10-minute interval (:04, :14, :24, :34, :44, :54) because
# the Nowcast data is freshly computed one minute prior.
#
# Daytime is determined from clearsky data: sunrise is the first timestamp with
# watt_clearsky > 0, sunset is the last such timestamp for tomorrow (since
# past_days=0 means today's early hours may be missing from the response).
#
# During nighttime, fetching falls back to the regular slot-based schedule.

module Pvnode
  class Nowcast
    FETCH_MINUTE_OFFSET = 4 # Nowcast is ready at :03, fetch at :04
    BASE_INTERVAL_MINUTES = 10

    # Conservative daylight assumption for budget planning: 12h of daylight
    # means 72 potential 10-minute slots per day. Used only to compute
    # skip_factor when the monthly budget can't cover every slot.
    DAYLIGHT_SLOTS_PER_DAY = 72
    private_constant :DAYLIGHT_SLOTS_PER_DAY

    DAYS_PER_MONTH = 31
    private_constant :DAYS_PER_MONTH

    # @param slots [Pvnode::Slots] fallback scheduler for nighttime
    # @param required_requests_count [Integer] number of API requests per fetch cycle
    def initialize(slots:, required_requests_count:)
      @slots = slots
      @required_requests_count = required_requests_count
    end

    # Extracts sunrise and sunset times from fetched clearsky data.
    # Should be called after each successful fetch.
    #
    # Keeps previously-derived values if the response contains no usable
    # tomorrow clearsky data, to avoid flapping between daytime and fallback.
    #
    # @param data [Hash] accumulated forecast data in format
    #   { timestamp => { watt_clearsky: Integer, ... }, ... }
    def update_daylight(data)
      return unless data

      first, last = tomorrow_clearsky_timestamps(data).minmax
      return unless first

      self.sunrise = time_of_day_today(first)
      self.sunset = time_of_day_today(last)
    end

    # Returns the next fetch time, aligned to the :04 offset of each
    # interval_minutes boundary.
    # During daytime: next aligned minute (but not past sunset)
    # During nighttime: delegates to slots
    #
    # @return [Time]
    def next_fetch_time
      return slots.next_fetch_time unless daytime?

      candidate = next_aligned_time
      candidate <= sunset ? candidate : slots.next_fetch_time
    end

    # @return [Boolean] true if sun position data is available and current time is between sunrise and sunset
    def daytime?
      return false unless sunrise && sunset

      Time.now.utc.between?(sunrise, sunset)
    end

    # Effective interval in minutes between daytime fetches.
    # BASE_INTERVAL_MINUTES when the monthly budget fits every 10-min slot,
    # otherwise a multiple that stretches the cadence to stay within budget.
    def interval_minutes
      BASE_INTERVAL_MINUTES * skip_factor
    end

    private

    attr_reader :slots, :required_requests_count
    attr_accessor :sunrise, :sunset

    def skip_factor
      @skip_factor ||= begin
        max_fetches_per_day =
          Pvnode::Slots::MAX_REQUESTS_PER_MONTH_NOWCAST.to_f /
          DAYS_PER_MONTH /
          required_requests_count

        if max_fetches_per_day >= DAYLIGHT_SLOTS_PER_DAY
          1
        else
          (DAYLIGHT_SLOTS_PER_DAY / max_fetches_per_day).ceil
        end
      end
    end

    def tomorrow_clearsky_timestamps(data)
      now = Time.now.utc
      tomorrow_start = Time.utc(now.year, now.month, now.day).to_i + 86_400
      tomorrow_end = tomorrow_start + 86_400

      data.filter_map do |timestamp, values|
        next unless timestamp >= tomorrow_start && timestamp < tomorrow_end
        next unless (values[:watt_clearsky] || 0).positive?

        timestamp
      end
    end

    def time_of_day_today(timestamp)
      t = Time.at(timestamp).utc
      now = Time.now.utc
      Time.utc(now.year, now.month, now.day, t.hour, t.min, 0)
    end

    def next_aligned_time
      now = Time.now.utc
      step = interval_minutes
      minutes_since_midnight = (now.hour * 60) + now.min
      next_minute = ((minutes_since_midnight / step) * step) + FETCH_MINUTE_OFFSET
      next_minute += step if next_minute <= minutes_since_midnight

      Time.utc(now.year, now.month, now.day) + (next_minute * 60)
    end
  end
end
