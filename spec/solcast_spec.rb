require 'adapter/solcast_adapter'

describe SolcastAdapter do
  describe '#fetch_data' do
    let(:config) { Config.from_env(forecast_provider: 'solcast') }
    let(:solcast) { described_class.new(config: config) }

    context 'when successful' do
      it 'returns solcast data' do
        stdout, stderr = capture_output do
          VCR.use_cassette('solcast_success') do
            data = solcast.fetch_data

            expect(data).to be_a(Hash)
            data.each do |key, value|
              expect(key).to be_an(Integer)
              expect(value).to be_an(Integer)
            end
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/OK/)
      end
    end
  end
end
