require 'adapter/pvnode/slots'

describe Pvnode::Slots do
  let(:slots) { described_class.new(max_requests_per_month:, required_requests_count:) }
  let(:max_requests_per_month) { 1_000 } # paid tier
  let(:required_requests_count) { 1 }

  describe '#next_fetch_time' do
    subject(:next_time) { slots.next_fetch_time }

    before { allow(Time).to receive(:now).and_return(now) }

    context 'with free account (1 request) when slot 0 has passed' do
      let(:max_requests_per_month) { 40 } # free tier
      let(:required_requests_count) { 1 }
      let(:now) { Time.utc(2025, 9, 30, 12, 0, 0) }

      it 'returns slot 0 tomorrow' do
        expect(next_time).to eq(Time.utc(2025, 10, 1, 0, 47, 0))
      end
    end

    context 'with free account (1 request) when slot 0 is still ahead' do
      let(:max_requests_per_month) { 40 } # free tier
      let(:required_requests_count) { 1 }
      let(:now) { Time.utc(2025, 9, 30, 0, 0, 0) }

      it 'returns slot 0 today' do
        expect(next_time).to eq(Time.utc(2025, 9, 30, 0, 47, 0))
      end
    end

    context 'with free account (2 requests)' do
      let(:max_requests_per_month) { 40 } # free tier
      let(:required_requests_count) { 2 }
      let(:now) { Time.utc(2025, 9, 30, 12, 0, 0) }

      it 'uses day-based skip for heavy rate limiting' do
        # 40/31/2 = 0.645 → skip_factor = ceil(24/0.645) = 38 (> 24)
        # days_to_skip = ceil(38/24) = 2
        expect(next_time).to eq(Time.utc(2025, 10, 2, 12, 0, 0))
      end
    end

    # Once-daily tier (slots_per_day = 1, e.g. v2 Free): fetch only once a day
    # instead of spending the larger request budget on redundant fetches.
    context 'with a once-daily tier before its slot' do
      let(:max_requests_per_month) { 250 }
      let(:slots) { described_class.new(max_requests_per_month:, required_requests_count:, slots_per_day: 1) }
      let(:now) { Time.utc(2025, 9, 30, 0, 0, 0) }

      it 'fetches once at 00:47' do
        expect(next_time).to eq(Time.utc(2025, 9, 30, 0, 47, 0))
      end
    end

    context 'with a once-daily tier after its slot' do
      let(:max_requests_per_month) { 250 }
      let(:slots) { described_class.new(max_requests_per_month:, required_requests_count:, slots_per_day: 1) }
      let(:now) { Time.utc(2025, 9, 30, 12, 0, 0) }

      it 'waits until 00:47 the next day instead of refetching' do
        expect(next_time).to eq(Time.utc(2025, 10, 1, 0, 47, 0))
      end
    end

    context 'with paid account: before first slot of the day' do
      let(:now) { Time.utc(2025, 9, 30, 0, 10, 0) }

      it 'returns slot 0 today at 00:47' do
        expect(next_time).to eq(Time.utc(2025, 9, 30, 0, 47, 0))
      end
    end

    context 'with paid account: next scheduled time is today at :47' do
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it { is_expected.to eq(Time.utc(2025, 9, 30, 3, 47, 0)) }
    end

    context 'with paid account: just after a slot' do
      let(:now) { Time.utc(2025, 9, 30, 4, 50, 0) }

      it { is_expected.to eq(Time.utc(2025, 9, 30, 5, 47, 0)) }
    end

    context 'with paid account: exactly at slot time' do
      let(:now) { Time.utc(2025, 9, 30, 3, 47, 0) }

      # At exactly 03:47, slot 03:00+47min is no longer in the future
      # → next slot is 04:47
      it { is_expected.to eq(Time.utc(2025, 9, 30, 4, 47, 0)) }
    end

    context 'with paid account: one second before slot time' do
      let(:now) { Time.utc(2025, 9, 30, 3, 46, 59) }

      # 03:47 > 03:46:59 → slot 03:47 is still available
      it { is_expected.to eq(Time.utc(2025, 9, 30, 3, 47, 0)) }
    end

    context 'with paid account: all times passed today' do
      let(:now) { Time.utc(2025, 9, 30, 23, 50, 0) }

      it { is_expected.to eq(Time.utc(2025, 10, 1, 0, 47, 0)) }
    end

    context 'with paid account: crossing month boundary' do
      let(:now) { Time.utc(2025, 1, 31, 23, 50, 0) }

      it { is_expected.to eq(Time.utc(2025, 2, 1, 0, 47, 0)) }
    end

    context 'with paid account: crossing year boundary' do
      let(:now) { Time.utc(2025, 12, 31, 23, 50, 0) }

      it { is_expected.to eq(Time.utc(2026, 1, 1, 0, 47, 0)) }
    end

    context 'with paid account: 1 request batch (no rate limiting)' do
      let(:required_requests_count) { 1 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses all 24 updates per day (skip_factor = 1)' do
        expect(next_time).to eq(Time.utc(2025, 9, 30, 3, 47, 0))
      end
    end

    context 'with paid account: 2 request batches (rate limiting)' do
      let(:required_requests_count) { 2 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses skip_factor = 2 for 16 updates/day' do
        # 1000/31/2 = 16.13 → skip_factor = ceil(23/15) = 2
        # At 03:00, slot 3 is odd → skip, slot 4 (04:47) is even → use it
        expect(next_time).to eq(Time.utc(2025, 9, 30, 4, 47, 0))
      end
    end

    context 'with paid account: 3 request batches (rate limiting)' do
      let(:required_requests_count) { 3 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses skip_factor = 3 for 10 updates/day' do
        # 1000/31/3 = 10.75 → skip_factor = ceil(23/9) = 3
        # At 03:00, slot 3 % 3 = 0 → use it
        expect(next_time).to eq(Time.utc(2025, 9, 30, 3, 47, 0))
      end
    end

    context 'with paid account: 4 request batches (rate limiting)' do
      let(:required_requests_count) { 4 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses skip_factor = 4 for 8 updates/day' do
        # 1000/31/4 = 8.06 → skip_factor = ceil(23/7) = 4
        # At 03:00, slot 3 % 4 != 0 → skip, slot 4 (04:47) is valid
        expect(next_time).to eq(Time.utc(2025, 9, 30, 4, 47, 0))
      end
    end

    context 'with paid account: 5 request batches (rate limiting)' do
      let(:required_requests_count) { 5 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses skip_factor = 5 to stay under limit' do
        # 1000/31/5 = 6.45 → skip_factor = ceil(23/5) = 5
        # At 03:00, slot 3 % 5 != 0 → skip, slot 5 (05:47) is valid
        expect(next_time).to eq(Time.utc(2025, 9, 30, 5, 47, 0))
      end
    end
  end

  describe 'monthly rate limit compliance' do
    # Verifies that no configuration ever exceeds the monthly limit,
    # even in worst case (31-day month)
    [
      { paid: true, requests: 1, limit: 1000 },
      { paid: true, requests: 2, limit: 1000 },
      { paid: true, requests: 3, limit: 1000 },
      { paid: true, requests: 4, limit: 1000 },
      { paid: true, requests: 5, limit: 1000 },
      { paid: true, requests: 6, limit: 1000 },
      { paid: false, requests: 1, limit: 40 },
      { paid: false, requests: 2, limit: 40 },
      { paid: false, requests: 3, limit: 40 },
      { paid: false, requests: 4, limit: 40 },
    ].each do |scenario|
      context "with #{scenario[:paid] ? 'paid' : 'free'} account (#{scenario[:requests]} requests/update)" do
        let(:max_requests_per_month) { scenario[:limit] }
        let(:required_requests_count) { scenario[:requests] }

        it "stays within #{scenario[:limit]} requests/month" do
          skip_factor = slots.send(:calculate_skip_factor)
          slots_per_day = 24

          updates_per_day =
            if skip_factor > slots_per_day
              days_to_skip = (skip_factor.to_f / slots_per_day).ceil
              1.0 / days_to_skip
            elsif skip_factor == slots_per_day
              1
            else
              (0...slots_per_day).count { |i| (i % skip_factor).zero? }
            end

          # Worst case: 31-day month, round up partial updates
          monthly_requests = (updates_per_day * scenario[:requests] * 31).ceil

          expect(monthly_requests).to be <= scenario[:limit],
                                      "Expected <= #{scenario[:limit]} requests/month, " \
                                      "got #{monthly_requests} (#{updates_per_day} updates/day × " \
                                      "#{scenario[:requests]} req × 31 days, skip_factor=#{skip_factor})"
        end
      end
    end
  end
end
