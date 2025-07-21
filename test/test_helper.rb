require 'simplecov'
require 'simplecov_json_formatter'
SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::JSONFormatter,
    SimpleCov::Formatter::HTMLFormatter,
  ])
end

require 'minitest/autorun'
require 'climate_control'

require File.expand_path './support/vcr_setup.rb', __dir__

# Silence deprecation warnings caused by the `influxdb-client` gem
Warning[:deprecated] = false
