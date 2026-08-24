require 'config'
require 'adapter/pvnode_v2_adapter'

describe PvnodeV2Adapter do
  let(:pvnode) { described_class.new(config:, site_id: config.pvnode_site_id) }
  let(:config) { Config.from_env(forecast_provider: 'pvnode') }
  let(:forecast_url) { %r{https://api\.pvnode\.com/v2/forecast/} }

  describe '#fetch_data' do
    context 'when successful' do
      it 'returns pvnode data' do
        stdout, stderr = capture_output do
          VCR.use_cassette('pvnode_v2_success') do
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
              expect(value).to have_key(:humidity)
              expect(value[:humidity]).to be_a(Numeric)
              expect(value).to have_key(:weather_code)
            end
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to include('OK')
      end

      it 'returns timestamps as UTC epochs on full quarter hours' do
        stdout, stderr = capture_output do
          VCR.use_cassette('pvnode_v2_success') do
            data = pvnode.fetch_data

            expect(data.keys).to all(be_a(Integer))
            expect(data.keys).to all(satisfy { |timestamp| (timestamp % 900).zero? })
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to include('OK')
      end
    end

    context 'when the site does not exist (invalid PVNODE_SITE_ID)' do
      let(:config) do
        Config.from_env(forecast_provider: 'pvnode', pvnode_site_id: 'site_doesnotexist0000000000')
      end

      it 'logs a clear error and returns nil without raising' do
        data = nil

        stdout, stderr = capture_output do
          VCR.use_cassette('pvnode_v2_invalid_site') do
            expect { data = pvnode.fetch_data }.not_to raise_error
          end
        end

        expect(data).to be_nil
        expect(stderr).to be_empty
        expect(stdout).to include('HTTP 404 Not Found')
      end
    end
  end

  describe 'request limit' do
    it 'reports the remaining quota after a fetch' do
      stdout, stderr = capture_output do
        VCR.use_cassette('pvnode_v2_success') { pvnode.fetch_data }
      end

      expect(pvnode.request_limit).to have_attributes(limit: 15_000, remaining: 12_739)
      expect(stdout).to include('pvnode quota:', 'requests left this month')
      expect(stderr).to be_empty
    end

    context 'when the quota is exhausted' do
      before do
        stub_request(:get, forecast_url).to_return(
          status: 429,
          headers: {
            'RequestLimit-Limit' => '250',
            'RequestLimit-Used' => '250',
            'RequestLimit-Remaining' => '0',
            'RequestLimit-Reset' => '2026-09-01T00:00:00Z',
          },
        )
      end

      it 'warns about the exhausted quota without raising' do
        data = nil

        stdout, stderr = capture_output do
          expect { data = pvnode.fetch_data }.not_to raise_error
        end

        expect(data).to be_nil
        expect(stderr).to be_empty
        expect(stdout).to include('HTTP 429')
        expect(stdout).to include('WARNING: pvnode quota: 0 of 250 requests left this month')
      end
    end

    context 'when few requests are left' do
      before do
        stub_request(:get, forecast_url).to_return(
          status: 200,
          body: '{"values":[]}',
          headers: {
            'RequestLimit-Limit' => '250',
            'RequestLimit-Remaining' => '20',
            'RequestLimit-Reset' => '2026-09-01T00:00:00Z',
          },
        )
      end

      it 'warns before the quota runs out' do
        stdout, = capture_output { pvnode.fetch_data }

        expect(stdout).to include('WARNING: pvnode quota: 20 of 250 requests left this month')
      end
    end

    context 'with a self-imposed limit above the limit of the plan' do
      let(:config) do
        Config.from_env(forecast_provider: 'pvnode', pvnode_request_limit: 99_999)
      end

      it 'warns once, not after every fetch' do
        stdout, = capture_output do
          VCR.use_cassette('pvnode_v2_success') do
            pvnode.fetch_data
            pvnode.fetch_data
          end
        end

        expect(stdout.scan('PVNODE_REQUEST_LIMIT=99999 has no effect').length).to eq(1)
      end
    end

    # A plan without a cap sends the literal string instead of a number.
    # See https://pvnode.com/docs/v2/integrations/build-your-own
    context 'with an unmetered quota' do
      let(:config) do
        Config.from_env(forecast_provider: 'pvnode', pvnode_request_limit: 200)
      end

      before do
        stub_request(:get, forecast_url).to_return(
          status: 200,
          body: '{"values":[]}',
          headers: {
            'RequestLimit-Limit' => 'unmetered',
            'RequestLimit-Used' => '4231',
            'RequestLimit-Remaining' => 'unmetered',
            'RequestLimit-Reset' => '2026-09-01T00:00:00Z',
          },
        )
      end

      it 'reports the quota without numbers' do
        stdout, = capture_output { pvnode.fetch_data }

        expect(stdout).to include('pvnode quota: unmetered')
      end

      it 'keeps the self-imposed limit, which has no plan limit to exceed' do
        stdout, = capture_output { pvnode.fetch_data }

        expect(stdout).not_to include('has no effect')
      end
    end
  end

  describe '#parse_forecast_data' do
    def parse(timestamp, **fields)
      pvnode.parse_forecast_data(
        'timezone' => 'UTC',
        'values' => [{ 'timestamp' => timestamp, 'pv_power' => 100 }.merge(fields)],
      )
    end

    it 'returns nothing when the response carries no values' do
      expect(pvnode.parse_forecast_data({})).to eq({})
    end

    it 'skips the fields the response leaves out' do
      response_data = { 'values' => [{ 'timestamp' => '2026-08-24T12:00:00Z', 'weather_code' => 3 }] }

      expect(pvnode.parse_forecast_data(response_data)).to eq(
        Time.utc(2026, 8, 24, 12).to_i => { weather_code: 3 },
      )
    end

    describe 'timestamp handling' do
      it 'converts a UTC timestamp to an epoch' do
        data = parse('2026-07-15T12:00:00Z')
        expect(data.keys.first).to eq(Time.utc(2026, 7, 15, 12, 0, 0).to_i)
      end

      it 'honours a numeric offset' do
        data = parse('2026-07-15T12:00:00+02:00')
        expect(data.keys.first).to eq(Time.utc(2026, 7, 15, 10, 0, 0).to_i)
      end

      it 'rejects a timestamp without a timezone' do
        # Such a timestamp would be read as machine-local time and silently
        # store a wrong point in time.
        expect { parse('2026-07-15T12:00:00') }.to raise_error(/Timestamp without timezone/)
      end
    end

    it 'omits fields that are absent in the response' do
      data = parse('2026-07-15T12:00:00Z') # only pv_power present
      expect(data.values.first).to eq(watt: 100)
    end

    it 'rounds power to whole watts and weather metrics to one decimal' do
      data = parse(
        '2026-07-15T12:00:00Z',
        'pv_power' => 1234.6, 'temp' => 21.37, 'relative_humidity' => 38.96,
      )
      expect(data.values.first).to eq(watt: 1235, temp: 21.4, humidity: 39.0)
    end
  end

  describe '#formatted_url' do
    subject(:uri) { URI.parse(pvnode.formatted_url(0)) }

    let(:query) { URI.decode_www_form(uri.query) }

    it 'targets the v2 forecast endpoint for the configured site' do
      expect(uri.to_s).to start_with('https://api.pvnode.com/v2/forecast/')
      expect(uri.path).to eq("/v2/forecast/#{config.pvnode_site_id}")
    end

    it 'requests the default, clearsky and weather field groups' do
      includes = query.filter_map { |key, value| value if key == 'include' }
      expect(includes).to eq(%w[default clearsky weather])
    end

    it 'requests no past days' do
      expect(query.assoc('past_days').last).to eq('0')
    end

    it 'requests UTC timestamps' do
      expect(query.assoc('timezone').last).to eq('utc')
    end

    it 'sends no forecast horizon, so the plan of the user decides' do
      expect(query.assoc('forecast_days')).to be_nil
    end
  end

  describe '#required_requests_count' do
    it 'always needs a single request (all strings live on the site)' do
      expect(pvnode.required_requests_count).to eq(1)
    end
  end

  describe 'scheduling' do
    it 'follows the recommendation of the API' do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 8, 24, 14, 47, 41))

      capture_output { VCR.use_cassette('pvnode_v2_success') { pvnode.fetch_data } }

      # The recorded response recommends 2026-08-24T15:00:00Z, plus the offset
      expect(pvnode.next_fetch_time).to eq(Time.utc(2026, 8, 24, 15, 0, 30))
    end
  end

  describe '#pull_interval_message' do
    it 'announces the schedule of the API' do
      expect(pvnode.pull_interval_message).to eq('when the API recommends it (next_poll_at)')
    end
  end

  describe 'self-imposed request limit (PVNODE_REQUEST_LIMIT)' do
    let(:config) do
      Config.from_env(forecast_provider: 'pvnode', pvnode_request_limit: 200)
    end

    it 'reports the limit at startup' do
      expect(pvnode.pull_interval_message).to eq(
        'when the API recommends it (next_poll_at), limited to 200 requests per month',
      )
    end

    it 'fetches less often than the API recommends' do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 8, 24, 14, 47, 41))

      capture_output { VCR.use_cassette('pvnode_v2_success') { pvnode.fetch_data } }

      # 200 requests spread over 31 days is one request every 3 hours and
      # 43 minutes, which is later than the recommended 15:00:00Z
      expect(pvnode.next_fetch_time).to eq(Time.utc(2026, 8, 24, 18, 30, 53))
    end
  end
end
