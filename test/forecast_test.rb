require 'test_helper'
require 'forecast'
require 'config'

class ForecastTest < Minitest::Test
  def test_current_success
    config = Config.from_env

    VCR.use_cassette('forecast_solar_success') do
      forecast = Forecast.new(config:).current

      assert forecast.is_a?(Hash)
      forecast.each do |key, value|
        assert key.is_a?(Integer)
        assert value.is_a?(Integer)
      end
    end
  end

  def test_current_fail
    config = Config.from_env

    VCR.use_cassette('forecast_solar_fail') do
      assert_raises Net::HTTPFatalError do
        Forecast.new(config:).current
      end
    end
  end
end
