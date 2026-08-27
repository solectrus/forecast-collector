require 'duration'
require 'adapter/pvnode/poll_schedule'
require 'adapter/pvnode/request_limit'

describe Pvnode::PollSchedule do
  subject(:schedule) { described_class.new(request_limit_per_month:) }

  let(:request_limit_per_month) { nil }
  let(:now) { Time.utc(2026, 8, 24, 14, 47, 41) }

  before { allow(Time).to receive(:now).and_return(now) }

  def build_request_limit(limit: 3000, remaining: 2769, reset_at: '2026-09-01T00:00:00Z')
    Pvnode::RequestLimit.new(
      limit:,
      remaining:,
      reset_at: reset_at && Time.iso8601(reset_at),
    )
  end

  # Records a complete request cycle, as the adapter does it.
  def fetch(next_poll_at:, request_limit: build_request_limit)
    schedule.record_attempt
    schedule.record_request_limit(request_limit)
    schedule.record_recommendation(next_poll_at)
  end

  describe '#next_fetch_time' do
    it 'follows the recommendation of the API, with a small offset' do
      # The offset keeps the request away from the slot boundary, where the API
      # would still return the previous answer.
      fetch(next_poll_at: '2026-08-24T15:00:00Z')

      expect(schedule.next_fetch_time).to eq(Time.utc(2026, 8, 24, 15, 0, 30))
    end

    it 'waits at least a minute when the recommendation is nearly due' do
      fetch(next_poll_at: '2026-08-24T14:47:42Z')

      expect(schedule.next_fetch_time).to eq(now + 60 + 30)
    end

    it 'waits at most a day when the recommendation is far away' do
      # The API can only recommend. A value this far away is a fault, and the
      # collector must not go silent because of it.
      fetch(next_poll_at: '2099-01-01T00:00:00Z')

      expect(schedule.next_fetch_time).to eq(now + 1.day + 30)
    end

    it 'keeps the offset on a plan with one update per day' do
      # Exactly a day away, so the offset must survive the upper limit.
      fetch(next_poll_at: '2026-08-25T14:47:41Z')

      expect(schedule.next_fetch_time).to eq(now + 1.day + 30)
    end

    it 'keeps the recommendation even when it is less than 15 minutes away' do
      # The collector polls a bit after the slot, so the next slot can be
      # closer than the grid of the API. Delaying it would drift into the
      # following slot with every cycle.
      fetch(next_poll_at: '2026-08-24T14:50:00Z')

      expect(schedule.next_fetch_time).to eq(Time.utc(2026, 8, 24, 14, 50, 30))
    end

    it 'converts a recommendation with an offset to UTC' do
      fetch(next_poll_at: '2026-08-24T17:00:00+02:00')

      expect(schedule.next_fetch_time).to eq(Time.utc(2026, 8, 24, 15, 0, 30))
    end

    context 'without a usable recommendation' do
      it 'spreads the requests that are left over the rest of the month' do
        # 2769 requests in the remaining 7 days is one request every 3 minutes,
        # so the 15-minute minimum applies
        fetch(next_poll_at: nil)

        expect(schedule.next_fetch_time).to eq(now + 15.minutes)
      end

      it 'fetches less often when few requests are left' do
        fetch(next_poll_at: nil, request_limit: build_request_limit(remaining: 8))

        seconds_left = Time.utc(2026, 9, 1) - now
        expect(schedule.next_fetch_time).to eq(now + (seconds_left / 8))
      end

      it 'waits at most a day, even with a single request left' do
        fetch(next_poll_at: nil, request_limit: build_request_limit(remaining: 1))

        expect(schedule.next_fetch_time).to eq(now + 1.day)
      end

      it 'waits an hour when the quota reset is already due' do
        # The API sends the reset of the running month, so a reset in the past
        # means the headers are stale. There is nothing to spread over.
        fetch(next_poll_at: nil, request_limit: build_request_limit(reset_at: '2026-08-24T14:00:00Z'))

        expect(schedule.next_fetch_time).to eq(now + 1.hour)
      end

      it 'waits an hour without a quota to spread' do
        fetch(next_poll_at: nil, request_limit: nil)

        expect(schedule.next_fetch_time).to eq(now + 1.hour)
      end

      it 'waits an hour on a plan without a cap' do
        # An unmetered plan reports no numbers, so there is nothing to spread.
        fetch(next_poll_at: nil, request_limit: build_request_limit(limit: nil, remaining: nil))

        expect(schedule.next_fetch_time).to eq(now + 1.hour)
      end

      it 'ignores a recommendation without a timezone' do
        # It would be read as machine-local time. The forecast data of the
        # response stays usable.
        fetch(next_poll_at: '2026-08-24T15:00:00', request_limit: nil)

        expect(schedule.next_fetch_time).to eq(now + 1.hour)
      end

      it 'ignores a recommendation that is already in the past' do
        fetch(next_poll_at: '2026-08-24T14:00:00Z', request_limit: nil)

        expect(schedule.next_fetch_time).to eq(now + 1.hour)
      end
    end

    context 'when the quota is exhausted' do
      it 'waits until the counter resets' do
        fetch(
          next_poll_at: '2026-08-24T15:00:00Z',
          request_limit: build_request_limit(remaining: 0, reset_at: '2026-08-25T00:00:00Z'),
        )

        expect(schedule.next_fetch_time).to eq(Time.utc(2026, 8, 25, 0, 1, 0))
      end

      it 'tries again the next day when the reset is further away' do
        # The reset is 7 days away here. Waiting that long in one piece hides
        # a plan change and makes the collector look dead.
        fetch(
          next_poll_at: '2026-08-24T15:00:00Z',
          request_limit: build_request_limit(remaining: 0),
        )

        expect(schedule.next_fetch_time).to eq(now + 1.day)
      end

      it 'keeps the quota when a later response carries no headers' do
        fetch(
          next_poll_at: '2026-08-24T15:00:00Z',
          request_limit: build_request_limit(remaining: 0, reset_at: '2026-08-25T00:00:00Z'),
        )

        # An error of a proxy, for example, carries no quota headers
        schedule.record_attempt
        schedule.record_request_limit(nil)

        expect(schedule.next_fetch_time).to eq(Time.utc(2026, 8, 25, 0, 1, 0))
      end

      it 'keeps a self-imposed limit that waits even longer' do
        schedule = described_class.new(request_limit_per_month: 10)
        schedule.record_attempt
        schedule.record_request_limit(build_request_limit(remaining: 0))

        # 10 requests spread over 31 days is one request every 3 days
        expect(schedule.next_fetch_time).to eq(now + (31.days / 10))
      end
    end

    context 'when the request failed' do
      it 'waits at least 15 minutes, so errors cannot cause a request loop' do
        # A failed request records the attempt only
        schedule.record_attempt

        expect(schedule.next_fetch_time).to eq(now + 1.hour)
      end
    end

    context 'with a self-imposed limit' do
      let(:request_limit_per_month) { 200 }

      it 'delays the recommendation to stay inside the limit' do
        fetch(next_poll_at: '2026-08-24T15:00:00Z')

        # 200 requests spread over 31 days is one request every 13392 seconds
        expect(schedule.next_fetch_time).to eq(now + 13_392)
      end

      it 'keeps the recommendation when it is later than the limit allows' do
        fetch(next_poll_at: '2026-08-24T20:00:00Z')

        expect(schedule.next_fetch_time).to eq(Time.utc(2026, 8, 24, 20, 0, 30))
      end
    end

    it 'starts the fallback interval at the last attempt, not at the check' do
      # Repeated errors must not cause a fast request loop. The interval counts
      # from the attempt, so asking again later does not move the next fetch.
      fetch(next_poll_at: nil, request_limit: nil)
      allow(Time).to receive(:now).and_return(now + 30.minutes)

      expect(schedule.next_fetch_time).to eq(now + 1.hour)
    end

    it 'starts the self-imposed interval at the last attempt too' do
      schedule = described_class.new(request_limit_per_month: 200)
      schedule.record_attempt
      allow(Time).to receive(:now).and_return(now + 30.minutes)

      # 200 requests spread over 31 days is one request every 13392 seconds
      expect(schedule.next_fetch_time).to eq(now + 13_392)
    end

    it 'never returns a time in the past' do
      # A fetch that took longer than the interval
      schedule.record_attempt
      allow(Time).to receive(:now).and_return(now + 3.hours)

      expect(schedule.next_fetch_time).to be > Time.now.utc
    end
  end

  describe '#message' do
    it 'announces the schedule of the API' do
      expect(schedule.message).to eq('when the API recommends it (next_poll_at)')
    end

    context 'with a self-imposed limit' do
      let(:request_limit_per_month) { 200 }

      it 'mentions the limit' do
        expect(schedule.message).to eq(
          'when the API recommends it (next_poll_at), limited to 200 requests per month',
        )
      end
    end
  end
end
