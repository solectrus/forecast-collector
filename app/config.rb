class Config # rubocop:disable Metrics/ClassLength
  def initialize(options = {})
    options.each { |key, value| instance_variable_set("@#{key}", value) }

    validate_url!(influx_url)
    validate_interval!(forecast_interval)
  end

  attr_reader :influx_schema,
              :influx_host,
              :influx_port,
              :influx_token,
              :influx_org,
              :influx_bucket,
              :influx_measurement,
              :forecast_provider,
              :forecast_interval,
              :forecast_solar_configurations,
              :forecast_solar_apikey,
              :pvnode_configurations,
              :pvnode_apikey,
              :solcast_configurations,
              :solcast_apikey

  def influx_url
    "#{influx_schema}://#{influx_host}:#{influx_port}"
  end

  def adapter
    @adapter ||=
      case forecast_provider
      when 'forecast.solar'
        require 'adapter/forecast_solar_adapter'
        ForecastSolarAdapter.new(config: self)
      when 'solcast'
        require 'adapter/solcast_adapter'
        SolcastAdapter.new(config: self)
      when 'pvnode'
        require 'adapter/pvnode_adapter'
        PvnodeAdapter.new(config: self)
      else
        raise ArgumentError, "Unknown provider: #{forecast_provider}"
      end
  end

  def self.from_env(options = {})
    new(
      influx_credentials_from_env
        .merge(forecast_solar_settings_from_env)
        .merge(solcast_settings_from_env)
        .merge(pvnode_settings_from_env)
        .merge(options),
    )
  end

  private

  def validate_interval!(interval)
    return if interval.is_a?(Integer) && interval.positive?

    throw "Interval is invalid: #{interval}"
  end

  def validate_url!(url)
    uri = URI.parse(url)
    return if uri.is_a?(URI::HTTP) && !uri.host.nil?

    throw "URL is invalid: #{url}"
  end

  class << self
    private

    def influx_credentials_from_env
      {
        influx_host: ENV.fetch('INFLUX_HOST'),
        influx_schema: ENV.fetch('INFLUX_SCHEMA', 'http'),
        influx_port: ENV.fetch('INFLUX_PORT', '8086'),
        influx_token: ENV.fetch('INFLUX_TOKEN'),
        influx_org: ENV.fetch('INFLUX_ORG'),
        influx_bucket: ENV.fetch('INFLUX_BUCKET'),
        influx_measurement: ENV.fetch('INFLUX_MEASUREMENT', 'Forecast'),
      }
    end

    def solcast_settings_from_env
      defaults = { solcast_site: ENV.fetch('SOLCAST_SITE', '') }
      {
        solcast_configurations: all_configurations_from_env('SOLCAST', SolcastConfiguration, defaults),
        solcast_apikey: ENV.fetch('SOLCAST_APIKEY', nil),
      }
    end

    def pvnode_settings_from_env
      defaults = {
        latitude: ENV.fetch('FORECAST_LATITUDE', ''),
        longitude: ENV.fetch('FORECAST_LONGITUDE', ''),
        declination: ENV.fetch('FORECAST_DECLINATION', ''),
        azimuth: ENV.fetch('FORECAST_AZIMUTH', ''),
        kwp: ENV.fetch('FORECAST_KWP', ''),
      }
      {
        pvnode_configurations: all_configurations_from_env('FORECAST', PvnodeConfiguration, defaults),
        pvnode_apikey: ENV.fetch('PVNODE_APIKEY', nil),
      }
    end

    def forecast_solar_settings_from_env
      defaults = {
        latitude: ENV.fetch('FORECAST_LATITUDE', ''),
        longitude: ENV.fetch('FORECAST_LONGITUDE', ''),
        declination: ENV.fetch('FORECAST_DECLINATION', ''),
        azimuth: ENV.fetch('FORECAST_AZIMUTH', ''),
        kwp: ENV.fetch('FORECAST_KWP', ''),
        damping_morning: ENV.fetch('FORECAST_DAMPING_MORNING', '0'),
        damping_evening: ENV.fetch('FORECAST_DAMPING_EVENING', '0'),
        inverter: ENV.fetch('FORECAST_INVERTER', nil),
        horizon: ENV.fetch('FORECAST_HORIZON', nil),
      }
      {
        forecast_provider: ENV.fetch('FORECAST_PROVIDER', 'forecast.solar'),
        forecast_solar_configurations: all_configurations_from_env('FORECAST', ForecastSolarConfiguration, defaults),
        forecast_interval: ENV.fetch('FORECAST_INTERVAL').to_i,
        forecast_solar_apikey: ENV.fetch('FORECAST_SOLAR_APIKEY', nil),
      }
    end

    def all_configurations_from_env(prefix, klass, defaults)
      config_count = ENV.fetch('FORECAST_CONFIGURATIONS', '1').to_i
      (0...config_count).map { |index| klass.from_env(index, prefix, defaults) }
    end
  end
end

class ForecastSolarConfiguration
  attr_reader :latitude, :longitude, :declination, :azimuth, :kwp, :damping_morning, :damping_evening, :inverter,
              :horizon

  def initialize(options = {})
    options.each { |key, value| instance_variable_set("@#{key}", value) }
  end

  def [](key)
    public_send(key)
  end

  def self.from_env(index, prefix, defaults)
    {
      latitude: ENV.fetch("#{prefix}_#{index}_LATITUDE", defaults[:latitude]),
      longitude: ENV.fetch("#{prefix}_#{index}_LONGITUDE", defaults[:longitude]),
      declination: ENV.fetch("#{prefix}_#{index}_DECLINATION", defaults[:declination]),
      azimuth: ENV.fetch("#{prefix}_#{index}_AZIMUTH", defaults[:azimuth]),
      kwp: ENV.fetch("#{prefix}_#{index}_KWP", defaults[:kwp]),
      damping_morning: ENV.fetch("#{prefix}_#{index}_DAMPING_MORNING", defaults[:damping_morning]),
      damping_evening: ENV.fetch("#{prefix}_#{index}_DAMPING_EVENING", defaults[:damping_evening]),
      inverter: ENV.fetch("#{prefix}_#{index}_INVERTER", defaults[:inverter]),
      horizon: ENV.fetch("#{prefix}_#{index}_HORIZON", defaults[:horizon]),
    }
  end
end

class SolcastConfiguration
  attr_reader :site

  def initialize(options = {})
    options.each { |key, value| instance_variable_set("@#{key}", value) }
  end

  def [](key)
    public_send(key)
  end

  def self.from_env(index, prefix, defaults)
    { site: ENV.fetch("#{prefix}_#{index}_SITE", defaults[:solcast_site]) }
  end
end

class PvnodeConfiguration
  attr_reader :latitude, :longitude, :declination, :azimuth, :kwp

  def initialize(options = {})
    options.each { |key, value| instance_variable_set("@#{key}", value) }
  end

  def [](key)
    public_send(key)
  end

  def self.from_env(index, prefix, defaults)
    {
      latitude: ENV.fetch("#{prefix}_#{index}_LATITUDE", defaults[:latitude]),
      longitude: ENV.fetch("#{prefix}_#{index}_LONGITUDE", defaults[:longitude]),
      declination: ENV.fetch("#{prefix}_#{index}_DECLINATION", defaults[:declination]),
      azimuth: ENV.fetch("#{prefix}_#{index}_AZIMUTH", defaults[:azimuth]),
      kwp: ENV.fetch("#{prefix}_#{index}_KWP", defaults[:kwp]),
    }
  end
end
