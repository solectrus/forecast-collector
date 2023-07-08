require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'test/cassettes'
  config.hook_into :webmock

  sensitive_environment_variables = %w[
    INFLUX_HOST
    INFLUX_PORT
    INFLUX_TOKEN
    INFLUX_ORG
    INFLUX_BUCKET
    FORECAST_LATITUDE
    FORECAST_LONGITUDE
  ]
  sensitive_environment_variables.each do |key_name|
    config.filter_sensitive_data("<#{key_name}>") { ENV.fetch(key_name) }
  end
end
