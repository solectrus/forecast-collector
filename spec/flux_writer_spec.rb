require 'flux_writer'
require 'config'

describe FluxWriter do
  subject(:flux_writer) { described_class.new(config:) }

  let(:config) { Config.from_env }
  let(:now) { Time.utc(2026, 8, 24, 12, 0, 0) }
  let(:write_url) { "#{config.influx_url}/api/v2/write?bucket=my-bucket&org=my-org&precision=s" }
  let(:ping_url) { "#{config.influx_url}/ping" }

  before { allow(Time).to receive(:now).and_return(now) }

  def future = now.to_i + 3600

  def past = now.to_i - 3600

  describe '#push' do
    it 'writes scalar values as a watt field' do
      stub = stub_request(:post, write_url).with(body: "my-forecast watt=100i #{future}")

      flux_writer.push(future => 100)

      expect(stub).to have_been_requested
    end

    it 'writes hash values as one field each' do
      stub = stub_request(:post, write_url)
             .with(body: "my-forecast temp=20.5,watt=100i,watt_clearsky=120i #{future}")

      flux_writer.push(future => { watt: 100, watt_clearsky: 120, temp: 20.5 })

      expect(stub).to have_been_requested
    end

    it 'skips timestamps in the past' do
      stub = stub_request(:post, write_url).with(body: "my-forecast watt=100i #{future}")

      flux_writer.push(past => 50, future => 100)

      expect(stub).to have_been_requested
    end

    it 'writes nothing when every timestamp is in the past' do
      stub = stub_request(:post, write_url)

      flux_writer.push(past => 50)

      expect(stub).not_to have_been_requested
    end

    it 'writes nothing without data' do
      stub = stub_request(:post, write_url)

      flux_writer.push(nil)

      expect(stub).not_to have_been_requested
    end
  end

  describe '#ready?' do
    it 'is true when InfluxDB answers the ping' do
      stub_request(:get, ping_url).to_return(status: 204)

      expect(flux_writer).to be_ready
    end

    it 'is false when InfluxDB does not answer the ping' do
      stub_request(:get, ping_url).to_return(status: 500)

      expect(flux_writer).not_to be_ready
    end
  end
end
