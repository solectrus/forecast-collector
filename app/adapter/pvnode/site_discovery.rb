require 'net/http'
require 'json'
require 'user_agent'

module Pvnode
  # Finds the pvnode site to use when PVNODE_SITE_ID is not configured.
  #
  # The sites endpoint is open to every plan. If the account has exactly one
  # usable site, the collector uses it. The user then only needs to set an API
  # key. In every other case the collector cannot decide and says what to do.
  #
  # A site is usable if it is active and not pending deletion.
  class SiteDiscovery
    # Raised when the sites cannot be read at all. This is different from an
    # account without a site: after an error the collector knows nothing about
    # the account and must not guess.
    class RequestFailed < StandardError; end

    # Raised when the account has sites, but none the collector can pick on its
    # own. Only the user can say which site to use, or which one to activate.
    class SelectionRequired < StandardError; end

    URL = 'https://api.pvnode.com/v2/sites/'.freeze

    def initialize(apikey:)
      @apikey = apikey
    end

    # @return [String, nil] the id of the only usable site of the account. Nil
    #   if the account has no site at all, which is the state of a user of the
    #   v1 API.
    # @raise [RequestFailed] if the sites cannot be read
    # @raise [SelectionRequired] if the account has sites, but not one usable
    def site_id
      return unless apikey

      sites = fetch_sites
      usable = sites.select { |site| usable?(site) }

      case usable.length
      when 0 then report_no_usable_site(sites)
      when 1 then report_single_site(usable.first)
      else report_multiple_sites(usable)
      end
    end

    private

    attr_reader :apikey

    def fetch_sites
      response = perform_request
      unless response.is_a?(Net::HTTPOK)
        raise RequestFailed, "HTTP #{response.code} #{response.message} - #{detail(response)}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise RequestFailed, "unexpected response - #{e.message}"
    end

    # Sites that are pending deletion or inactive are part of the response, but
    # cannot be used for a forecast. An unknown status counts as usable, so a
    # new status of the API cannot hide every site of the account.
    def usable?(site)
      site['deleted_at'].nil? && site['status'] != 'inactive'
    end

    def perform_request
      uri = URI(URL)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{apikey}"
      request['User-Agent'] = UserAgent.current

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
    rescue StandardError => e
      raise RequestFailed, "cannot connect to #{URL} - #{e.message}"
    end

    # The API explains a rejected request in the `detail` field.
    def detail(response)
      JSON.parse(response.body)['detail']
    rescue StandardError
      nil
    end

    def report_single_site(site)
      puts "Found one pvnode site: #{describe(site)}"
      site['id']
    end

    # An account without any site belongs to a user of the v1 API, so the
    # collector reports nothing and lets the caller fall back. An account whose
    # sites are all unusable belongs to a user of the v2 API, who must act.
    def report_no_usable_site(sites)
      if sites.empty?
        puts 'Your pvnode account has no site yet. ' \
             'Create one at https://www.pvnode.com to use the pvnode v2 API.'
        return nil
      end

      raise SelectionRequired,
            'Your pvnode account has no active site. ' \
            'Activate one at https://www.pvnode.com to use the pvnode v2 API.'
    end

    def report_multiple_sites(sites)
      list = sites.map { |site| "\n  #{describe(site)}" }.join

      raise SelectionRequired,
            "Your pvnode account has #{sites.length} active sites. " \
            "Set PVNODE_SITE_ID to one of them:#{list}"
    end

    # The name is a required field of a site, so it needs no fallback.
    def describe(site)
      "#{site['name']} (#{site['id']})"
    end
  end
end
