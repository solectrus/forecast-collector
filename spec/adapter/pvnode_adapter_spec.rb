require 'adapter/pvnode_adapter'

describe PvnodeAdapter do
  let(:pvnode) { described_class.new(config:) }

  let(:config) { Config.from_env(forecast_provider: 'pvnode', pvnode_paid:) }
  let(:pvnode_paid) { true }

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
      expect(params['forecast_days']).to eq('7')
      expect(params['clearsky_data']).to eq('true')
      expect(params['diffuse_radiation_model']).to eq('perez')
      expect(params['snow_slide_coefficient']).to eq('0.5')
    end

    it 'includes required parameters with correct values' do
      expect(params['latitude']).to eq('50.92264')
      expect(params['longitude']).to eq('6.407')
      expect(params['slope']).to eq('30')
      expect(params['orientation']).to eq('20')
      expect(params['pv_power_kw']).to eq('9.24')
      expect(params['required_data']).to eq('pv_watts,temp,weather_code')
      expect(params['past_days']).to eq('0')
    end

    context 'with multiple planes with same extra_params' do
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
          pvnode_configurations: [
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '30',
              azimuth: '20',
              kwp: '5.0',
              extra_params: 'diffuse_radiation_model=perez',
            },
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '45',
              azimuth: '-20',
              kwp: '4.24',
              extra_params: 'diffuse_radiation_model=perez',
            },
          ],
        )
      end

      it 'combines two planes with identical extra_params into one request' do
        # Both planes have same extra_params, so they can be batched
        expect(pvnode.adapter_requests_count).to eq(1)

        url = pvnode.formatted_url(0)
        params = URI.decode_www_form(URI.parse(url).query).to_h

        # First plane parameters
        expect(params['latitude']).to eq('50.0')
        expect(params['longitude']).to eq('6.0')
        expect(params['slope']).to eq('30')
        expect(params['orientation']).to eq('20')
        expect(params['pv_power_kw']).to eq('5.0')

        # Second plane parameters
        expect(params['second_array_slope']).to eq('45')
        expect(params['second_array_orientation']).to eq('-20')
        expect(params['second_array_power_kw']).to eq('4.24')

        # Extra params (same for both planes)
        expect(params['diffuse_radiation_model']).to eq('perez')
      end
    end

    context 'with multiple planes with different extra_params' do
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
          pvnode_configurations: [
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '30',
              azimuth: '20',
              kwp: '5.0',
              extra_params: 'snow_slide_coefficient=0.5',
            },
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '45',
              azimuth: '-20',
              kwp: '4.24',
              extra_params: 'snow_slide_coefficient=0.3',
            },
          ],
        )
      end

      it 'creates separate requests for planes with different extra_params' do
        # Different extra_params means we need 2 separate requests
        expect(pvnode.adapter_requests_count).to eq(2)

        # First request with first plane
        url0 = pvnode.formatted_url(0)
        params0 = URI.decode_www_form(URI.parse(url0).query).to_h
        expect(params0['slope']).to eq('30')
        expect(params0['snow_slide_coefficient']).to eq('0.5')
        expect(params0).not_to have_key('second_array_slope')

        # Second request with second plane
        url1 = pvnode.formatted_url(1)
        params1 = URI.decode_www_form(URI.parse(url1).query).to_h
        expect(params1['slope']).to eq('45')
        expect(params1['snow_slide_coefficient']).to eq('0.3')
        expect(params1).not_to have_key('second_array_slope')
      end
    end

    context 'with complex mix of extra_params' do
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
          pvnode_configurations: [
            # Group 1: nil extra_params (2 planes -> 1 request)
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '30',
              azimuth: '0',
              kwp: '5.0',
              extra_params: nil,
            },
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '45',
              azimuth: '90',
              kwp: '4.0',
              extra_params: nil,
            },
            # Group 2: 'diffuse_radiation_model=perez' (3 planes -> 2 requests)
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '35',
              azimuth: '180',
              kwp: '3.0',
              extra_params: 'diffuse_radiation_model=perez',
            },
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '40',
              azimuth: '270',
              kwp: '2.5',
              extra_params: 'diffuse_radiation_model=perez',
            },
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '50',
              azimuth: '-90',
              kwp: '2.0',
              extra_params: 'diffuse_radiation_model=perez',
            },
            # Group 3: 'snow_slide_coefficient=0.8' (1 plane -> 1 request)
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '60',
              azimuth: '-180',
              kwp: '1.5',
              extra_params: 'snow_slide_coefficient=0.8',
            },
          ],
        )
      end

      it 'groups planes correctly and creates optimal number of requests' do
        # 6 planes in 3 groups:
        # - Group nil: 2 planes -> 1 request
        # - Group perez: 3 planes -> 2 requests
        # - Group snow: 1 plane -> 1 request
        # Total: 4 requests
        expect(pvnode.adapter_requests_count).to eq(4)
      end

      it 'batches planes with nil extra_params together' do
        # Find the request with nil extra_params
        requests = (0...pvnode.adapter_requests_count).map do |i|
          url = pvnode.formatted_url(i)
          URI.decode_www_form(URI.parse(url).query).to_h
        end

        # One request should have azimuth 0 and 90 (the two nil planes)
        nil_request = requests.find { |r| r['orientation'] == '0' }
        expect(nil_request).not_to be_nil
        expect(nil_request['second_array_orientation']).to eq('90')
        expect(nil_request).not_to have_key('diffuse_radiation_model')
        expect(nil_request).not_to have_key('snow_slide_coefficient')
      end

      it 'batches planes with same extra_params together' do
        requests = (0...pvnode.adapter_requests_count).map do |i|
          url = pvnode.formatted_url(i)
          URI.decode_www_form(URI.parse(url).query).to_h
        end

        # Should have 2 requests with diffuse_radiation_model=perez
        perez_requests = requests.select { |r| r['diffuse_radiation_model'] == 'perez' }
        expect(perez_requests.length).to eq(2)

        # First perez request should have 2 planes (orientations 180 and 270)
        first_perez = perez_requests.find { |r| r['orientation'] == '180' }
        expect(first_perez).not_to be_nil
        expect(first_perez['second_array_orientation']).to eq('270')

        # Second perez request should have 1 plane (orientation -90)
        second_perez = perez_requests.find { |r| r['orientation'] == '-90' }
        expect(second_perez).not_to be_nil
        expect(second_perez).not_to have_key('second_array_orientation')
      end

      it 'keeps planes with unique extra_params separate' do
        requests = (0...pvnode.adapter_requests_count).map do |i|
          url = pvnode.formatted_url(i)
          URI.decode_www_form(URI.parse(url).query).to_h
        end

        # Should have 1 request with snow_slide_coefficient=0.8
        snow_requests = requests.select { |r| r['snow_slide_coefficient'] == '0.8' }
        expect(snow_requests.length).to eq(1)
        expect(snow_requests.first['orientation']).to eq('-180')
        expect(snow_requests.first).not_to have_key('second_array_orientation')
      end
    end

    context 'with odd number of planes' do
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
          pvnode_configurations: [
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '30',
              azimuth: '20',
              kwp: '5.0',
              extra_params: nil,
            },
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '45',
              azimuth: '-20',
              kwp: '4.24',
              extra_params: nil,
            },
            {
              latitude: '50.0',
              longitude: '6.0',
              declination: '60',
              azimuth: '90',
              kwp: '3.0',
              extra_params: nil,
            },
          ],
        )
      end

      it 'handles third plane in separate request' do
        # First request (index 0) should include planes 0 and 1
        url0 = pvnode.formatted_url(0)
        params0 = URI.decode_www_form(URI.parse(url0).query).to_h
        expect(params0['slope']).to eq('30')
        expect(params0['second_array_slope']).to eq('45')

        # Second request (index 1) should include only plane 2
        url1 = pvnode.formatted_url(1)
        params1 = URI.decode_www_form(URI.parse(url1).query).to_h
        expect(params1['slope']).to eq('60')
        expect(params1['orientation']).to eq('90')
        expect(params1['pv_power_kw']).to eq('3.0')
        expect(params1).not_to have_key('second_array_slope')
      end
    end
  end

  describe '#adapter_requests_count' do
    it 'returns half the number of planes (rounded up)' do
      config = Config.new(
        forecast_interval: 900,
        influx_host: 'localhost',
        influx_schema: 'http',
        influx_port: '8086',
        influx_token: 'test-token',
        influx_org: 'test-org',
        influx_bucket: 'test-bucket',
        influx_measurement: 'test-measurement',
        pvnode_apikey: 'test-key',
        pvnode_configurations: [
          { latitude: '50.0', longitude: '6.0', declination: '30', azimuth: '20', kwp: '5.0', extra_params: nil },
          { latitude: '50.0', longitude: '6.0', declination: '45', azimuth: '-20', kwp: '4.24', extra_params: nil },
          { latitude: '50.0', longitude: '6.0', declination: '60', azimuth: '90', kwp: '3.0', extra_params: nil },
        ],
      )
      adapter = described_class.new(config:)

      # 3 planes should result in 2 requests (3 / 2.0).ceil = 2
      expect(adapter.adapter_requests_count).to eq(2)
    end
  end
end
