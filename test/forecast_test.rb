require 'test_helper'
require 'forecast'
require 'config'

class ForecastTest < Minitest::Test
  def test_fetch_data_success
    config = Config.from_env
    forecast = Forecast.new(config:)

    out, err =
      capture_io do
        VCR.use_cassette('forecast_solar_success') do
          data = forecast.fetch_data

          assert data.is_a?(Hash)
          data.each do |key, value|
            assert key.is_a?(Integer)
            assert value.is_a?(Integer)
          end
        end
      end

    assert_match(/OK/, out)
    assert_empty(err)
  end

  def test_fetch_data_fail
    config = Config.from_env
    forecast = Forecast.new(config:)

    out, err =
      capture_io do
        VCR.use_cassette('forecast_solar_fail') do
          data = forecast.fetch_data

          assert_nil data
        end
      end

    assert_match(/Too Many Requests/, out)
    assert_empty(err)
  end
end
