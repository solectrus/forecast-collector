# SimpleCov configuration. `SimpleCov.start` lives in spec/spec_helper.rb —
# this file is auto-loaded on `require "simplecov"` and must stay config-only.

SimpleCov.configure do
  # Include app files the suite never loads through a `require`, for example
  # app/main.rb. Without this they are absent from the report rather than
  # counted as uncovered, which overstates the coverage figure.
  cover 'app/**/*.rb'

  enable_coverage :branch
  primary_coverage :branch

  minimum_coverage line: 100, branch: 100
end
