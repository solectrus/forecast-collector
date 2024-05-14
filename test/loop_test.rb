require 'test_helper'
require 'loop'
require 'config'

class LoopTest < Minitest::Test
  def test_start_successful_with_forecast_solar
    config = Config.from_env(forecast_provider: 'forecast.solar')

    cassettes = [{ name: 'forecast_solar_success' }, { name: 'influxdb' }]

    out, err =
      capture_io do
        VCR.use_cassettes(cassettes) { Loop.start(config:, max_count: 2) }
      end

    assert_match(/Fetching forecast/, out)
    assert_match(/Pushing forecast to InfluxDB/, out)
    assert_empty(err)
  end

  def test_start_successful_with_solcast
    config = Config.from_env(forecast_provider: 'solcast')

    cassettes = [{ name: 'solcast_success' }, { name: 'influxdb' }]

    out, err =
      capture_io do
        VCR.use_cassettes(cassettes) { Loop.start(config:, max_count: 2) }
      end

    assert_match(/Fetching forecast/, out)
    assert_match(/Pushing forecast to InfluxDB/, out)
    assert_empty(err)
  end

  def test_start_fail
    config = Config.from_env

    cassettes = [{ name: 'forecast_solar_fail' }]

    out, err =
      capture_io do
        VCR.use_cassettes(cassettes) { Loop.start(config:, max_count: 1) }
      end

    assert_match(/Too Many Requests/, out)
    assert_empty(err)
  end
end
