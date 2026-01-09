require 'loop'

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

      let(:flux_writer) do
        instance_double(FluxWriter, ready?: false).tap do |flux_writer|
          allow(FluxWriter).to receive(:new).with(config:).and_return(flux_writer)
        end
      end

      it 'fails with exit code 1' do
        exit_status = nil
        stdout, stderr = capture_output do
          described_class.start(config: config, max_wait: 1, max_count: 1)
        rescue SystemExit => e
          exit_status = e.status
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/InfluxDB not ready/)
        expect(exit_status).to eq(1)
      end
    end
  end
end
