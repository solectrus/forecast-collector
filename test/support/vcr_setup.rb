require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'test/cassettes'
  config.hook_into :webmock

  # Remove Cookie header
  config.before_record { |i| i.response.headers.delete('Set-Cookie') }

  sensitive_environment_variables = %w[
    INFLUX_HOST
    INFLUX_PORT
    INFLUX_TOKEN
    INFLUX_ORG
    INFLUX_BUCKET
    FORECAST_LATITUDE
    FORECAST_LONGITUDE
    SOLCAST_APIKEY
    SOLCAST_0_SITE
    SOLCAST_1_SITE
    SOLCAST_SITE
    FORECAST_SOLAR_APIKEY
  ]
  sensitive_environment_variables.each do |key_name|
    config.filter_sensitive_data("<#{key_name}>") { ENV.fetch(key_name, nil) }
  end

  record_mode = ENV['VCR'] ? ENV['VCR'].to_sym : :once
  config.default_cassette_options = {
    record: record_mode,
    allow_playback_repeats: true,
  }
end
