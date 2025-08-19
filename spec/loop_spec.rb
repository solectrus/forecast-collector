require_relative '../app/loop'

describe Loop do
  describe '.start' do
    context 'with forecast.solar provider' do
      let(:config) { Config.from_env(forecast_provider: 'forecast.solar') }

      it 'successfully fetches and pushes forecast data' do
        stdout, stderr = capture_output do
          VCR.use_cassette('forecast_solar_success') do
            VCR.use_cassette('influxdb') do
              described_class.start(config: config, max_count: 2, max_wait: 1)
            end
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/Fetching forecast/)
        expect(stdout).to match(/Pushing forecast to InfluxDB/)
      end
    end

    context 'with solcast provider' do
      let(:config) { Config.from_env(forecast_provider: 'solcast') }

      it 'successfully fetches and pushes forecast data' do
        stdout, stderr = capture_output do
          VCR.use_cassette('solcast_success') do
            VCR.use_cassette('influxdb') do
              described_class.start(config: config, max_count: 2, max_wait: 1)
            end
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/Fetching forecast/)
        expect(stdout).to match(/Pushing forecast to InfluxDB/)
      end
    end

    context 'when forecast fails' do
      let(:config) { Config.from_env }

      it 'handles forecast failures gracefully' do
        stdout, stderr = capture_output do
          VCR.use_cassette('forecast_solar_fail') do
            described_class.start(config: config, max_count: 1, max_wait: 1)
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/Too Many Requests/)
      end
    end

    context 'when InfluxDB is not ready' do
      let(:config) { Config.from_env }

      it 'handles InfluxDB connection failures' do
        stdout, stderr = capture_output do
          described_class.start(config: config, max_wait: 1, max_count: 1)
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/InfluxDB not ready/)
      end
    end
  end
end
