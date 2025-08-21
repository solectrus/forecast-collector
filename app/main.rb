#!/usr/bin/env ruby

# Add app directory to load path so we can use simple require statements
$LOAD_PATH.unshift(__dir__)

require 'dotenv/load'
require 'loop'
require 'config'

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

puts "Pulling from #{config.adapter.provider_name} every #{config.forecast_interval} seconds"
puts "Pushing to InfluxDB at #{config.influx_url}, " \
       "bucket #{config.influx_bucket}, " \
       "measurement #{config.influx_measurement}"
puts "\n"

Loop.start(config:)
