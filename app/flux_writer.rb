require 'influxdb-client'

class FluxWriter
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  # @param lookback [Integer] seconds before now that are still written. Older
  #   timestamps are skipped, so a value that has passed stays as it was.
  def push(data, lookback: 0)
    filtered_data = filter_past_data(data, lookback)
    return if filtered_data.empty?

    points =
      filtered_data.map do |key, value|
        # Support both simple values (e.g., 100) and hash values (e.g., { watt: 100, watt_clearsky: 120 })
        fields =
          if value.is_a?(Hash)
            value
          else
            { watt: value }
          end

        InfluxDB2::Point.new(
          name: influx_measurement,
          time: key,
          fields:,
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

  def filter_past_data(data, lookback)
    return [] unless data

    oldest_time = Time.now.to_i - lookback
    data.select { |timestamp, _| timestamp > oldest_time }
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
