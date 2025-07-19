require 'simplecov'
require 'simplecov_small_badge'

SimpleCov.start do
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCovSmallBadge::Formatter,
  ])
end

require 'minitest/autorun'
require 'climate_control'

require File.expand_path './support/vcr_setup.rb', __dir__

# Silence deprecation warnings caused by the `influxdb-client` gem
Warning[:deprecated] = false
