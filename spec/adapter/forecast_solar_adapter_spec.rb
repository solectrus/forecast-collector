require 'adapter/forecast_solar_adapter'

describe ForecastSolarAdapter do
  let(:config) { Config.from_env }
  let(:forecast) { described_class.new(config: config) }

  describe '#fetch_data' do
    context 'when successful' do
      it 'returns forecast data' do
        stdout, stderr = capture_output do
          VCR.use_cassette('forecast_solar_success') do
            data = forecast.fetch_data

            expect(data).to be_a(Hash)
            data.each do |key, value|
              expect(key).to be_an(Integer)
              expect(value).to be_an(Integer)
            end
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/OK/)
      end
    end

    context 'when request fails' do
      it 'returns nil' do
        stdout, stderr = capture_output do
          VCR.use_cassette('forecast_solar_fail') do
            data = forecast.fetch_data
            expect(data).to be_nil
          end
        end

        expect(stderr).to be_empty
        expect(stdout).to match(/Too Many Requests/)
      end
    end
  end

  describe 'accumulation across multiple planes' do
    let(:base_plane) do
      {
        latitude: '51.13',
        longitude: '10.42',
        azimuth: '0',
        declination: '30',
        damping_morning: '0',
        damping_evening: '0',
      }
    end

    it 'accumulates results from multiple planes correctly' do
      stdout, stderr = capture_output do
        # Two planes with 4 and 5 kwp
        multi_plane_result = VCR.use_cassettes([{ name: 'forecast_solar_multiplane' }]) do
          described_class.new(
            config: Config.from_env(
              forecast_solar_configurations: [
                base_plane.merge(kwp: '4'),
                base_plane.merge(kwp: '5'),
              ],
            ),
          ).fetch_data
        end

        # Single plane with 9 kwp
        single_plane_result = VCR.use_cassettes([{ name: 'forecast_solar_singleplane' }]) do
          described_class.new(
            config: Config.from_env(
              forecast_solar_configurations: [base_plane.merge(kwp: '9')],
            ),
          ).fetch_data
        end

        # Result should be the same: Same keys, same values (accept small delta)
        expect(multi_plane_result.keys).to eq(single_plane_result.keys)
        single_plane_result.each do |key, value|
          expect(multi_plane_result[key]).to be_within(2).of(value)
        end
      end

      expect(stderr).to be_empty
      expect(stdout).to match(/OK/)
    end
  end
end
