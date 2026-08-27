require 'json'

module Pvnode
  # A failed response of the pvnode API, turned into a message for the user.
  #
  # The API explains every rejection in the `detail` field of the body. The
  # collector reports that text instead of guessing from the status code alone,
  # because pvnode can reword a reason or add a new one.
  class ResponseError
    # Raised when the API rejects the request because of one field group that
    # the plan of the user does not include. This is a signal, not a fault: the
    # collector drops the group and asks again without it.
    class GroupRejected < StandardError
      alias group message
    end

    # Status codes that only the user can fix. A request that repeats such an
    # error never succeeds, so the collector stops and says what to do.
    #
    # A 403 has three meanings: the plan has no access to the forecast API, the
    # site is inactive after a downgrade, or the request asked for a field
    # group of a higher plan. Only the third one is a retry, and #rejected_group
    # finds it. The `detail` text names the real reason in every case.
    #
    # See https://pvnode.com/docs/v2/integrations/build-your-own
    ADVICE = {
      '401' => 'Set PVNODE_APIKEY to a valid key from https://www.pvnode.com',
      '403' => 'Check your plan and your sites at https://www.pvnode.com',
      '404' => 'Set PVNODE_SITE_ID to an existing site of your pvnode account, ' \
               'or unset it to use the only site of the account',
    }.freeze
    private_constant :ADVICE

    def initialize(http_response)
      @http_response = http_response
    end

    # True if the user must act. Every other error is temporary: an exhausted
    # quota (429) or a fault of the server (5xx) passes on its own.
    def fatal?
      ADVICE.key?(code)
    end

    # What the user must do, nil if there is nothing to do.
    def advice
      ADVICE[code]
    end

    # The field group the API rejected, nil if the error is about something
    # else. Today only `variability` is bound to a plan, and the collector does
    # not request it. But pvnode can move a group to a higher plan at any time,
    # and then a client that treats every 403 as fatal stops for good.
    #
    # @param candidates [Array<String>] groups the collector can drop
    def rejected_group(candidates)
      return unless code == '403'

      candidates.find { |group| detail.to_s.include?(group) }
    end

    def to_s
      "HTTP #{code} #{http_response.message}#{detail_message}"
    end

    private

    attr_reader :http_response

    def code
      http_response.code
    end

    def detail_message
      detail ? " - #{detail}" : ''
    end

    # A response of a proxy carries no JSON body, and an unknown error of the
    # API can carry a body without the field.
    def detail
      JSON.parse(http_response.body)['detail']
    rescue StandardError
      nil
    end
  end
end
