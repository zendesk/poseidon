# This file was generated by the `rspec --init` command. Conventionally, all
# specs live under a `spec` directory, which RSpec adds to the `$LOAD_PATH`.
# Require this file using `require "spec_helper"` to ensure that it is only
# loaded once.
#
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'

  config.disable_monkey_patching!
end

POSEIDON_PATH = File.absolute_path(File.dirname(__FILE__) + "/../")

require 'logger'
SPEC_LOGGER = Logger.new(File.join(POSEIDON_PATH, "log", "spec.log"))

require 'simplecov'
SimpleCov.start

require 'poseidon'
include Poseidon
Poseidon.logger = SPEC_LOGGER

require 'coveralls'
Coveralls.wear!

def spec_sleep(time, reason)
  SPEC_LOGGER.info("Sleeping #{time}, reason: #{reason}...")
  sleep time
end
