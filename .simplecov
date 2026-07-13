# SimpleCov configuration. `SimpleCov.start` lives in spec/spec_helper.rb —
# this file is auto-loaded on `require "simplecov"` and must stay config-only.

SimpleCov.configure do
  # Include app files the suite never loads (app/adapters.rb, app/main.rb).
  # Without this they are absent from the report rather than counted as
  # uncovered, which overstates the coverage figure.
  cover 'app/**/*.rb'
end
