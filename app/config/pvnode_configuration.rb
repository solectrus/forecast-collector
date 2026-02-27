class PvnodeConfiguration
  def self.from_env(index, prefix, defaults)
    {
      latitude: ENV.fetch("FORECAST_#{index}_LATITUDE", defaults[:latitude]),
      longitude: ENV.fetch("FORECAST_#{index}_LONGITUDE", defaults[:longitude]),
      declination: ENV.fetch("FORECAST_#{index}_DECLINATION", defaults[:declination]),
      azimuth: ENV.fetch("FORECAST_#{index}_AZIMUTH", defaults[:azimuth]),
      kwp: ENV.fetch("FORECAST_#{index}_KWP", defaults[:kwp]),
      extra_params: ENV.fetch("#{prefix}_#{index}_EXTRA_PARAMS", defaults[:extra_params]),
    }
  end
end
