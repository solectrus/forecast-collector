require 'test_helper'
require 'solcast'
require 'config'

class SolcastTest < Minitest::Test
  SOLCAST_OPTIONS = {
    forecast_interval: 900,
    influx_host: 'influx.example.com',
    influx_schema: 'https',
    influx_port: '443',
    influx_token: 'this.is.just.an.example',
    influx_org: 'my-org',
    influx_bucket: 'my-bucket',
    influx_measurement: 'my-measurement',
    forecast_provider: 'solcast',
    solcast_apikey: 'APIKEY',
    solcast_configurations: [
        site: '1111-2222-3333-4444',
    ],
  }.freeze

  def test_fetch_data_success
    solcast = Solcast.new(config: Config.new(SOLCAST_OPTIONS))

    out, err =
      capture_io do
        VCR.use_cassette('solcast_success') do
          data = solcast.fetch_data

          assert_kind_of Hash, data
          data.each do |key, value|
            assert_kind_of Integer, key
            assert_kind_of Integer, value
          end
        end
      end

    assert_match(/OK/, out)
    assert_empty(err)
  end
end
