require 'test_helper'
require 'loop'
require 'config'

class LoopTest < Minitest::Test
  def test_start
    config = Config.from_env

    cassettes = [
      { name: 'forecast_solar_success_0' },
      { name: 'forecast_solar_success_1' },
      { name: 'influxdb' }
    ]
    VCR.use_cassettes(cassettes) do
      Loop.start(config:, max_count: 1)
    end
  end
end
