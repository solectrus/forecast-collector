require 'influxdb-client'

class FluxWriter
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def push(data)
    return unless data

    points =
      data.map do |key, value|
        InfluxDB2::Point.new(
          name: influx_measurement,
          time: key,
          fields: {
            watt: value,
          },
        )
      end

    write_api.write(
      data: points,
      bucket: config.influx_bucket,
      org: config.influx_org,
    )
  end

  private

  def influx_measurement
    config.influx_measurement
  end

  def influx_client
    @influx_client ||=
      InfluxDB2::Client.new(
        config.influx_url,
        config.influx_token,
        use_ssl: config.influx_schema == 'https',
        precision: InfluxDB2::WritePrecision::SECOND,
      )
  end

  def write_api
    @write_api ||= influx_client.create_write_api
  end
end
