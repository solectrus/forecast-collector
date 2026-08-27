require 'json'
require 'tmpdir'
require 'fileutils'
require 'adapter/pvnode/timestamp'

module Pvnode
  # Remembers when the next pvnode request returns something new, so a restart
  # of the collector does not cost a request.
  #
  # Only the time is stored, not the forecast. The forecast is already in
  # InfluxDB, where SOLECTRUS reads it. A restart therefore needs nothing but
  # the time of the next slot.
  #
  # The file lives in the temporary directory, which needs no setting and no
  # volume. That is enough for the case that costs the most requests: a crash
  # loop or a restart of the same container repeats the request every time. A
  # new container (an update of the image) starts without the file and costs
  # one request.
  #
  # A fault of the file system never stops the collector. A state that cannot
  # be read or written only costs one request.
  #
  # See https://pvnode.com/docs/v2/integrations/build-your-own
  class PollState
    # @param site_id [String] the site the time belongs to. A state of another
    #   site is dropped, because the slots of the API are per site.
    # @param path [String] file to store the time in
    def initialize(site_id:, path: File.join(Dir.tmpdir, 'forecast-collector-pvnode.json'))
      @site_id = site_id
      @path = path
    end

    # @return [Time, nil] the stored time, nil if there is none to trust
    def next_poll_at
      stored = JSON.parse(File.read(path))
      return unless stored['site_id'] == site_id

      Pvnode::Timestamp.parse(stored['next_poll_at'])
    rescue StandardError
      nil
    end

    # Stores the recommendation of the API. A response without one drops the
    # stored time, so a restart cannot use a slot that already passed.
    def save(next_poll_at)
      return FileUtils.rm_f(path) unless next_poll_at

      File.write(path, JSON.generate(site_id:, next_poll_at:))
    rescue StandardError => e
      puts "  WARNING: Cannot save the pvnode schedule to #{path}: #{e.message}"
    end

    private

    attr_reader :path, :site_id
  end
end
