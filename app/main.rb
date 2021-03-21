#!/usr/bin/env ruby

require 'dotenv/load'
require 'influxdb-client'

require_relative 'forecast_loop'

# Flush output immediately
$stdout.sync = true

ForecastLoop.start
