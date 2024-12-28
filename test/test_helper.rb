require 'simplecov'
SimpleCov.start

require 'minitest/autorun'
require 'climate_control'

require File.expand_path './support/vcr_setup.rb', __dir__

# Silence deprecation warnings caused by the `influxdb-client` gem
Warning[:deprecated] = false
