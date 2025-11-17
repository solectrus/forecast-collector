require 'adapter/base_adapter'
require 'config'

describe BaseAdapter do
  let(:config) { instance_double(Config) }
  let(:adapter) { described_class.new(config:) }

  describe '#accumulate' do
    context 'with scalar values' do
      it 'sums values for the same timestamp' do
        hashes = [
          {
            1000 => 100,
            2000 => 200,
          },
          {
            1000 => 50,
            2000 => 75,
          },
        ]

        result = adapter.accumulate(hashes)

        expect(result).to eq(
          1000 => 150,
          2000 => 275,
        )
      end
    end

    context 'with hash values containing watt fields' do
      it 'sums watt values from multiple sources' do
        hashes = [
          { 1000 => { watt: 100, temp: 20.5 } },
          { 1000 => { watt: 50, temp: 20.5 } },
        ]

        result = adapter.accumulate(hashes)

        expect(result).to eq(
          1000 => { watt: 150, temp: 20.5 },
        )
      end

      it 'sums watt_clearsky values from multiple sources' do
        hashes = [
          { 1000 => { watt_clearsky: 200, temp: 20.5 } },
          { 1000 => { watt_clearsky: 100, temp: 20.5 } },
        ]

        result = adapter.accumulate(hashes)

        expect(result).to eq(
          1000 => { watt_clearsky: 300, temp: 20.5 },
        )
      end

      it 'keeps first value for non-watt fields (temperature)' do
        hashes = [
          { 1000 => { watt: 100, temp: 20.5 } },
          { 1000 => { watt: 50, temp: 25.0 } },
        ]

        result = adapter.accumulate(hashes)

        expect(result[1000][:temp]).to eq(20.5)
      end

      it 'keeps first value for weather_code' do
        hashes = [
          { 1000 => { watt: 100, weather_code: 1 } },
          { 1000 => { watt: 50, weather_code: 2 } },
        ]

        result = adapter.accumulate(hashes)

        expect(result[1000][:weather_code]).to eq(1)
      end

      it 'handles multiple watt fields correctly' do
        hashes = [
          { 1000 => { watt: 100, watt_clearsky: 150, temp: 20.5 } },
          { 1000 => { watt: 50, watt_clearsky: 75, temp: 20.5 } },
        ]

        result = adapter.accumulate(hashes)

        expect(result).to eq(
          1000 => { watt: 150, watt_clearsky: 225, temp: 20.5 },
        )
      end
    end

    context 'with mixed timestamps' do
      it 'accumulates values independently per timestamp' do
        hashes = [
          { 1000 => { watt: 100, temp: 20.5 },
            2000 => { watt: 200, temp: 21.0 }, },
          { 1000 => { watt: 50, temp: 20.5 },
            3000 => { watt: 150, temp: 22.5 }, },
        ]

        result = adapter.accumulate(hashes)

        expect(result).to eq(
          1000 => { watt: 150, temp: 20.5 },
          2000 => { watt: 200, temp: 21.0 },
          3000 => { watt: 150, temp: 22.5 },
        )
      end
    end

    context 'with nil values' do
      it 'filters out nil hashes' do
        hashes = [
          { 1000 => 100 },
          nil,
          { 1000 => 50 },
        ]

        result = adapter.accumulate(hashes)

        expect(result).to eq(1000 => 150)
      end

      it 'returns nil when all hashes are nil' do
        hashes = [nil, nil, nil]

        result = adapter.accumulate(hashes)

        expect(result).to be_nil
      end
    end

    context 'with single hash' do
      it 'returns the hash unchanged' do
        hashes = [
          { 1000 => { watt: 100, temp: 20.5 } },
        ]

        result = adapter.accumulate(hashes)

        expect(result).to eq(
          1000 => { watt: 100, temp: 20.5 },
        )
      end
    end

    context 'with empty array' do
      it 'returns nil' do
        result = adapter.accumulate([])

        expect(result).to be_nil
      end
    end
  end
end
