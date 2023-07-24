require 'test_helper'
require 'forecast'
require 'config'

class ForecastTest < Minitest::Test
  def test_current_success
    config = Config.from_env

    VCR.use_cassette('forecast_solar_success_0') do
      forecast = Forecast.new(config:).current(0)

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
      assert_raises Net::HTTPClientException do
        Forecast.new(config:).current(0)
      end
    end
  end
end
