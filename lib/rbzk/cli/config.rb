require 'yaml'
require 'fileutils'

module RBZK
  module CLI
    # Configuration handler for the CLI
    class Config
      # Default configuration values
      DEFAULT_CONFIG = {
        'ip' => '192.168.100.201',
        'port' => 4370,
        'timeout' => 30,
        'password' => 0,
        'verbose' => false,
        'force_udp' => false,
        'no_ping' => true,
        'encoding' => 'UTF-8'
      }.freeze

      # Initialize a new configuration
      # @param config_file [String] Path to the configuration file
      def initialize(config_file = nil)
        @config_file = config_file || default_config_file
        @config = load_config
      end

      # Get a configuration value
      # @param key [String, Symbol] Configuration key
      # @return [Object] Configuration value
      def [](key)
        @config[key.to_s]
      end

      # Set a configuration value
      # @param key [String, Symbol] Configuration key
      # @param value [Object] Configuration value
      def []=(key, value)
        @config[key.to_s] = value
      end

      # Save the configuration to the file
      def save
        # Create the directory if it doesn't exist
        FileUtils.mkdir_p(File.dirname(@config_file))

        # Save the configuration
        File.open(@config_file, 'w') do |f|
          f.write(YAML.dump(@config))
        end
      end

      # Get the default configuration file path
      # @return [String] Default configuration file path
      def default_config_file
        if ENV['XDG_CONFIG_HOME']
          File.join(ENV['XDG_CONFIG_HOME'], 'rbzk', 'config.yml')
        elsif ENV['HOME']
          File.join(ENV['HOME'], '.config', 'rbzk', 'config.yml')
        else
          File.join(Dir.pwd, '.rbzk.yml')
        end
      end

      # Load the configuration from the file
      # @return [Hash] Configuration values
      def load_config
        if File.exist?(@config_file)
          begin
            config = YAML.load_file(@config_file)
            return DEFAULT_CONFIG.merge(config) if config.is_a?(Hash)
          rescue StandardError => e
            warn "Error loading configuration file: #{e.message}"
          end
        end
        DEFAULT_CONFIG.dup
      end

      # Get all configuration values
      # @return [Hash] All configuration values
      def to_h
        @config.dup
      end
    end
  end
end
