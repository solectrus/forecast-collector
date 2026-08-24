#!/usr/bin/env ruby

# Add app directory to load path so we can use simple require statements
$LOAD_PATH.unshift(__dir__)

require 'dotenv/load'
require 'loop'
require 'config'
require 'app_version'

# Flush output immediately
$stdout.sync = true

puts 'Forecast collector for SOLECTRUS, ' \
       "Version #{AppVersion.current || '<unknown>'}, " \
       "built at #{ENV.fetch('BUILDTIME', '<unknown>')}"
puts 'https://github.com/solectrus/forecast-collector'
puts 'Copyright (c) 2020-2026 Georg Ledermann, released under the MIT License'
puts "\n"

config = Config.from_env

puts "Using Ruby #{RUBY_VERSION} on platform #{RUBY_PLATFORM}"

# Resolved before the message, so anything the adapter reports while it is
# built (for example the pvnode site) is printed in order.
adapter = config.adapter
puts "Pulling from #{adapter.provider_name} #{adapter.pull_interval_message}"
puts "Pushing to InfluxDB at #{config.influx_url}, " \
       "bucket #{config.influx_bucket}, " \
       "measurement #{config.influx_measurement}"
puts "\n"

Loop.start(config:)
