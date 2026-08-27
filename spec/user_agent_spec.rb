require 'user_agent'

describe UserAgent do
  describe '.current' do
    subject(:current) do
      ClimateControl.modify(COMMIT_VERSION: commit_version, VERSION: nil) do
        described_class.current
      end
    end

    context 'with a version' do
      let(:commit_version) { 'v0.10.1-3-g2d8f177' }

      it 'names the collector, the version and the homepage' do
        expect(current).to eq(
          'Forecast-Collector/v0.10.1-3-g2d8f177 (+https://github.com/solectrus/forecast-collector)',
        )
      end
    end

    context 'without a version' do
      # A build outside CI carries no version. The header must stay valid, so
      # the identifier drops the version instead of showing an empty one.
      let(:commit_version) { nil }

      it 'names the collector and the homepage' do
        expect(current).to eq('Forecast-Collector (+https://github.com/solectrus/forecast-collector)')
      end
    end
  end
end
