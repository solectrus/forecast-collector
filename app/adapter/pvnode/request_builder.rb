module Pvnode
  module RequestBuilder
    private

    # Groups planes into batches of up to 2 with identical extra_params.
    # Example: [[plane0, plane1], [plane2], [plane3, plane4]]
    def batched_planes
      @batched_planes ||=
        config.pvnode_configurations
              .group_by { |plane| plane[:extra_params] }
              .each_value
              .flat_map { |planes| planes.each_slice(2).to_a }
    end

    def build_params(first_plane, second_plane)
      params = {
        latitude: first_plane[:latitude],
        longitude: first_plane[:longitude],
        slope: first_plane[:declination],
        orientation: first_plane[:azimuth],
        pv_power_kw: first_plane[:kwp],
        required_data:,
        clearsky_data:,
        past_days:,
        forecast_days:,
      }.compact

      if second_plane
        params.merge!({
          second_array_slope: second_plane[:declination],
          second_array_orientation: second_plane[:azimuth],
          second_array_power_kw: second_plane[:kwp],
        }.compact)
      end

      params
    end

    # Sends the pvnode API key with every request.
    def request_headers
      super.merge('Authorization' => "Bearer #{config.pvnode_apikey}")
    end
  end
end
