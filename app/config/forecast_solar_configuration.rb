class ForecastSolarConfiguration
  attr_reader :latitude, :longitude, :declination, :azimuth, :kwp, :damping_morning, :damping_evening, :inverter,
              :horizon

  def initialize(options = {})
    options.each { |key, value| instance_variable_set("@#{key}", value) }
  end

  def [](key)
    public_send(key)
  end

  def self.from_env(index, prefix, defaults)
    {
      latitude: ENV.fetch("#{prefix}_#{index}_LATITUDE", defaults[:latitude]),
      longitude: ENV.fetch("#{prefix}_#{index}_LONGITUDE", defaults[:longitude]),
      declination: ENV.fetch("#{prefix}_#{index}_DECLINATION", defaults[:declination]),
      azimuth: ENV.fetch("#{prefix}_#{index}_AZIMUTH", defaults[:azimuth]),
      kwp: ENV.fetch("#{prefix}_#{index}_KWP", defaults[:kwp]),
      damping_morning: ENV.fetch("#{prefix}_#{index}_DAMPING_MORNING", defaults[:damping_morning]),
      damping_evening: ENV.fetch("#{prefix}_#{index}_DAMPING_EVENING", defaults[:damping_evening]),
      inverter: ENV.fetch("#{prefix}_#{index}_INVERTER", defaults[:inverter]),
      horizon: ENV.fetch("#{prefix}_#{index}_HORIZON", defaults[:horizon]),
    }
  end
end
