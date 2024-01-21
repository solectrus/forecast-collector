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

  def test_accumulation
    base_plane = {
      latitude: '51.13',
      longitude: '10.42',
      azimuth: '0',
      declination: '30',
      damping_morning: '0',
      damping_evening: '0',
    }

    out, err =
      capture_io do
        # Two planes with 4 and 5 kwp
        multi_plane_result =
          VCR.use_cassettes([{ name: 'forecast_solar_multiplane' }]) do
            Forecast.new(
              config:
                Config.from_env(
                  forecast_configurations: [
                    base_plane.merge(kwp: '4'),
                    base_plane.merge(kwp: '5'),
                  ],
                ),
            ).fetch_data
          end

        # Single plane with 9 kwp
        single_plane_result =
          VCR.use_cassettes([{ name: 'forecast_solar_singleplane' }]) do
            Forecast.new(
              config:
                Config.from_env(
                  forecast_configurations: [base_plane.merge(kwp: '9')],
                ),
            ).fetch_data
          end

        # Result should be the same: Same keys, same values (accept small delta)
        assert_equal(multi_plane_result.keys, single_plane_result.keys)
        single_plane_result.each do |key, value|
          assert_in_delta(value, multi_plane_result[key], 2)
        end
      end

    assert_match(/OK/, out)
    assert_empty(err)
  end
end
