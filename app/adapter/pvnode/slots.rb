# Calculates optimal fetch times for pvnode API to respect rate limits
#
# The pvnode API provides weather forecast data with different rate limits:
# - Free accounts: 40 requests/month
# - Paid accounts: 1000 requests/month
#
# The API updates forecast data 16 times per day at fixed slots.
# This class optimizes fetching by:
# - Calculating which slots to use based on rate limit and required requests
# - Skipping slots when necessary to stay within monthly quota
# - Using day-based scheduling for very restrictive limits

module Pvnode
  class Slots
    # pvnode updates forecast data 16 times per day at these fixed times (UTC):
    #   01:00, 01:30, 04:00, 04:30, 07:00, 07:30, 10:00, 10:30,
    #   13:00, 13:30, 16:00, 16:30, 19:00, 19:30, 22:00, 22:30
    SCHEDULED_SLOTS = [
      [1, 0], [1, 30], [4, 0], [4, 30], [7, 0], [7, 30], [10, 0], [10, 30],
      [13, 0], [13, 30], [16, 0], [16, 30], [19, 0], [19, 30], [22, 0], [22, 30],
    ].freeze

    # Rate limits enforced by pvnode API
    MAX_REQUESTS_PER_MONTH_PAID = 1_000  # Paid subscription
    MAX_REQUESTS_PER_MONTH_FREE = 40     # Free tier

    # @param paid [Boolean] true for paid account, false for free account
    # @param required_requests_count [Integer] number of API requests needed per update
    #   (e.g., 2 if we need to fetch data for 2 different plane configurations)
    def initialize(paid:, required_requests_count:)
      @paid = paid
      @required_requests_count = required_requests_count
    end

    attr_reader :paid, :required_requests_count

    # Returns the applicable monthly rate limit based on account type
    def max_requests_per_month
      paid ? MAX_REQUESTS_PER_MONTH_PAID : MAX_REQUESTS_PER_MONTH_FREE
    end

    # Returns the next optimal time to fetch data from pvnode API
    #
    # Strategy:
    # 1. Calculate skip_factor to determine which slots to use
    # 2. If rate limit is very restrictive (skip_factor > 16), schedule days ahead
    # 3. Otherwise, find next available slot today matching the skip pattern
    # 4. If no more slots today, use first slot tomorrow
    #
    # @return [Time] next fetch time in UTC
    def next_fetch_time
      skip_factor = calculate_skip_factor

      # For very restrictive rate limits: skip entire days
      # Example: Free account with 2 requests needs skip_factor=24 → skip 2 days
      if skip_factor > 16
        days_to_skip = (skip_factor / 16.0).ceil
        return Time.now.utc + (SECONDS_PER_DAY * days_to_skip)
      end

      # For normal rate limits: find next matching slot
      now = Time.now.utc
      next_slot = find_next_slot_today(now)
      return next_slot if next_slot

      # No more slots today: use first slot tomorrow
      first_slot_tomorrow(now)
    end

    private

    SECONDS_PER_DAY = 24 * 60 * 60
    private_constant :SECONDS_PER_DAY

    # Add 5 minutes to avoid scheduling exactly at slot time (API might not be ready yet)
    SAFETY_MARGIN_SECONDS = 5 * 60
    private_constant :SAFETY_MARGIN_SECONDS

    # Finds the next available slot today that matches the skip pattern
    #
    # The skip pattern is determined by calculate_skip_factor:
    # - skip_factor=1: use all slots (indices 0,1,2,3,...)
    # - skip_factor=2: use every 2nd slot (indices 0,2,4,6,...)
    # - skip_factor=12: use every 12th slot (indices 0,12)
    #
    # @param now [Time] current time
    # @return [Time, nil] next matching slot time, or nil if no more slots today
    def find_next_slot_today(now)
      skip_factor = calculate_skip_factor
      all_times = daily_slot_times(now)
      future_times = all_times.select { |time| time + SAFETY_MARGIN_SECONDS > now }

      future_times.each do |time|
        slot_index = all_times.index(time)
        return time + SAFETY_MARGIN_SECONDS if (slot_index % skip_factor).zero?
      end

      nil
    end

    # Converts SCHEDULED_SLOTS to absolute Time objects for a given day
    def daily_slot_times(now)
      SCHEDULED_SLOTS.map do |hour, minute|
        Time.utc(now.year, now.month, now.day, hour, minute, 0)
      end
    end

    # Returns the first slot time for tomorrow (with safety margin)
    def first_slot_tomorrow(now)
      one_day_later = now + SECONDS_PER_DAY
      first_hour, first_minute = SCHEDULED_SLOTS.first

      Time.utc(
        one_day_later.year, one_day_later.month, one_day_later.day,
        first_hour, first_minute, 0,
      ) + SAFETY_MARGIN_SECONDS
    end

    # Calculates the optimal skip factor to stay within monthly rate limit
    #
    # The skip_factor determines which slots to use:
    # - skip_factor=1: use all 16 slots per day (no skipping)
    # - skip_factor=2: use every 2nd slot (8 updates/day)
    # - skip_factor=3: use every 3rd slot (5-6 updates/day)
    # - skip_factor>16: triggers day-based scheduling in next_fetch_time
    #
    # Calculation logic:
    # 1. Determine how many slots we can afford per day: max_requests_per_month / 30 / required_requests
    # 2. If we can afford all 16 slots: return 1 (no optimization needed)
    # 3. If we can only afford 1 or fewer slots per day: use day-based scheduling (skip_factor=32)
    # 4. Otherwise: calculate how many slots to skip: 16 / max_slots_per_day (rounded up)
    #
    # @return [Integer] skip factor (1 = use all slots, >1 = skip slots)
    #
    # @example Paid account scenarios (1000 req/month, 16 slots/day available)
    #   1 request/update  → 1000/30/1 = 33 slots/day → skip_factor=1 (use all 16, well under limit)
    #   3 requests/update → 1000/30/3 = 11 slots/day → skip_factor=2 (use 8 slots = 720 req/month)
    #   5 requests/update → 1000/30/5 = 6 slots/day  → skip_factor=3 (use 5 slots = 750 req/month)
    #
    # @example Free account scenarios (40 req/month, 16 slots/day available)
    #   1 request/update  → 40/30/1 = 1.3 slots/day  → skip_factor=32 (use day-skip: 1x/day = 30 req/month)
    #   2 requests/update → 40/30/2 = 0.6 slots/day  → skip_factor=32 (use day-skip: 1x/2days = 30 req/month)
    def calculate_skip_factor
      # Calculate max slots per day to stay under monthly limit
      # Use 30 days as average month length, float division for precision
      max_slots_per_day = max_requests_per_month / 30.0 / required_requests_count

      # No optimization needed if we can afford all slots
      return 1 if max_slots_per_day >= 16

      # Calculate how many slots to skip to match our budget
      # Example: max_slots_per_day=8 → 16/8=2 → use every 2nd slot (8 updates/day)
      # Example: max_slots_per_day=1.33 → 16/1.33=12.03 → ceil=13 (not enough, would use 2 slots/day)
      #
      # Special case: If result would still use 2+ slots per day but budget allows <2,
      # we need to increase skip_factor to force day-based scheduling (skip_factor > 16)
      skip_factor = (16.0 / max_slots_per_day).ceil

      # Check if this skip_factor would still use too many slots per day
      # slots_per_day = 16 / skip_factor (rounded up because of modulo logic)
      # If slots_per_day > max_slots_per_day, we need a larger skip_factor
      if skip_factor <= 16
        slots_per_day = (16.0 / skip_factor).ceil
        # If we'd use more slots than budget allows, force day-based scheduling
        skip_factor *= 2 if slots_per_day > max_slots_per_day
      end

      skip_factor
    end
  end
end
