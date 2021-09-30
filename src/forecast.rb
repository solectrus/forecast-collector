require 'net/http'

class Forecast
  def current
    forecast_response.dig('result', 'watts').map do |point|
      [Time.parse(point[0]), { watt: point[1] }]
    end.to_h
  end

  def uri
    URI.parse("https://api.forecast.solar/estimate/#{latitude}/#{longitude}/#{declination}/#{azimuth}/#{kwp}?time=utc")
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
