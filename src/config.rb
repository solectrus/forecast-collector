Config =
  Struct.new(
    :forecast_interval,
    :forecast_latitude,
    :forecast_longitude,
    :forecast_declination,
    :forecast_azimuth,
    :forecast_kwp,
    :forecast_damping_morning,
    :forecast_damping_evening,
    :forecast_apikey,
    :influx_schema,
    :influx_host,
    :influx_port,
    :influx_token,
    :influx_org,
    :influx_bucket,
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
        {
          forecast_latitude: ENV.fetch('FORECAST_LATITUDE'),
          forecast_longitude: ENV.fetch('FORECAST_LONGITUDE'),
          forecast_declination: ENV.fetch('FORECAST_DECLINATION'),
          forecast_azimuth: ENV.fetch('FORECAST_AZIMUTH'),
          forecast_kwp: ENV.fetch('FORECAST_KWP'),
          forecast_damping_morning: ENV.fetch('FORECAST_DAMPING_MORNING', '0'),
          forecast_damping_evening: ENV.fetch('FORECAST_DAMPING_EVENING', '0'),
          forecast_interval: ENV.fetch('FORECAST_INTERVAL').to_i,
          forecast_apikey: ENV.fetch('FORECAST_APIKEY', nil),
          influx_host: ENV.fetch('INFLUX_HOST'),
          influx_schema: ENV.fetch('INFLUX_SCHEMA', 'http'),
          influx_port: ENV.fetch('INFLUX_PORT', '8086'),
          influx_token: ENV.fetch('INFLUX_TOKEN'),
          influx_org: ENV.fetch('INFLUX_ORG'),
          influx_bucket: ENV.fetch('INFLUX_BUCKET'),
        }.merge(options),
      )
    end
  end
