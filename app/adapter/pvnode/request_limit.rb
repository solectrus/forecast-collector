require 'adapter/pvnode/timestamp'

module Pvnode
  # Monthly request quota of the pvnode v2 API, taken from the `RequestLimit-*`
  # response headers.
  #
  # The quota counts per user and endpoint. If the same pvnode account is used
  # by other tools (evcc, Home Assistant, ...), their requests count too.
  class RequestLimit
    # Value the API sends instead of a number on a plan without a cap.
    # Documented at https://pvnode.com/docs/v2/integrations/build-your-own
    UNMETERED = 'unmetered'.freeze
    private_constant :UNMETERED

    # Warn as soon as less than this part of the monthly quota is left.
    LOW_WATERMARK = 0.1
    private_constant :LOW_WATERMARK

    # Reads the quota from a HTTP response. Returns nil if the response carries
    # no usable quota, for example the v1 API or an error from a proxy. The
    # reset date is optional, the two counters are not: without them the
    # schedule cannot spread the requests that are left.
    #
    # On a plan without a cap the counters read `unmetered` instead of a
    # number. Then the quota exists, but has no numbers to report.
    def self.from_response(http_response)
      limit = http_response['RequestLimit-Limit']
      remaining = http_response['RequestLimit-Remaining']
      return unless limit && remaining

      reset_at = Timestamp.parse_or_nil(http_response['RequestLimit-Reset'])

      # One counter is enough to know that the plan has no cap. The other one
      # cannot carry a meaningful number then.
      return new(limit: nil, remaining: nil, reset_at:) if [limit, remaining].include?(UNMETERED)

      # A number cap needs both counters. If one of them is unreadable, the
      # quota is unusable and the schedule falls back to its own interval.
      limit = Integer(limit, exception: false)
      remaining = Integer(remaining, exception: false)
      return unless limit && remaining

      new(limit:, remaining:, reset_at:)
    end

    # @param limit [Integer, nil] nil on a plan without a cap
    # @param remaining [Integer, nil] nil on a plan without a cap
    def initialize(limit:, remaining:, reset_at:)
      @limit = limit
      @remaining = remaining
      @reset_at = reset_at
    end

    attr_reader :limit, :remaining, :reset_at

    # False on a plan without a cap: there is no number to count down.
    def metered?
      !remaining.nil?
    end

    def exhausted?
      metered? && !remaining.positive?
    end

    def low?
      metered? && !exhausted? && remaining < limit * LOW_WATERMARK
    end

    def to_s
      return 'unmetered' unless metered?

      "#{remaining} of #{limit} requests left this month#{reset_message}"
    end

    private

    def reset_message
      return '' unless reset_at

      ", resets #{reset_at.utc.strftime('%Y-%m-%d %H:%M UTC')}"
    end
  end
end
