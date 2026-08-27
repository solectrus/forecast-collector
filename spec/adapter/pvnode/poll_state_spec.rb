require 'tmpdir'
require 'adapter/pvnode/poll_state'

describe Pvnode::PollState do
  subject(:state) { described_class.new(site_id: 'site_one', path:) }

  let(:path) { File.join(Dir.tmpdir, 'poll-state-spec.json') }

  it 'stores the file in the temporary directory, so it needs no configuration' do
    described_class.new(site_id: 'site_one').save('2026-08-27T14:00:00Z')

    expect(described_class.new(site_id: 'site_one').next_poll_at).to eq(Time.utc(2026, 8, 27, 14))
  end

  describe '#next_poll_at' do
    it 'returns what was saved' do
      state.save('2026-08-27T14:00:00Z')

      expect(state.next_poll_at).to eq(Time.utc(2026, 8, 27, 14, 0, 0))
    end

    it 'returns nil without a file' do
      expect(state.next_poll_at).to be_nil
    end

    it 'returns nil when the file is not readable JSON' do
      File.write(path, 'not json')

      expect(state.next_poll_at).to be_nil
    end

    it 'returns nil when the timestamp carries no timezone' do
      # It would be read as machine-local time, which differs between a
      # developer machine and the UTC-based containers.
      File.write(path, '{"site_id":"site_one","next_poll_at":"2026-08-27T14:00:00"}')

      expect(state.next_poll_at).to be_nil
    end

    it 'returns nil when the state belongs to another site' do
      # The slots of the API are per site, so the time says nothing about the
      # site the collector reads now.
      described_class.new(site_id: 'site_two', path:).save('2026-08-27T14:00:00Z')

      expect(state.next_poll_at).to be_nil
    end
  end

  describe '#save' do
    it 'drops the stored time when there is no recommendation' do
      state.save('2026-08-27T14:00:00Z')
      state.save(nil)

      expect(state.next_poll_at).to be_nil
    end

    it 'drops nothing when there is no file' do
      expect { state.save(nil) }.not_to raise_error
    end

    it 'warns but keeps running when the file cannot be written' do
      unwritable = described_class.new(site_id: 'site_one', path: '/does/not/exist/pvnode.json')

      stdout, = capture_output { expect { unwritable.save('2026-08-27T14:00:00Z') }.not_to raise_error }

      expect(stdout).to include('WARNING: Cannot save the pvnode schedule')
    end
  end
end
