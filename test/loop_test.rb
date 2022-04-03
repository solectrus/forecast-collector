require 'test_helper'
require 'loop'
require 'config'

class LoopTest < Minitest::Test
  def test_start
    config = Config.from_env

    VCR.use_cassette('forecast_solar_success') do
      VCR.use_cassette('influxdb') do
        Loop.start(config:, max_count: 1)
      end
    end
  end
end
