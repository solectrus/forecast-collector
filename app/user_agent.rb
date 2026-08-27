require 'app_version'

# User agent sent with every outgoing HTTP request, so providers can identify
# the collector and its version.
module UserAgent
  APP_NAME = 'Forecast-Collector'.freeze
  HOMEPAGE = 'https://github.com/solectrus/forecast-collector'.freeze

  def self.current
    identifier = [APP_NAME, AppVersion.current].compact.join('/')

    "#{identifier} (+#{HOMEPAGE})"
  end
end
