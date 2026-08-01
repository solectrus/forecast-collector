require_relative 'config/forecast_solar_configuration'
require_relative 'config/solcast_configuration'
require_relative 'config/pvnode_configuration'

class Config # rubocop:disable Metrics/ClassLength
  def initialize(options = {})
    options.each { |key, value| instance_variable_set("@#{key}", value) }

    validate_url!(influx_url)
    validate_positive_integer!(forecast_interval, 'Interval') unless forecast_provider == 'pvnode'
    validate_positive_integer!(pvnode_request_limit, 'Request limit') if pvnode_request_limit
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
              :pvnode_site_id,
              :pvnode_apikey,
              :pvnode_paid,
              :pvnode_nowcast,
              :pvnode_request_limit,
              :pvnode_clearsky_data,
              :solcast_configurations,
              :solcast_apikey

  def influx_url
    "#{influx_schema}://#{influx_host}:#{influx_port}"
  end

  def pvnode_site_id?
    !pvnode_site_id.to_s.strip.empty?
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
        require 'adapter/pvnode_v1_adapter'
        require 'adapter/pvnode_v2_adapter'

        # Use the v2 (site-based) API when a site ID is configured, otherwise
        # fall back to the v1 API. This lets existing installations keep working
        # after an update until they opt into v2 by setting PVNODE_SITE_ID.
        adapter_class = pvnode_site_id? ? PvnodeV2Adapter : PvnodeV1Adapter
        adapter_class.new(config: self)
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

  def validate_positive_integer!(value, name)
    return if value.is_a?(Integer) && value.positive?

    throw "#{name} is invalid: #{value}"
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
        extra_params: ENV.fetch('PVNODE_EXTRA_PARAMS', nil),
      }

      plan = ENV.fetch('PVNODE_PAID', 'false').downcase
      {
        pvnode_configurations: all_configurations_from_env('PVNODE', PvnodeConfiguration, defaults),
        pvnode_site_id: ENV.fetch('PVNODE_SITE_ID', nil),
        pvnode_apikey: ENV.fetch('PVNODE_APIKEY', nil),
        pvnode_paid: %w[true nowcast].include?(plan),
        pvnode_nowcast: plan == 'nowcast',
        # Self-imposed monthly request limit
        pvnode_request_limit: optional_integer_from_env('PVNODE_REQUEST_LIMIT'),
      }
    end

    # Reads an optional integer setting; unset or blank means not configured.
    def optional_integer_from_env(key)
      value = ENV.fetch(key, '').strip
      value.empty? ? nil : value.to_i
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
        forecast_interval: optional_integer_from_env('FORECAST_INTERVAL'),
        forecast_solar_apikey: ENV.fetch('FORECAST_SOLAR_APIKEY', nil),
      }
    end

    def all_configurations_from_env(prefix, klass, defaults)
      config_count = ENV.fetch('FORECAST_CONFIGURATIONS', '1').to_i
      (0...config_count).map { |index| klass.from_env(index, prefix, defaults) }
    end
  end
end
