# Helper method to capture stdout and stderr output
# Returns [stdout, stderr] as array
def capture_output
  original_stdout = $stdout
  original_stderr = $stderr
  $stdout = StringIO.new
  $stderr = StringIO.new

  yield

  [$stdout.string, $stderr.string]
ensure
  $stdout = original_stdout
  $stderr = original_stderr
end
