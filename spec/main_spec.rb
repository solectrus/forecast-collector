require 'loop'

# The entrypoint is a script, not a class.
describe 'app/main.rb' do # rubocop:disable RSpec/DescribeClass
  # The spec loads the script instead of requiring a class. The loop itself is
  # stubbed, because it never returns.
  def run_main(version: nil)
    capture_output do
      ClimateControl.modify(
        FORECAST_PROVIDER: 'forecast.solar',
        BUILDTIME: '2026-08-24T12:00:00Z',
        COMMIT_VERSION: version,
        VERSION: nil,
      ) do
        load File.expand_path('../app/main.rb', __dir__)
      end
    end
  end

  before { allow(Loop).to receive(:start) }

  it 'starts the loop with the configuration of the environment' do
    run_main

    expect(Loop).to have_received(:start).with(config: an_instance_of(Config))
  end

  it 'reports the version and the build time' do
    stdout, stderr = run_main(version: 'v0.10.1-3-g2d8f177')

    expect(stderr).to be_empty
    expect(stdout).to include(
      'Forecast collector for SOLECTRUS',
      'Version v0.10.1-3-g2d8f177',
      'built at 2026-08-24T12:00:00Z',
    )
  end

  it 'reports an unknown version when the build carries none' do
    # A build outside CI has no version.
    stdout, = run_main

    expect(stdout).to include('Version <unknown>')
  end

  it 'reports the provider and the InfluxDB target' do
    stdout, = run_main

    expect(stdout).to include(
      'Pulling from Forecast.Solar every 1 seconds',
      'Pushing to InfluxDB at http://localhost:8086',
      'bucket my-bucket',
      'measurement my-forecast',
    )
  end
end
