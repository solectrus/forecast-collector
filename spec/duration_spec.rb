require 'duration'

describe Integer do
  describe 'time units' do
    it 'converts every unit to seconds' do
      expect(30.seconds).to eq(30)
      expect(15.minutes).to eq(900)
      expect(2.hours).to eq(7_200)
      expect(31.days).to eq(2_678_400)
    end

    it 'reads a single unit in the singular' do
      expect(1.second).to eq(1)
      expect(1.minute).to eq(60)
      expect(1.hour).to eq(3_600)
      expect(1.day).to eq(86_400)
    end

    it 'returns an Integer, so the result can be added to a Time' do
      expect(5.minutes).to be_an(described_class)
      expect(Time.utc(2026, 8, 27, 12) + 30.minutes).to eq(Time.utc(2026, 8, 27, 12, 30))
    end
  end
end
