Config =
  Struct.new(
    :forecast_provider,
    :forecast_configurations,
    :forecast_solar_apikey,
    :forecast_interval,
    :solcast_configurations,
    :solcast_apikey,
    :influx_schema,
    :influx_host,
    :influx_port,
    :influx_token,
    :influx_org,
    :influx_bucket,
    :influx_measurement,
    keyword_init: true,
  ) do
    def initialize(*options)
      super

      validate_url!(influx_url)
      validate_interval!(forecast_interval)
    end

    def influx_url
      "#{influx_schema}://#{influx_host}:#{influx_port}"
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

    def self.from_env(options = {})
      new(
        {}.merge(forecast_settings_from_env)
          .merge(solcast_settings_from_env)
          .merge(influx_credentials_from_env)
          .merge(options),
      )
    end

    def self.influx_credentials_from_env
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

    def self.solcast_settings_from_env
      defaults = single_solcast_settings_from_env
      {
        solcast_configurations: all_solcast_settings_from_env(defaults),
        solcast_apikey: ENV.fetch('SOLCAST_APIKEY', nil),
      }
    end

    def self.forecast_settings_from_env
      defaults = single_forecast_settings_from_env
      {
        forecast_provider: ENV.fetch('FORECAST_PROVIDER', 'forecast.solar'),
        forecast_configurations: all_forecast_settings_from_env(defaults),
        forecast_interval: ENV.fetch('FORECAST_INTERVAL').to_i,
        forecast_solar_apikey: ENV.fetch('FORECAST_SOLAR_APIKEY', nil),
      }
    end

    def self.single_forecast_settings_from_env
      {
        latitude: ENV.fetch('FORECAST_LATITUDE', ''),
        longitude: ENV.fetch('FORECAST_LONGITUDE', ''),
        declination: ENV.fetch('FORECAST_DECLINATION', ''),
        azimuth: ENV.fetch('FORECAST_AZIMUTH', ''),
        kwp: ENV.fetch('FORECAST_KWP', ''),
        damping_morning: ENV.fetch('FORECAST_DAMPING_MORNING', '0'),
        damping_evening: ENV.fetch('FORECAST_DAMPING_EVENING', '0'),
      }
    end

    def self.single_solcast_settings_from_env
      {
        solcast_site: ENV.fetch('SOLCAST_SITE', ''),
      }
    end

    def self.all_forecast_settings_from_env(defaults)
      config_count = ENV.fetch('FORECAST_CONFIGURATIONS', '1').to_i

      (0...config_count).map do |index|
        ForecastConfiguration.from_env(index, defaults)
      end
    end

    def self.all_solcast_settings_from_env(defaults)
      config_count = ENV.fetch('FORECAST_CONFIGURATIONS', '1').to_i

      (0...config_count).map do |index|
        SolcastConfiguration.from_env(index, defaults)
      end
    end
  end

ForecastConfiguration =
  Struct.new(
    :latitude,
    :longitude,
    :declination,
    :azimuth,
    :kwp,
    :damping_morning,
    :damping_evening,
  ) do
    def self.from_env(index, defaults)
      {
        latitude: ENV.fetch("FORECAST_#{index}_LATITUDE", defaults[:latitude]),
        longitude:
          ENV.fetch("FORECAST_#{index}_LONGITUDE", defaults[:longitude]),
        declination:
          ENV.fetch("FORECAST_#{index}_DECLINATION", defaults[:declination]),
        azimuth: ENV.fetch("FORECAST_#{index}_AZIMUTH", defaults[:azimuth]),
        kwp: ENV.fetch("FORECAST_#{index}_KWP", defaults[:kwp]),
        damping_morning:
          ENV.fetch(
            "FORECAST_#{index}_DAMPING_MORNING",
            defaults[:damping_morning],
          ),
        damping_evening:
          ENV.fetch(
            "FORECAST_#{index}_DAMPING_EVENING",
            defaults[:damping_evening],
          ),
      }
    end
  end

SolcastConfiguration =
  Struct.new(
    :site,
  ) do
    def self.from_env(index, defaults)
      {
        site: ENV.fetch("SOLCAST_#{index}_SITE", defaults[:solcast_site]),
      }
    end
  end
