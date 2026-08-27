require 'time'

module Pvnode
  # Parses the ISO 8601 timestamps of the pvnode v2 API.
  #
  # The request asks for `timezone=utc`, so the API sends timestamps that end
  # in `Z`. A timestamp without a zone would be read as machine-local time,
  # which differs between a developer machine and the UTC-based containers.
  # Such a timestamp is rejected instead of read as a wrong point in time.
  module Timestamp
    ZONED = /(?:Z|[+-]\d{2}:?\d{2})\z/
    private_constant :ZONED

    # @raise [ArgumentError] if the timestamp carries no timezone
    def self.parse(value)
      raise ArgumentError, "Timestamp without timezone: #{value}" unless value.to_s.match?(ZONED)

      Time.iso8601(value).utc
    end

    # @return [Time, nil] nil for a timestamp the collector cannot read. A
    #   timestamp is a recommendation, never data the collector needs.
    def self.parse_or_nil(value)
      parse(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
