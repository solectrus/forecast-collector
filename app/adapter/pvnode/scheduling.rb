require 'adapter/pvnode/slots'
require 'adapter/pvnode/nowcast'

module Pvnode
  # Scheduling policy shared by the pvnode adapters: picks the subscription
  # tier, derives the monthly request budget from it (optionally narrowed by a
  # self-imposed limit) and wires up the slot/Nowcast schedulers.
  #
  # The tier values themselves live in the including class (TIERS), since v1 and
  # v2 share the tier names but not their limits.
  module Scheduling
    # The slot scheduler fetches at most hourly; higher-frequency tiers rely on
    # the Nowcast scheduler for sub-hourly updates.
    MAX_SLOTS_PER_DAY = 24

    def next_fetch_time
      nowcast&.next_fetch_time || slots.next_fetch_time
    end

    def pull_interval_message
      [schedule_message, request_limit_message].compact.join(', ')
    end

    private

    def schedule_message
      if nowcast?
        "in Nowcast mode (every #{nowcast.interval_minutes} min during daylight, slot-based at night)"
      else
        'on provider schedule (auto)'
      end
    end

    # A configured request limit is always reported, including when it exceeds
    # the limit of the subscription tier and therefore has no effect.
    def request_limit_message
      limit = config.pvnode_request_limit
      return unless limit
      return "limited to #{limit} requests per month" if limit <= tier_limit

      "WARNING: PVNODE_REQUEST_LIMIT=#{limit} ignored, " \
        "your plan allows only #{tier_limit} requests per month"
    end

    def slots
      @slots ||= Pvnode::Slots.new(
        max_requests_per_month:,
        required_requests_count:,
        slots_per_day:,
      )
    end

    def nowcast
      return unless nowcast?

      @nowcast ||= Pvnode::Nowcast.new(
        slots:,
        required_requests_count:,
        max_requests_per_month:,
      )
    end

    def nowcast?
      config.pvnode_nowcast == true
    end

    def paid?
      config.pvnode_paid == true
    end

    # The active subscription tier. Reads the including class's TIERS, so v1 and
    # v2 share the tier names (free/light/plus) but define their own values.
    def tier
      return self.class::TIERS.fetch(:plus) if nowcast?
      return self.class::TIERS.fetch(:light) if paid?

      self.class::TIERS.fetch(:free)
    end

    # Monthly request budget of the active subscription tier.
    def tier_limit
      tier.fetch(:requests_per_month)
    end

    # Monthly request budget the scheduling is based on: the tier's limit,
    # unless PVNODE_REQUEST_LIMIT sets a lower one to leave requests for other
    # consumers of the same pvnode account.
    def max_requests_per_month
      [tier_limit, config.pvnode_request_limit].compact.min
    end

    # How often the slot scheduler should fetch per day, capped at hourly: tiers
    # that update less often (v2 Free: once daily) fetch correspondingly less,
    # while sub-hourly nowcast updates are handled by the Nowcast scheduler.
    # Tiers without a documented update frequency fall back to the hourly grid.
    def slots_per_day
      [tier.fetch(:updates_per_day, MAX_SLOTS_PER_DAY), MAX_SLOTS_PER_DAY].min
    end
  end
end
