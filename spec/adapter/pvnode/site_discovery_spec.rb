require 'adapter/pvnode/site_discovery'

describe Pvnode::SiteDiscovery do
  subject(:discovery) { described_class.new(apikey: ENV.fetch('PVNODE_APIKEY', nil)) }

  describe '#site_id' do
    context 'without any site' do
      it 'returns nil and explains how to create a site' do
        stdout, = capture_output do
          VCR.use_cassette('pvnode_v2_sites_empty') { expect(discovery.site_id).to be_nil }
        end

        expect(stdout).to include('Your pvnode account has no site yet')
      end
    end

    context 'with exactly one site' do
      it 'returns the id of that site' do
        stdout, = capture_output do
          VCR.use_cassette('pvnode_v2_sites_one') { expect(discovery.site_id).to match(/\Asite_/) }
        end

        expect(stdout).to include('Found one pvnode site: Dummy 1 (site_')
      end
    end

    context 'with a site that is pending deletion' do
      it 'raises, because only the user can activate a site' do
        VCR.use_cassette('pvnode_v2_sites_deleted') do
          expect { discovery.site_id }.to raise_error(
            described_class::SelectionRequired, /has no active site/,
          )
        end
      end
    end

    # The position of both sites is replaced by neutral values by hand. The
    # recording comes from an account with a real plant, and a cassette is part
    # of the public repository. The specs do not read these fields.
    context 'with multiple active sites' do
      it 'raises and lists the sites, because only the user can select one' do
        VCR.use_cassette('pvnode_v2_sites_many') do
          expect { discovery.site_id }.to raise_error(
            described_class::SelectionRequired,
            /has 2 active sites.+one of them:\n  W15-Test \(site_.+\n  Dummy 2 \(site_/m,
          )
        end
      end
    end

    # Derived from the cassette above by hand: the status of the second site is
    # set to `inactive`. The API documentation lists the value, but neither the
    # web app nor the API can produce it, because the endpoints that manage a
    # site need a plan with Sites API access.
    context 'with an inactive site' do
      it 'ignores it and uses the active site' do
        stdout, = capture_output do
          VCR.use_cassette('pvnode_v2_sites_inactive') do
            expect(discovery.site_id).to match(/\Asite_/)
          end
        end

        expect(stdout).to include('Found one pvnode site: W15-Test (site_')
      end
    end

    context 'when the API rejects the API key' do
      subject(:discovery) { described_class.new(apikey: 'invalid-api-key') }

      it 'raises, so the caller cannot mistake it for an account without a site' do
        VCR.use_cassette('pvnode_v2_sites_unauthorized') do
          expect { discovery.site_id }.to raise_error(described_class::RequestFailed) do |error|
            expect(error.message).to include('HTTP 401')
            expect(error.advice).to include('Set PVNODE_APIKEY')
          end
        end
      end
    end

    context 'when the request cannot be sent' do
      before { stub_request(:get, 'https://api.pvnode.com/v2/sites/').to_timeout }

      it 'raises without advice, because only the user knows the cause' do
        expect { discovery.site_id }.to raise_error(described_class::RequestFailed) do |error|
          expect(error.message).to include('cannot connect')
          expect(error.advice).to be_nil
        end
      end
    end

    context 'when a proxy answers instead of the API' do
      before do
        stub_request(:get, 'https://api.pvnode.com/v2/sites/').to_return(
          status: 200,
          headers: { 'Content-Type' => 'text/html' },
          body: '<html>Gateway timeout</html>',
        )
      end

      it 'raises' do
        expect { discovery.site_id }.to raise_error(
          described_class::RequestFailed, /unexpected response/,
        )
      end
    end

    context 'without an API key' do
      subject(:discovery) { described_class.new(apikey: nil) }

      it 'returns nil without a request' do
        expect(discovery.site_id).to be_nil
        expect(a_request(:get, 'https://api.pvnode.com/v2/sites/')).not_to have_been_made
      end
    end
  end
end
