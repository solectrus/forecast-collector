require 'adapter/pvnode_v2_adapter'

describe PvnodeV2Adapter do
  let(:pvnode) { described_class.new(config:) }
  let(:config) { Config.from_env(forecast_provider: 'pvnode', pvnode_paid:) }
  let(:pvnode_paid) { false }

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

  describe 'monthly rate limit' do
    it 'uses the v2 Free-tier budget by default' do
      expect(pvnode.send(:max_requests_per_month)).to eq(250)
    end

    context 'with paid (Light) tier' do
      let(:pvnode_paid) { true }

      it 'uses the 3000-request budget' do
        expect(pvnode.send(:max_requests_per_month)).to eq(3_000)
      end
    end

    context 'with nowcast (Plus) tier' do
      let(:config) { Config.from_env(forecast_provider: 'pvnode', pvnode_paid: true, pvnode_nowcast: true) }

      it 'uses the 3000-request budget' do
        expect(pvnode.send(:max_requests_per_month)).to eq(3_000)
      end
    end
  end

  describe 'fetch frequency (slots per day)' do
    it 'fetches only once a day on Free (data updates once daily)' do
      expect(pvnode.send(:slots_per_day)).to eq(1)
    end

    context 'with paid (Light) tier' do
      let(:pvnode_paid) { true }

      it 'fetches hourly' do
        expect(pvnode.send(:slots_per_day)).to eq(24)
      end
    end

    context 'with nowcast (Plus) tier' do
      let(:config) { Config.from_env(forecast_provider: 'pvnode', pvnode_paid: true, pvnode_nowcast: true) }

      it 'caps the slot scheduler at hourly (Nowcast handles the 10-min cadence)' do
        expect(pvnode.send(:slots_per_day)).to eq(24)
      end
    end
  end

  describe '#pull_interval_message' do
    context 'without nowcast' do
      it 'returns the auto schedule message' do
        expect(pvnode.pull_interval_message).to eq('on provider schedule (auto)')
      end
    end

    context 'with nowcast enabled' do
      let(:config) { Config.from_env(forecast_provider: 'pvnode', pvnode_paid: true, pvnode_nowcast: true) }

      it 'returns the nowcast message with the base 10 min interval' do
        expect(pvnode.pull_interval_message).to eq(
          'in Nowcast mode (every 10 min during daylight, slot-based at night)',
        )
      end
    end
  end

  describe 'self-imposed request limit (PVNODE_REQUEST_LIMIT)' do
    let(:config) do
      Config.from_env(forecast_provider: 'pvnode', pvnode_paid: true, pvnode_request_limit: 200)
    end

    it 'schedules within the configured limit instead of the tier limit' do
      expect(pvnode.send(:max_requests_per_month)).to eq(200)
    end

    it 'reports the limit at startup' do
      expect(pvnode.pull_interval_message).to eq(
        'on provider schedule (auto), limited to 200 requests per month',
      )
    end

    it 'fetches less often than the tier alone would allow' do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 6, 24, 12, 0, 0))

      # 200/31 = 6.45 slots per day → skip_factor = 5 → slots at 0, 5, 10, 15, 20
      # (without the limit, the Light tier would fetch hourly, i.e. at 12:47)
      expect(pvnode.next_fetch_time).to eq(Time.utc(2026, 6, 24, 15, 47, 0))
    end

    context 'with a limit above the tier limit' do
      let(:config) do
        Config.from_env(forecast_provider: 'pvnode', pvnode_paid: true, pvnode_request_limit: 99_999)
      end

      it 'sticks to the tier limit and warns about it' do
        expect(pvnode.send(:max_requests_per_month)).to eq(3_000)
        expect(pvnode.pull_interval_message).to eq(
          'on provider schedule (auto), WARNING: PVNODE_REQUEST_LIMIT=99999 ignored, ' \
          'your plan allows only 3000 requests per month',
        )
      end
    end
  end
end
