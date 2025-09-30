require 'net/http'

# Base class for all forecast adapters.
# Provides common functionality for fetching and accumulating forecast data
# from different weather/solar forecast services.
#
# Subclasses must implement:
# - #fetch(index) - fetches and parses data for a configuration
# - #adapter_configuration_count - returns number of configurations
# - #formatted_url(index) - returns complete API URL for a configuration
class BaseAdapter
  def initialize(config:)
    @config = config
  end

  attr_reader :config

  def fetch_data
    hashes = []
    configuration_count = adapter_configuration_count

    (0...configuration_count).each do |index|
      print "  #{index}: #{url(index)} ... "
      begin
        hashes.append(fetch(index))
        puts 'OK'
      rescue StandardError => e
        puts "Error #{e}"
      end
    end

    accumulate(hashes)
  end

  def accumulate(hashes)
    result = hashes[0]
    (1...hashes.length).each do |index|
      hashes[index].each do |k, v|
        result[k] ||= 0
        result[k] += v
      end
    end

    result
  end

  def url(index)
    URI.parse(formatted_url(index))
  end

  # Fetches forecast data for the given configuration index.
  # Must return a Hash with timestamp keys (Integer) and power values (Integer).
  # Format: { timestamp => watts, ... }
  # Example: { 1715011200 => 541, 1715013000 => 555 }
  def fetch(index)
    http_response = make_http_request(index)
    parsed_data = parse_json_response(http_response)
    parse_forecast_data(parsed_data)
  end

  # Step 1: Makes the HTTP request and returns the raw response
  # Can be overridden by subclasses for custom HTTP handling (e.g., authentication)
  def make_http_request(index)
    uri = url(index)
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = user_agent

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end
  end

  # Step 2: Parses the JSON response from HTTP response
  # Can be overridden by subclasses for custom parsing (e.g., XML, non-JSON APIs)
  def parse_json_response(http_response)
    case http_response
    when Net::HTTPOK
      JSON.parse(http_response.body)
    else
      throw "Failure: #{http_response.code} #{http_response.message}"
    end
  end

  # Step 3: Extracts forecast data from parsed response into standard format.
  # Must be implemented by subclasses to handle their specific response structure.
  def parse_forecast_data(response_data)
    # :nocov:
    raise NotImplementedError, 'Subclass must implement #parse_forecast_data'
    # :nocov:
  end

  # Returns the display name of the provider
  # Can be overridden by subclasses for custom names
  def provider_name
    self.class.name.sub('Adapter', '')
  end

  # Returns the next fetch time as a Time object
  # Can be overridden by subclasses for custom scheduling
  def next_fetch_time
    Time.now + config.forecast_interval
  end

  private

  # Returns the number of configurations for this adapter.
  # Used to determine how many API calls to make.
  # Must return an Integer.
  def adapter_configuration_count
    # :nocov:
    raise NotImplementedError, 'Subclass must implement #adapter_configuration_count'
    # :nocov:
  end

  # Returns the complete URL for the API call for the given configuration index.
  # Should include all necessary parameters (API key, coordinates, etc.).
  # Must return a String.
  # Example: "https://api.example.com/forecast?lat=51.13&lon=10.42&api_key=abc123"
  def formatted_url(index)
    # :nocov:
    raise NotImplementedError, 'Subclass must implement #formatted_url'
    # :nocov:
  end

  def user_agent
    app = 'Forecast-Collector'
    version = ENV.fetch('VERSION', nil)
    identifier = [app, version].compact.join('/')

    "#{identifier} (+https://github.com/solectrus/forecast-collector)"
  end
end
