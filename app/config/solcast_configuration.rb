class SolcastConfiguration
  def self.from_env(index, prefix, defaults)
    { site: ENV.fetch("#{prefix}_#{index}_SITE", defaults[:solcast_site]) }
  end
end
