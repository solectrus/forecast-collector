# Calculates optimal fetch times for pvnode API to respect rate limits
#
# The pvnode API provides weather forecast data with different rate limits:
# - Free accounts: 40 requests/month
# - Paid accounts: 1500 requests/month
#
# The API updates forecast data 24 times per day (hourly).
# This class optimizes fetching by:
# - Calculating which slots to use based on rate limit and required requests
# - Skipping slots when necessary to stay within monthly quota
# - Using day-based scheduling for very restrictive limits

module Pvnode
  class Slots
    # Rate limits enforced by pvnode API
    MAX_REQUESTS_PER_MONTH_NOWCAST = 3_000 # Nowcast subscription
    MAX_REQUESTS_PER_MONTH_PAID    = 1_000 # Basic paid subscription
    MAX_REQUESTS_PER_MONTH_FREE    = 40    # Free tier

    SLOTS_PER_DAY = 24
    private_constant :SLOTS_PER_DAY

    # @param paid [Boolean] true for paid account, false for free account
    # @param nowcast [Boolean] true if the Nowcast subscription is in use
    # @param required_requests_count [Integer] number of API requests needed per update
    #   (e.g., 2 if we need to fetch data for 2 different plane configurations)
    def initialize(paid:, required_requests_count:, nowcast: false)
      @paid = paid
      @nowcast = nowcast
      @required_requests_count = required_requests_count
    end

    attr_reader :paid, :nowcast, :required_requests_count

    # Returns the applicable monthly rate limit based on subscription
    def max_requests_per_month
      return MAX_REQUESTS_PER_MONTH_NOWCAST if nowcast
      return MAX_REQUESTS_PER_MONTH_PAID if paid

      MAX_REQUESTS_PER_MONTH_FREE
    end

    # Returns the next optimal time to fetch data from pvnode API
    #
    # Strategy:
    # 1. Calculate skip_factor to determine which slots to use
    # 2. If rate limit is very restrictive (skip_factor > SLOTS_PER_DAY), schedule days ahead
    # 3. Otherwise, find next available slot today matching the skip pattern
    # 4. If no more slots today, use first slot tomorrow
    #
    # @return [Time] next fetch time in UTC
    def next_fetch_time
      skip_factor = calculate_skip_factor

      # For very restrictive rate limits: skip entire days
      if skip_factor > SLOTS_PER_DAY
        days_to_skip = (skip_factor.to_f / SLOTS_PER_DAY).ceil
        return Time.now.utc + (SECONDS_PER_DAY * days_to_skip)
      end

      # For normal rate limits: find next matching slot
      now = Time.now.utc
      next_slot = find_next_slot_today(now, skip_factor)
      return next_slot if next_slot

      # No more slots today: use first slot tomorrow
      first_slot_tomorrow(now)
    end

    private

    SECONDS_PER_DAY = 24 * 60 * 60
    private_constant :SECONDS_PER_DAY

    # pvnode data is ready at :40, fetch from :44 (4 min buffer)
    SAFETY_MARGIN_SECONDS = 44 * 60
    private_constant :SAFETY_MARGIN_SECONDS

    # Use 31 days (worst case) to never exceed monthly limits
    DAYS_PER_MONTH = 31
    private_constant :DAYS_PER_MONTH

    # Finds the next available slot today that matches the skip pattern
    #
    # The skip pattern is determined by calculate_skip_factor:
    # - skip_factor=1: use all slots (indices 0,1,2,3,...)
    # - skip_factor=2: use every 2nd slot (indices 0,2,4,6,...)
    # - skip_factor=12: use every 12th slot (indices 0,12)
    #
    # @param now [Time] current time
    # @param skip_factor [Integer] which slots to use
    # @return [Time, nil] next matching slot time, or nil if no more slots today
    def find_next_slot_today(now, skip_factor)
      SLOTS_PER_DAY.times do |hour|
        next unless (hour % skip_factor).zero?

        fetch_time = Time.utc(now.year, now.month, now.day, hour, 0, 0) + SAFETY_MARGIN_SECONDS
        return fetch_time if fetch_time > now
      end

      nil
    end

    # Returns the first slot time for tomorrow (with safety margin)
    def first_slot_tomorrow(now)
      one_day_later = now + SECONDS_PER_DAY

      Time.utc(
        one_day_later.year, one_day_later.month, one_day_later.day,
        0, 0, 0,
      ) + SAFETY_MARGIN_SECONDS
    end

    # Calculates the optimal skip factor to stay within monthly rate limit
    #
    # The skip_factor determines which slots to use:
    # - skip_factor=1: use all slots per day (no skipping)
    # - skip_factor=2: use every 2nd slot
    # - skip_factor>SLOTS_PER_DAY: triggers day-based scheduling in next_fetch_time
    #
    # @return [Integer] skip factor (1 = use all slots, >1 = skip slots)
    #
    # @example Paid account scenarios (1500 req/month, 24 slots/day available)
    #   1 request/update  → 1500/31/1 = 48 slots/day → skip_factor=1 (use all 24)
    #   2 requests/update → 1500/31/2 = 24 slots/day → skip_factor=1 (use all 24)
    #   3 requests/update → 1500/31/3 = 16 slots/day → skip_factor=2 (use 12 slots)
    #
    # @example Free account scenarios (40 req/month, 24 slots/day available)
    #   1 request/update  → 40/31/1 = 1.3 slots/day  → skip_factor=SLOTS_PER_DAY (1x/day)
    #   2 requests/update → 40/31/2 = 0.6 slots/day  → day-skip (1x/2days)
    def calculate_skip_factor
      max_slots_per_day = max_requests_per_month / DAYS_PER_MONTH.to_f / required_requests_count

      return 1 if max_slots_per_day >= SLOTS_PER_DAY

      # For budgets that can't afford even 1 slot per day, use day-based scheduling
      return (SLOTS_PER_DAY.to_f / max_slots_per_day).ceil if max_slots_per_day < 1

      # For very limited budgets (1-2 slots/day), use exactly 1 slot per day
      return SLOTS_PER_DAY if max_slots_per_day < 2

      # Calculate skip_factor to get at most max_slots_per_day slots
      target_slots = max_slots_per_day.floor
      ((SLOTS_PER_DAY - 1).to_f / (target_slots - 1)).ceil
    end
  end
end
