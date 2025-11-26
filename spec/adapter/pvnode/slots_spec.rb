require 'adapter/pvnode/slots'

describe Pvnode::Slots do
  let(:slots) { described_class.new(paid:, required_requests_count:) }
  let(:paid) { true }
  let(:required_requests_count) { 1 }

  describe '#next_fetch_time' do
    subject(:next_time) { slots.next_fetch_time }

    before { allow(Time).to receive(:now).and_return(now) }

    context 'with free account (1 request)' do
      let(:paid) { false }
      let(:required_requests_count) { 1 }
      let(:now) { Time.utc(2025, 9, 30, 12, 0, 0) }

      it 'uses exactly 1 slot per day (skip_factor 16)' do
        # 40 req/month ÷ 30 days ÷ 1 request = 1.33 updates/day
        # Since < 2, use skip_factor=16 → only slot 0 (01:05 UTC) each day
        # At 12:00, slot 0 has passed → use slot 0 tomorrow
        expect(next_time).to eq(Time.utc(2025, 10, 1, 1, 5, 0))
      end
    end

    context 'with free account (2 requests)' do
      let(:paid) { false }
      let(:required_requests_count) { 2 }
      let(:now) { Time.utc(2025, 9, 30, 12, 0, 0) }

      it 'uses day-based skip for heavy rate limiting' do
        # 40 req/month ÷ 30 days ÷ 2 requests = 0.66 updates/day
        # This means we need to skip multiple days
        # skip_factor = 16 / 0.66 = 24 (> 16)
        # days_to_skip = ceil(24 / 16) = 2 days
        expect(next_time).to eq(Time.utc(2025, 10, 2, 12, 0, 0))
      end
    end

    context 'with paid account: next scheduled time is today at :05' do
      let(:paid) { true }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it { is_expected.to eq(Time.utc(2025, 9, 30, 4, 5, 0)) }
    end

    context 'with paid account: next scheduled time is today at :35' do
      let(:paid) { true }
      let(:now) { Time.utc(2025, 9, 30, 4, 15, 0) }

      it { is_expected.to eq(Time.utc(2025, 9, 30, 4, 35, 0)) }
    end

    context 'with paid account: all times passed today' do
      let(:paid) { true }
      let(:now) { Time.utc(2025, 9, 30, 23, 0, 0) }

      it { is_expected.to eq(Time.utc(2025, 10, 1, 1, 5, 0)) }
    end

    context 'with paid account: crossing month boundary' do
      let(:paid) { true }
      let(:now) { Time.utc(2025, 1, 31, 23, 0, 0) }

      it { is_expected.to eq(Time.utc(2025, 2, 1, 1, 5, 0)) }
    end

    context 'with paid account: crossing year boundary' do
      let(:paid) { true }
      let(:now) { Time.utc(2025, 12, 31, 23, 0, 0) }

      it { is_expected.to eq(Time.utc(2026, 1, 1, 1, 5, 0)) }
    end

    context 'with paid account: 1 request batch (no rate limiting)' do
      let(:paid) { true }
      let(:required_requests_count) { 1 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses all 16 updates per day (skip_factor = 1)' do
        # Should use next available slot without skipping
        expect(next_time).to eq(Time.utc(2025, 9, 30, 4, 5, 0))
      end
    end

    context 'with paid account: 2 request batches (no rate limiting)' do
      let(:paid) { true }
      let(:required_requests_count) { 2 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses all 16 updates per day (skip_factor = 1)' do
        # 1000 requests/month ÷ 30 days ÷ 2 batches = 16.66 → 16 updates/day max
        # 16 daily slots ÷ 16 = 1 (no skipping)
        expect(next_time).to eq(Time.utc(2025, 9, 30, 4, 5, 0))
      end
    end

    context 'with paid account: 3 request batches (rate limiting)' do
      let(:paid) { true }
      let(:required_requests_count) { 3 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'skips every other update (skip_factor = 2)' do
        # 1000 requests/month ÷ 30 days ÷ 3 batches = 11.11 → 11 updates/day max
        # 16 daily slots ÷ 11 = 1.45 → ceil = 2 (skip every other slot)
        # At 03:00, next slot is 04:05 (index 2)
        # Slot 2 % 2 = 0 → use it
        expect(next_time).to eq(Time.utc(2025, 9, 30, 4, 5, 0))
      end
    end

    context 'with paid account: 4 request batches (rate limiting)' do
      let(:paid) { true }
      let(:required_requests_count) { 4 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses skip_factor = 3 for 6 updates/day' do
        # 1000 requests/month ÷ 30 days ÷ 4 batches = 8.33 → target 8 slots/day
        # skip_factor = ceil(15/7) = 3 → uses slots 0,3,6,9,12,15 = 6 slots/day
        # At 03:00, next slots are: index 2 (04:05), index 3 (04:35)
        # Slot 2 % 3 = 2 → skip, Slot 3 % 3 = 0 → use it
        expect(next_time).to eq(Time.utc(2025, 9, 30, 4, 35, 0))
      end
    end

    context 'with paid account: 5 request batches (heavy rate limiting)' do
      let(:paid) { true }
      let(:required_requests_count) { 5 }
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it 'uses skip_factor = 3 to stay under limit' do
        # 1000 requests/month ÷ 30 days ÷ 5 batches = 6.66 → 6 updates/day max
        # 16 daily slots ÷ 6 = 2.66 → ceil = 3 (use every 3rd slot)
        # At 03:00, next slots are: index 2 (04:05), index 3 (04:35)
        # Slot 2 % 3 = 2 → skip
        # Slot 3 % 3 = 0 → use it
        expect(next_time).to eq(Time.utc(2025, 9, 30, 4, 35, 0))
      end
    end
  end
end
