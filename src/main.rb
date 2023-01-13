#!/usr/bin/env ruby

require 'dotenv/load'
require_relative 'loop'
require_relative 'config'

# Flush output immediately
$stdout.sync = true

puts 'Forecast collector for SOLECTRUS'
puts 'https://github.com/solectrus/forecast-collector'
puts 'Copyright (c) 2020,2023 Georg Ledermann, released under the MIT License'
puts "\n"

config = Config.from_env

puts "Using Ruby #{RUBY_VERSION} on platform #{RUBY_PLATFORM}"
puts "Pulling from api.forecast.solar every #{config.forecast_interval} seconds"
puts "Pushing to InfluxDB at #{config.influx_url}, bucket #{config.influx_bucket}"
puts "\n"

Loop.start(config:)
