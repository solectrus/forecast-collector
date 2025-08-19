require 'config'

describe Config do
  let(:valid_options) do
    {
      forecast_interval: 900,
      influx_host: 'influx.example.com',
      influx_schema: 'https',
      influx_port: '443',
      influx_token: 'this.is.just.an.example',
      influx_org: 'my-org',
      influx_bucket: 'my-bucket',
      influx_measurement: 'my-measurement',
    }.freeze
  end

  describe '#initialize' do
    context 'with valid options' do
      it 'creates a config instance' do
        expect { described_class.new(valid_options) }.not_to raise_error
      end
    end

    context 'with invalid options' do
      it 'raises an exception for empty options' do
        expect { described_class.new({}) }.to raise_error(Exception)
      end

      it 'raises an exception for invalid forecast interval' do
        invalid_options = valid_options.merge(forecast_interval: 0)
        expect { described_class.new(invalid_options) }.to raise_error(Exception, /Interval is invalid/)
      end

      it 'raises an exception for invalid influx schema' do
        invalid_options = valid_options.merge(influx_schema: 'foo')
        expect { described_class.new(invalid_options) }.to raise_error(Exception, /URL is invalid/)
      end
    end
  end

  describe 'forecast methods' do
    let(:config) { described_class.new(valid_options) }

    it 'returns the forecast interval' do
      expect(config.forecast_interval).to eq(900)
    end
  end

  describe 'influx methods' do
    let(:config) { described_class.new(valid_options) }

    it 'returns the influx host' do
      expect(config.influx_host).to eq('influx.example.com')
    end

    it 'returns the influx schema' do
      expect(config.influx_schema).to eq('https')
    end

    it 'returns the influx port' do
      expect(config.influx_port).to eq('443')
    end

    it 'returns the influx token' do
      expect(config.influx_token).to eq('this.is.just.an.example')
    end

    it 'returns the influx org' do
      expect(config.influx_org).to eq('my-org')
    end

    it 'returns the influx bucket' do
      expect(config.influx_bucket).to eq('my-bucket')
    end

    it 'returns the influx measurement' do
      expect(config.influx_measurement).to eq('my-measurement')
    end
  end

  describe '.from_env' do
    let(:config) { described_class.from_env }

    it 'creates config from environment variables' do
      expect(config.influx_host).to eq('localhost')
      expect(config.influx_schema).to eq('http')
      expect(config.influx_port).to eq('8086')
      expect(config.influx_token).to eq('my-token')
      expect(config.influx_org).to eq('my-org')
      expect(config.influx_bucket).to eq('my-bucket')
      expect(config.influx_measurement).to eq('my-forecast')

      expect(config.forecast_solar_configurations.length).to eq(1)
      expect(config.forecast_solar_configurations).to eq([
        {
          latitude: '50.9215',
          longitude: '6.3627',
          declination: '30',
          azimuth: '20',
          kwp: '9.24',
          damping_morning: '0',
          damping_evening: '0',
          inverter: '8.5',
          horizon: '0,30,60,30',
        },
      ])
    end
  end

  describe 'solcast configurations' do
    context 'with single site' do
      around do |example|
        ClimateControl.modify(
          SOLCAST_SITE: '111',
          SOLCAST_0_SITE: nil,
          SOLCAST_1_SITE: nil,
        ) do
          example.run
        end
      end

      it 'returns single solcast configuration' do
        config = described_class.from_env
        expect(config.solcast_configurations.length).to eq(1)
        expect(config.solcast_configurations.first).to eq({ site: '111' })
      end
    end

    context 'with multiple sites' do
      around do |example|
        ClimateControl.modify(
          SOLCAST_SITE: nil,
          FORECAST_CONFIGURATIONS: '2',
          SOLCAST_0_SITE: '111',
          SOLCAST_1_SITE: '222',
        ) do
          example.run
        end
      end

      it 'returns multiple solcast configurations' do
        config = described_class.from_env
        expect(config.solcast_configurations.length).to eq(2)
        expect(config.solcast_configurations[0]).to eq({ site: '111' })
        expect(config.solcast_configurations[1]).to eq({ site: '222' })
      end
    end
  end
end
