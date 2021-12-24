require 'net/http'

class Forecast
  def current
    # Change mapping:
    #   "result": {
    #     "watts": {
    #       "1632979620": 0,
    #       "1632984240": 28,
    #       "1632988800": 119,
    #    .....
    #   =>
    #   { 1632979620 => 0, 1632980640 => 28, 1632981600 => 119, ... }

    forecast_response
      .dig('result', 'watts')
      .transform_keys(&:to_i)
  end

  def uri
    URI.parse("https://api.forecast.solar/estimate/#{latitude}/#{longitude}/#{declination}/#{azimuth}/#{kwp}?time=seconds")
  end

  private

  def forecast_response
    response = Net::HTTP.get_response(uri)

    case response
    when Net::HTTPOK
      JSON.parse(response.body)
    else
      throw "Failure: #{response.value}"
    end
  end

  def latitude
    @latitude ||= ENV.fetch('FORECAST_LATITUDE')
  end

  def longitude
    @longitude ||= ENV.fetch('FORECAST_LONGITUDE')
  end

  def declination
    @declination ||= ENV.fetch('FORECAST_DECLINATION')
  end

  def azimuth
    @azimuth ||= ENV.fetch('FORECAST_AZIMUTH')
  end

  def kwp
    @kwp ||= ENV.fetch('FORECAST_KWP')
  end
end
