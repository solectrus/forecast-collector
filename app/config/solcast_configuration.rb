class SolcastConfiguration
  attr_reader :site

  def initialize(options = {})
    options.each { |key, value| instance_variable_set("@#{key}", value) }
  end

  def [](key)
    public_send(key)
  end

  def self.from_env(index, prefix, defaults)
    { site: ENV.fetch("#{prefix}_#{index}_SITE", defaults[:solcast_site]) }
  end
end
