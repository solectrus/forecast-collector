require 'test_helper'
require 'loop'
require 'config'

class LoopTest < Minitest::Test
  def test_start_successful_with_forecast_solar
    config = Config.from_env(forecast_provider: 'forecast.solar')

    out, err =
      capture_io do
        VCR.use_cassette('forecast_solar_success') do
          VCR.use_cassette('influxdb') do
            Loop.start(config:, max_count: 2, max_wait: 1)
          end
        end
      end

    assert_match(/Fetching forecast/, out)
    assert_match(/Pushing forecast to InfluxDB/, out)
    assert_empty(err)
  end

  def test_start_successful_with_solcast
    config = Config.from_env(forecast_provider: 'solcast')

    out, err =
      capture_io do
        VCR.use_cassette('solcast_success') do
          VCR.use_cassette('influxdb') do
            Loop.start(config:, max_count: 2, max_wait: 1)
          end
        end
      end

    assert_match(/Fetching forecast/, out)
    assert_match(/Pushing forecast to InfluxDB/, out)
    assert_empty(err)
  end

  def test_start_fail
    config = Config.from_env

    out, err =
      capture_io do
        VCR.use_cassette('forecast_solar_fail') do
          Loop.start(config:, max_count: 1, max_wait: 1)
        end
      end

    assert_match(/Too Many Requests/, out)
    assert_empty(err)
  end

  def test_start_fail_when_influxdb_not_ready
    config = Config.from_env

    out, err =
      capture_io do
        Loop.start(config:, max_wait: 1, max_count: 1)
      end

    assert_match(/InfluxDB not ready/, out)
    assert_empty(err)
  end
end
