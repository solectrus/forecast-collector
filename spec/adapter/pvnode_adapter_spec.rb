require 'adapter/pvnode_adapter'

describe PvnodeAdapter do
  let(:config) { Config.from_env(forecast_provider: 'pvnode') }
  let(:pvnode) { described_class.new(config:) }

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
              expect(value).to have_key(:temp)
              expect(value[:temp]).to be_a(Numeric)
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

  describe '#formatted_url' do
    subject(:params) do
      url = pvnode.formatted_url(0)
      URI.decode_www_form(URI.parse(url).query).to_h
    end

    it 'includes extra parameters when set in config' do
      expect(params['forecast_days']).to eq('3')
      expect(params['clearsky_data']).to eq('true')
      expect(params['diffuse_radiation_model']).to eq('perez')
      expect(params['snow_slide_coefficient']).to eq('0.5')
    end

    it 'includes required parameters with correct values' do
      expect(params['latitude']).to eq('50.92264')
      expect(params['longitude']).to eq('6.407')
      expect(params['slope']).to eq('30.0')
      expect(params['orientation']).to eq('200.0')
      expect(params['pv_power_kw']).to eq('9.24')
      expect(params['required_data']).to eq('pv_watts,temp,weather_code')
      expect(params['past_days']).to eq('0')
    end

    it 'converts declination to slope' do
      expect(params['slope']).to eq('30.0')
    end

    it 'converts azimuth to orientation by adding 180 degrees' do
      expect(params['orientation']).to eq('200.0')
    end

    context 'when extra parameters are nil' do
      let(:config) do
        Config.new(
          forecast_interval: 900,
          influx_host: 'localhost',
          influx_schema: 'http',
          influx_port: '8086',
          influx_token: 'test-token',
          influx_org: 'test-org',
          influx_bucket: 'test-bucket',
          influx_measurement: 'test-measurement',
          pvnode_apikey: 'test-key',
          pvnode_configurations: [{
            latitude: '50.0',
            longitude: '6.0',
            declination: '30',
            azimuth: '20',
            kwp: '9.24',
            extra_params: nil,
          }],
          pvnode_forecast_days: nil,
          pvnode_clearsky_data: nil,
        )
      end

      it 'omits nil parameters from URL' do
        expect(params).not_to have_key('forecast_days')
        expect(params).not_to have_key('clearsky_data')
      end
    end
  end
end
