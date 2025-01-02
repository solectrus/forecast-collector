#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'loop'
require_relative 'config'

# Flush output immediately
$stdout.sync = true

puts 'Forecast collector for SOLECTRUS, ' \
       "Version #{ENV.fetch('VERSION', '<unknown>')}, " \
       "built at #{ENV.fetch('BUILDTIME', '<unknown>')}"
puts 'https://github.com/solectrus/forecast-collector'
puts 'Copyright (c) 2020-2025 Georg Ledermann, released under the MIT License'
puts "\n"

config = Config.from_env

puts "Using Ruby #{RUBY_VERSION} on platform #{RUBY_PLATFORM}"
host = case config.forecast_provider
       when 'forecast.solar'
         'api.forecast.solar'
       when 'solcast'
         'api.solcast.com.au'
       end

puts "Pulling from #{host} every #{config.forecast_interval} seconds"
puts "Pushing to InfluxDB at #{config.influx_url}, " \
       "bucket #{config.influx_bucket}, " \
       "measurement #{config.influx_measurement}"
puts "\n"

Loop.start(config:)
