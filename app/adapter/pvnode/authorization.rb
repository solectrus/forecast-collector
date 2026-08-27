module Pvnode
  # Sends the pvnode API key with every request.
  module Authorization
    private

    def request_headers
      super.merge('Authorization' => "Bearer #{config.pvnode_apikey}")
    end
  end
end
