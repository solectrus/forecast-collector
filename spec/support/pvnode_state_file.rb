require 'tmpdir'

# The pvnode v2 adapter stores its schedule in a file in the temporary
# directory. Each example gets its own directory, so no example can see the
# state of another one.
RSpec.configure do |config|
  config.around do |example|
    Dir.mktmpdir('forecast-collector-spec') do |dir|
      ClimateControl.modify(TMPDIR: dir) { example.run }
    end
  end
end
