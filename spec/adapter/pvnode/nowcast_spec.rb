require 'adapter/pvnode/nowcast'
require 'adapter/pvnode/slots'

describe Pvnode::Nowcast do
  let(:nowcast) { described_class.new(slots:, required_requests_count:) }
  let(:required_requests_count) { 1 }
  let(:slots) do
    Pvnode::Slots.new(paid: true, nowcast: true, required_requests_count:)
  end

  describe '#update_daylight' do
    it 'extracts sunrise and sunset from clearsky data' do
      allow(Time).to receive(:now).and_return(time_today('12:00'))

      data = build_clearsky_data(
        '06:00' => 0,
        '07:00' => 100,
        '08:00' => 300,
        '18:00' => 50,
        '19:00' => 0,
      )

      nowcast.update_daylight(data)

      # Sunrise at 07:00, sunset at 18:00 (first/last positive clearsky)
      expect(nowcast).to be_daytime
    end

    it 'handles nil data gracefully' do
      nowcast.update_daylight(nil)

      expect(nowcast.daytime?).to be false
    end

    it 'handles empty data' do
      nowcast.update_daylight({})

      expect(nowcast.daytime?).to be false
    end

    it 'handles data with no clearsky values today' do
      # Only zero values
      data = build_clearsky_data(
        '06:00' => 0,
        '12:00' => 0,
        '18:00' => 0,
      )

      nowcast.update_daylight(data)

      expect(nowcast.daytime?).to be false
    end

    it 'keeps previous sunrise/sunset when a later response has no tomorrow data' do
      allow(Time).to receive(:now).and_return(time_today('12:00'))

      nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50))
      expect(nowcast).to be_daytime

      # Simulate a follow-up fetch that returns no usable tomorrow clearsky data.
      nowcast.update_daylight({})

      expect(nowcast).to be_daytime
    end
  end

  describe '#daytime?' do
    before { allow(Time).to receive(:now).and_return(now) }

    context 'when between sunrise and sunset' do
      let(:now) { time_today('12:00') }

      it 'returns true' do
        nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50))

        expect(nowcast).to be_daytime
      end
    end

    context 'when before sunrise' do
      let(:now) { time_today('05:00') }

      it 'returns false' do
        nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50))

        expect(nowcast).not_to be_daytime
      end
    end

    context 'when after sunset' do
      let(:now) { time_today('20:00') }

      it 'returns false' do
        nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50))

        expect(nowcast).not_to be_daytime
      end
    end

    context 'when no data has been loaded' do
      let(:now) { time_today('12:00') }

      it 'returns false' do
        expect(nowcast).not_to be_daytime
      end
    end
  end

  describe '#next_fetch_time' do
    before { allow(Time).to receive(:now).and_return(now) }

    context 'when daytime at :00' do
      let(:now) { time_today('12:00') }

      before { nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50)) }

      it 'returns next aligned time at :04' do
        expect(nowcast.next_fetch_time).to eq(time_today('12:04'))
      end
    end

    context 'when daytime at :04' do
      let(:now) { time_today('12:04') }

      before { nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50)) }

      it 'returns next aligned time at :14' do
        expect(nowcast.next_fetch_time).to eq(time_today('12:14'))
      end
    end

    context 'when daytime at :07' do
      let(:now) { time_today('12:07') }

      before { nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50)) }

      it 'returns next aligned time at :14' do
        expect(nowcast.next_fetch_time).to eq(time_today('12:14'))
      end
    end

    context 'when daytime at :54' do
      let(:now) { time_today('12:54') }

      before { nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50)) }

      it 'returns next aligned time at :04 of next hour' do
        expect(nowcast.next_fetch_time).to eq(time_today('13:04'))
      end
    end

    context 'when daytime and close to sunset' do
      let(:now) { time_today('18:55') }

      before { nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50)) }

      it 'falls back to slots when next aligned time would exceed sunset' do
        # next aligned = 19:04, which is past sunset (19:00)
        expect(nowcast.next_fetch_time).to eq(slots.next_fetch_time)
      end
    end

    context 'when nighttime' do
      let(:now) { time_today('22:00') }

      before { nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50)) }

      it 'delegates to slots' do
        expect(nowcast.next_fetch_time).to eq(slots.next_fetch_time)
      end
    end

    context 'when no data has been loaded' do
      let(:now) { time_today('12:00') }

      it 'delegates to slots' do
        expect(nowcast.next_fetch_time).to eq(slots.next_fetch_time)
      end
    end
  end

  describe '#interval_minutes' do
    context 'with 1 request per fetch' do
      let(:required_requests_count) { 1 }

      it 'uses the base 10-minute interval' do
        # 3000/31/1 = 96.77 ≥ 72 daylight slots → skip_factor = 1
        expect(nowcast.interval_minutes).to eq(10)
      end
    end

    context 'with 2 requests per fetch' do
      let(:required_requests_count) { 2 }

      it 'stretches to 20 minutes' do
        # 3000/31/2 = 48.39 < 72 → skip_factor = ceil(72/48.39) = 2
        expect(nowcast.interval_minutes).to eq(20)
      end
    end

    context 'with 3 requests per fetch' do
      let(:required_requests_count) { 3 }

      it 'stretches to 30 minutes' do
        # 3000/31/3 = 32.26 < 72 → skip_factor = ceil(72/32.26) = 3
        expect(nowcast.interval_minutes).to eq(30)
      end
    end
  end

  describe '#next_fetch_time with stretched interval' do
    # 2 requests/fetch → interval_minutes = 20
    let(:required_requests_count) { 2 }

    before do
      allow(Time).to receive(:now).and_return(now)
      nowcast.update_daylight(build_clearsky_data('07:00' => 100, '19:00' => 50))
    end

    context 'when at :04' do
      let(:now) { time_today('12:04') }

      it 'returns next aligned time at :24 (20-minute step)' do
        expect(nowcast.next_fetch_time).to eq(time_today('12:24'))
      end
    end

    context 'when at :24' do
      let(:now) { time_today('12:24') }

      it 'returns next aligned time at :44' do
        expect(nowcast.next_fetch_time).to eq(time_today('12:44'))
      end
    end

    context 'when at :44' do
      let(:now) { time_today('12:44') }

      it 'returns next aligned time at :04 of next hour' do
        expect(nowcast.next_fetch_time).to eq(time_today('13:04'))
      end
    end
  end

  describe '#next_fetch_time across a DST transition' do
    # Europe/Berlin spring-forward: 2026-03-29 02:00 local → 03:00 local.
    # Simulate a server running in that zone at local noon that day.
    around do |example|
      ClimateControl.modify(TZ: 'Europe/Berlin') { example.run }
    end

    let(:now) { Time.utc(2026, 3, 29, 10, 0, 0) } # 12:00 local, 10:00 UTC

    before do
      allow(Time).to receive(:now).and_return(now)
      # Sunrise/sunset derived from UTC clearsky timestamps
      tomorrow = Time.utc(2026, 3, 30)
      data = {
        (tomorrow + (5 * 3600)).to_i => { watt_clearsky: 100 },
        (tomorrow + (18 * 3600)).to_i => { watt_clearsky: 50 },
      }
      nowcast.update_daylight(data)
    end

    it 'aligns to the next :04 UTC regardless of local DST jump' do
      expect(nowcast.next_fetch_time).to eq(Time.utc(2026, 3, 29, 10, 4, 0))
    end
  end

  private

  def time_today(hhmm)
    hour, minute = hhmm.split(':').map(&:to_i)
    today = Time.now.utc
    Time.utc(today.year, today.month, today.day, hour, minute, 0)
  end

  def build_clearsky_data(hour_values)
    tomorrow = Time.now.utc + 86_400
    hour_values.each_with_object({}) do |(hhmm, watt), result|
      hour, minute = hhmm.split(':').map(&:to_i)
      timestamp = Time.utc(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute, 0).to_i
      result[timestamp] = { watt: watt, watt_clearsky: watt, temp: 20.0 }
    end
  end
end
