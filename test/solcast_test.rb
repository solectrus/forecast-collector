require 'test_helper'
require 'solcast'
require 'config'

class SolcastTest < Minitest::Test
  def test_fetch_data_success
    config = Config.from_env(
      forecast_provider: 'solcast',
    )
    solcast = Solcast.new(config:)

    out, err =
      capture_io do
        VCR.use_cassette('solcast_success') do
          data = solcast.fetch_data

          assert_kind_of Hash, data
          data.each do |key, value|
            assert_kind_of Integer, key
            assert_kind_of Integer, value
          end
        end
      end

    assert_match(/OK/, out)
    assert_empty(err)
  end
end
