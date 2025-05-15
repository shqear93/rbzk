require 'rbzk/cli/commands'

module RBZK
  # Command Line Interface module for RBZK
  # Provides methods for interacting with ZKTeco devices from the command line
  module CLI
    # Start the CLI with the given arguments
    # @param args [Array<String>] Command line arguments
    # @return [Integer] Exit code
    def self.start(args = ARGV)
      Commands.start(args)
    end
  end
end
