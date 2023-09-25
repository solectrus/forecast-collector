require 'test_helper'
require 'loop'
require 'config'

class LoopTest < Minitest::Test
  def test_start
    config = Config.from_env

    cassettes = [{ name: 'forecast_solar_success' }, { name: 'influxdb' }]

    out, err =
      capture_io do
        VCR.use_cassettes(cassettes) { Loop.start(config:, max_count: 2) }
      end

    assert_match(/Getting data from/, out)
    assert_match(/Pushing forecast to InfluxDB/, out)
    assert_empty(err)
  end
end
