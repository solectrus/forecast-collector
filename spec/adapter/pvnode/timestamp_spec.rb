require 'adapter/pvnode/timestamp'

describe Pvnode::Timestamp do
  describe '.parse' do
    it 'reads a UTC timestamp' do
      expect(described_class.parse('2026-07-15T12:00:00Z')).to eq(Time.utc(2026, 7, 15, 12, 0, 0))
    end

    it 'converts a timestamp with an offset to UTC' do
      expect(described_class.parse('2026-07-15T12:00:00+02:00')).to eq(Time.utc(2026, 7, 15, 10, 0, 0))
    end

    it 'accepts an offset without a colon' do
      expect(described_class.parse('2026-07-15T12:00:00+0200')).to eq(Time.utc(2026, 7, 15, 10, 0, 0))
    end

    it 'rejects a timestamp without a timezone' do
      # Such a timestamp would be read as machine-local time and silently
      # become a wrong point in time.
      expect { described_class.parse('2026-07-15T12:00:00') }.to raise_error(
        ArgumentError, /Timestamp without timezone/,
      )
    end

    it 'rejects a value that is no timestamp' do
      expect { described_class.parse('tomorrow') }.to raise_error(ArgumentError)
    end
  end
end
