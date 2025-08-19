require 'adapter/pvnode_adapter'

describe PvnodeAdapter do
  let(:config) { Config.from_env(forecast_provider: 'pvnode') }
  let(:pvnode) { described_class.new(config: config) }

  describe '#fetch_data' do
    context 'when successful' do
      it 'returns pvnode data' do
        stdout, stderr = capture_output do
          VCR.use_cassette('pvnode_success') do
            data = pvnode.fetch_data

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
