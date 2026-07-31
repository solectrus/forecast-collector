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

      it 'converts the site-local timestamps to the correct UTC epoch' do
        stdout, stderr = capture_output do
          VCR.use_cassette('pvnode_v2_success') do
            data = pvnode.fetch_data

            # First slot is 2026-06-24T00:00:00 in Europe/Berlin (UTC+2 in June),
            # i.e. 2026-06-23T22:00:00 UTC
            expect(data.keys.min).to eq(Time.utc(2026, 6, 23, 22, 0, 0).to_i)
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
    def parse(timestamp, timezone: 'Europe/Berlin', **fields)
      pvnode.parse_forecast_data(
        'timezone' => timezone,
        'values' => [{ 'timestamp' => timestamp, 'pv_power' => 100 }.merge(fields)],
      )
    end

    describe 'naive-local to UTC conversion' do
      it 'applies the winter (standard time) offset' do
        data = parse('2026-01-15T12:00:00') # CET, UTC+1
        expect(data.keys.first).to eq(Time.utc(2026, 1, 15, 11, 0, 0).to_i)
      end

      it 'applies the summer (DST) offset' do
        data = parse('2026-07-15T12:00:00') # CEST, UTC+2
        expect(data.keys.first).to eq(Time.utc(2026, 7, 15, 10, 0, 0).to_i)
      end

      it 'resolves ambiguous fall-back times to the first (still-DST) occurrence' do
        # On 2026-10-25, 02:30 occurs twice; the first is CEST (UTC+2)
        data = parse('2026-10-25T02:30:00')
        expect(data.keys.first).to eq(Time.utc(2026, 10, 25, 0, 30, 0).to_i)
      end

      it 'handles non-existent spring-forward times without raising' do
        # On 2026-03-29, 02:30 is skipped by the clock change
        data = parse('2026-03-29T02:30:00')
        expect(data.keys.first).to eq(Time.utc(2026, 3, 29, 1, 30, 0).to_i)
      end

      it 'honours the timezone from the response, not a fixed one' do
        data = parse('2026-01-15T12:00:00', timezone: 'America/New_York') # EST, UTC-5
        expect(data.keys.first).to eq(Time.utc(2026, 1, 15, 17, 0, 0).to_i)
      end
    end

    it 'omits fields that are absent in the response' do
      data = parse('2026-07-15T12:00:00') # only pv_power present
      expect(data.values.first).to eq(watt: 100)
    end

    it 'rounds power to whole watts and weather metrics to one decimal' do
      data = parse(
        '2026-07-15T12:00:00',
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

    it 'uses 1 forecast day for free accounts' do
      expect(query.assoc('forecast_days').last).to eq('1')
    end

    context 'with paid account' do
      let(:pvnode_paid) { true }

      it 'uses 7 forecast days' do
        expect(query.assoc('forecast_days').last).to eq('7')
      end
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
end
