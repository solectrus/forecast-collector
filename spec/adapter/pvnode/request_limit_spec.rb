require 'net/http'
require 'adapter/pvnode/request_limit'

describe Pvnode::RequestLimit do
  subject(:request_limit) { described_class.from_response(response) }

  let(:response) { build_response(headers) }
  let(:headers) do
    {
      'RequestLimit-Limit' => '3000',
      'RequestLimit-Remaining' => '2769',
      'RequestLimit-Reset' => '2026-09-01T00:00:00Z',
    }
  end

  def build_response(headers)
    instance_double(Net::HTTPOK).tap do |response|
      allow(response).to receive(:[]) { |key| headers[key] }
    end
  end

  describe '.from_response' do
    it 'reads the quota from the headers' do
      expect(request_limit).to have_attributes(
        limit: 3000,
        remaining: 2769,
        reset_at: Time.utc(2026, 9, 1),
      )
    end

    context 'without quota headers' do
      let(:headers) { {} }

      it 'returns nil' do
        expect(request_limit).to be_nil
      end
    end

    context 'with an unparsable counter' do
      let(:headers) { super().merge('RequestLimit-Remaining' => 'plenty') }

      it 'returns nil, because the quota is unusable' do
        expect(request_limit).to be_nil
      end
    end

    # A plan without a cap sends the literal string instead of a number.
    # See https://pvnode.com/docs/v2/integrations/build-your-own
    context 'with an unmetered quota' do
      let(:headers) do
        super().merge('RequestLimit-Limit' => 'unmetered', 'RequestLimit-Remaining' => 'unmetered')
      end

      it 'reports a quota without numbers' do
        expect(request_limit).to have_attributes(
          metered?: false,
          limit: nil,
          remaining: nil,
          reset_at: Time.utc(2026, 9, 1),
        )
      end
    end

    context 'with only the remaining counter unmetered' do
      let(:headers) { super().merge('RequestLimit-Remaining' => 'unmetered') }

      it 'reports a quota without numbers, because no cap can be counted' do
        expect(request_limit).to have_attributes(metered?: false, limit: nil)
      end
    end

    context 'with only the limit unmetered' do
      let(:headers) { super().merge('RequestLimit-Limit' => 'unmetered') }

      it 'reports a quota without numbers too' do
        expect(request_limit).to have_attributes(metered?: false, remaining: nil)
      end
    end

    context 'with an unparsable reset timestamp' do
      let(:headers) { super().merge('RequestLimit-Reset' => 'soon') }

      it 'keeps the counters' do
        expect(request_limit).to have_attributes(remaining: 2769, reset_at: nil)
      end
    end
  end

  describe '#exhausted?' do
    it 'is false while requests are left' do
      expect(request_limit).not_to be_exhausted
    end

    context 'with an unmetered quota' do
      let(:headers) { super().merge('RequestLimit-Remaining' => 'unmetered') }

      it 'is false, because there is no cap to reach' do
        expect(request_limit).not_to be_exhausted
      end
    end

    context 'when no requests are left' do
      let(:headers) { super().merge('RequestLimit-Remaining' => '0') }

      it 'is true' do
        expect(request_limit).to be_exhausted
      end
    end
  end

  describe '#low?' do
    it 'is false while more than 10% of the quota is left' do
      expect(request_limit).not_to be_low
    end

    context 'with an unmetered quota' do
      let(:headers) { super().merge('RequestLimit-Remaining' => 'unmetered') }

      it 'is false, because there is no cap to run out of' do
        expect(request_limit).not_to be_low
      end
    end

    context 'when less than 10% of the quota is left' do
      let(:headers) { super().merge('RequestLimit-Remaining' => '299') }

      it 'is true' do
        expect(request_limit).to be_low
      end
    end

    context 'when the quota is exhausted' do
      let(:headers) { super().merge('RequestLimit-Remaining' => '0') }

      it 'is false, because exhausted is reported instead' do
        expect(request_limit).not_to be_low
      end
    end
  end

  describe '#to_s' do
    it 'reports the remaining requests and the reset date' do
      expect(request_limit.to_s).to eq(
        '2769 of 3000 requests left this month, resets 2026-09-01 00:00 UTC',
      )
    end

    context 'without a reset date' do
      let(:headers) { super().merge('RequestLimit-Reset' => 'no date') }

      it 'reports the remaining requests only' do
        expect(request_limit.to_s).to eq('2769 of 3000 requests left this month')
      end
    end

    context 'with an unmetered quota' do
      let(:headers) { super().merge('RequestLimit-Remaining' => 'unmetered') }

      it 'reports that there is no cap' do
        expect(request_limit.to_s).to eq('unmetered')
      end
    end
  end
end
