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

              expect(value).to be_a(Hash)
              expect(value).to have_key(:watt)
              expect(value[:watt]).to be_an(Integer)
              expect(value[:watt_clearsky]).to be_an(Integer)
            end
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/OK/)
      end
    end
  end

  describe '#next_fetch_time' do
    subject { pvnode.next_fetch_time }

    before { allow(Time).to receive(:now).and_return(now) }

    context 'when next scheduled time is today at :05' do
      let(:now) { Time.utc(2025, 9, 30, 3, 0, 0) }

      it { is_expected.to eq(Time.utc(2025, 9, 30, 4, 5, 0)) }
    end

    context 'when next scheduled time is today at :35' do
      let(:now) { Time.utc(2025, 9, 30, 4, 15, 0) }

      it { is_expected.to eq(Time.utc(2025, 9, 30, 4, 35, 0)) }
    end

    context 'when all times passed today' do
      let(:now) { Time.utc(2025, 9, 30, 23, 0, 0) }

      it { is_expected.to eq(Time.utc(2025, 10, 1, 1, 5, 0)) }
    end

    context 'when crossing month boundary' do
      let(:now) { Time.utc(2025, 1, 31, 23, 0, 0) }

      it { is_expected.to eq(Time.utc(2025, 2, 1, 1, 5, 0)) }
    end

    context 'when crossing year boundary' do
      let(:now) { Time.utc(2025, 12, 31, 23, 0, 0) }

      it { is_expected.to eq(Time.utc(2026, 1, 1, 1, 5, 0)) }
    end
  end
end
