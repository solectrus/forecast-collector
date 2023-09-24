require 'test_helper'
require 'loop'
require 'config'

class LoopTest < Minitest::Test
  def test_start
    config = Config.from_env

    cassettes = [{ name: 'forecast_solar_success' }, { name: 'influxdb' }]
    VCR.use_cassettes(cassettes) { Loop.start(config:, max_count: 1) }
  end
end
