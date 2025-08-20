require 'influxdb-client'

class FluxWriter
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def push(data)
    filtered_data = filter_past_data(data)
    return if filtered_data.empty?

    points =
      filtered_data.map do |key, value|
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

  def ready?
    influx_client.ping.status == 'ok'
  end

  private

  def filter_past_data(data)
    return [] unless data

    current_time = Time.now.to_i
    data.select { |timestamp, _| timestamp > current_time }
  end

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
