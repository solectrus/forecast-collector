require 'test_helper'
require 'forecast'

class ForecastTest < Minitest::Test
  def test_current_success
    VCR.use_cassette('forecast_solar_success') do
      forecast = Forecast.new.current

      assert forecast.is_a?(Hash)
      forecast.each do |key, value|
        assert key.is_a?(Integer)
        assert value.is_a?(Integer)
      end
    end
  end

  def test_current_fail
    VCR.use_cassette('forecast_solar_fail') do
      assert_raises Net::HTTPClientException do
        Forecast.new.current
      end
    end
  end
end
