require 'duration'
require 'adapter/pvnode/timestamp'

module Pvnode
  # Decides when to request the pvnode v2 forecast API again.
  #
  # The API calculates a forecast on demand and caches it. With `next_poll_at`
  # it tells the client when a request returns something newer. An earlier
  # request costs quota and returns the same cached data. The server knows the
  # plan of the user, so the collector follows this recommendation instead of
  # calculating an interval itself.
  #
  # A self-imposed monthly limit (PVNODE_REQUEST_LIMIT) applies on top of the
  # recommendation. It keeps requests free for other tools on the same pvnode
  # account and can only delay a request, never make it earlier.
  #
  # If there is no usable recommendation, because the request failed or the
  # response carried none, the schedule falls back to an interval of its own.
  # This interval is never shorter than 15 minutes, so an error cannot cause a
  # fast request loop.
  class PollSchedule
    # Shortest interval the fallback calculates. The API advertises its update
    # slots on a 15-minute grid, so a shorter interval cannot find new data.
    MIN_INTERVAL = 15.minutes
    private_constant :MIN_INTERVAL

    # Used when the API sends neither a recommendation nor a quota.
    DEFAULT_INTERVAL = 1.hour
    private_constant :DEFAULT_INTERVAL

    # Added to the recommendation of the API. Without it a request can land
    # just before the slot boundary and get the previous answer again, which
    # costs a request for data the collector already has.
    POLL_OFFSET = 30.seconds
    private_constant :POLL_OFFSET

    # Shortest delay the recommendation can ask for. It stops a recommendation
    # that is almost due from becoming a fast request loop. The offset comes on
    # top of it.
    MIN_DELAY = 1.minute
    private_constant :MIN_DELAY

    # Longest time between two attempts. The quota resets only at the start of
    # the next month, which can be weeks away. A daily attempt shows that the
    # collector is alive and lets it recover without a restart if the plan
    # changes. A self-imposed limit still applies on top and can wait longer.
    MAX_WAIT = 1.day
    private_constant :MAX_WAIT

    # Delay after the quota reset, so the counter is really back to zero.
    RESET_MARGIN = 1.minute
    private_constant :RESET_MARGIN

    # Worst case, so a self-imposed limit holds in every month.
    DAYS_PER_MONTH = 31
    private_constant :DAYS_PER_MONTH

    # @param request_limit_per_month [Integer, nil] self-imposed limit, in
    #   requests per month
    def initialize(request_limit_per_month: nil)
      @request_limit_per_month = request_limit_per_month
    end

    attr_reader :request_limit

    # Records that a request was sent. This happens for every request, also for
    # a failed one, so an error cannot cause a fast retry loop.
    def record_attempt
      @last_attempt_at = Time.now.utc
    end

    # Records the quota headers of a response. They also come with the 429 that
    # reports an exhausted quota.
    #
    # A response without the headers does not come from the pvnode API, for
    # example an error of a proxy. It says nothing about the quota, so the last
    # known quota stays.
    def record_request_limit(request_limit)
      @request_limit = request_limit if request_limit
    end

    # Records the recommendation of a successful response. A recommendation the
    # collector cannot read is dropped, not raised: the schedule then falls back
    # to its own interval, and the forecast data of the response stays usable.
    def record_recommendation(next_poll_at)
      @next_poll_at = Timestamp.parse_or_nil(next_poll_at)
    end

    def next_fetch_time
      [recommended_time, self_imposed_time, Time.now.utc + 1].compact.max
    end

    # Human-readable schedule for the startup message.
    def message
      message = 'when the API recommends it (next_poll_at)'
      return message unless request_limit_per_month

      "#{message}, limited to #{request_limit_per_month} requests per month"
    end

    private

    attr_reader :request_limit_per_month, :next_poll_at, :last_attempt_at

    def now
      Time.now.utc
    end

    # When the API allows a newer result. An exhausted quota wins, because
    # every request until the reset returns an error.
    def recommended_time
      return quota_reset_time if request_limit&.exhausted? && request_limit.reset_at

      future_recommendation || fallback_time
    end

    def quota_reset_time
      [request_limit.reset_at + RESET_MARGIN, now + MAX_WAIT].min
    end

    # A recommendation in the past is not usable. It belongs to a response that
    # is already too old, for example because the requests after it failed.
    #
    # The range keeps a recommendation usable that the collector cannot trust.
    # The API can only recommend, so a value that is almost due or years away
    # must not decide the schedule alone. The offset comes after the range, so
    # a plan with one update per day keeps it.
    def future_recommendation
      return unless next_poll_at && next_poll_at > now

      now + (next_poll_at - now).clamp(MIN_DELAY, MAX_WAIT) + POLL_OFFSET
    end

    # Used without a usable recommendation. The interval starts at the last
    # attempt, so repeated errors cannot cause a fast retry loop.
    def fallback_time
      (last_attempt_at || now) + fallback_interval
    end

    # The earliest time the self-imposed limit allows, nil if there is none. It
    # spreads the monthly limit evenly over a month.
    def self_imposed_time
      return unless request_limit_per_month

      (last_attempt_at || now) + (DAYS_PER_MONTH.days / request_limit_per_month)
    end

    # Spreads the requests that are left evenly over the rest of the month.
    def fallback_interval
      return DEFAULT_INTERVAL unless spreadable_quota?

      seconds_left = request_limit.reset_at - now
      return DEFAULT_INTERVAL unless seconds_left.positive?

      (seconds_left / request_limit.remaining).clamp(MIN_INTERVAL, MAX_WAIT)
    end

    # A plan without a cap has no number to spread, so the default interval
    # applies there.
    def spreadable_quota?
      request_limit&.metered? && request_limit.reset_at && request_limit.remaining.positive?
    end
  end
end
