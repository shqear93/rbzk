# frozen_string_literal: true

RSpec.describe RBZK::CLI::Config do
  let(:config_file) { File.join(Dir.pwd, '.rbzk_test.yml') }
  let(:config) { RBZK::CLI::Config.new(config_file) }

  after do
    # Clean up test config file
    FileUtils.rm_f(config_file)
  end

  describe '#initialize' do
    it 'loads default configuration if file does not exist' do
      expect(config['ip']).to eq('192.168.100.201')
      expect(config['port']).to eq(4370)
      expect(config['timeout']).to eq(30)
      expect(config['password']).to eq(0)
      expect(config['verbose']).to eq(false)
      expect(config['force_udp']).to eq(false)
      expect(config['no_ping']).to eq(true)
      expect(config['encoding']).to eq('UTF-8')
    end

    it 'loads configuration from file if it exists' do
      # Create a test config file
      File.open(config_file, 'w') do |f|
        f.write(YAML.dump({
                            'ip' => '192.168.1.100',
                            'port' => 4371
                          }))
      end

      # Create a new config object
      config = RBZK::CLI::Config.new(config_file)

      # Check that values from file are loaded
      expect(config['ip']).to eq('192.168.1.100')
      expect(config['port']).to eq(4371)

      # Check that default values are still used for missing keys
      expect(config['timeout']).to eq(30)
    end
  end

  describe '#[]' do
    it 'returns the value for the given key' do
      expect(config['ip']).to eq('192.168.100.201')
    end

    it 'returns the value for the given symbol key' do
      expect(config[:ip]).to eq('192.168.100.201')
    end

    it 'returns nil for unknown keys' do
      expect(config['unknown']).to be_nil
    end
  end

  describe '#[]=' do
    it 'sets the value for the given key' do
      config['ip'] = '192.168.1.100'
      expect(config['ip']).to eq('192.168.1.100')
    end

    it 'sets the value for the given symbol key' do
      config[:ip] = '192.168.1.100'
      expect(config['ip']).to eq('192.168.1.100')
    end
  end

  describe '#save' do
    it 'saves the configuration to the file' do
      config['ip'] = '192.168.1.100'
      config.save

      # Check that the file was created
      expect(File.exist?(config_file)).to be true

      # Check that the file contains the correct values
      saved_config = YAML.load_file(config_file)
      expect(saved_config['ip']).to eq('192.168.1.100')
    end

    it 'creates the directory if it does not exist' do
      # Use a config file in a non-existent directory
      dir = File.join(Dir.pwd, 'test_config_dir')
      file = File.join(dir, 'config.yml')
      config = RBZK::CLI::Config.new(file)

      # Save the configuration
      config.save

      # Check that the directory was created
      expect(Dir.exist?(dir)).to be true

      # Clean up
      FileUtils.rm_rf(dir)
    end
  end

  describe '#to_h' do
    it 'returns a hash of all configuration values' do
      config['ip'] = '192.168.1.100'
      hash = config.to_h

      expect(hash).to be_a(Hash)
      expect(hash['ip']).to eq('192.168.1.100')
      expect(hash['port']).to eq(4370)
    end

    it 'returns a copy of the configuration' do
      hash = config.to_h
      hash['ip'] = '192.168.1.100'

      expect(config['ip']).to eq('192.168.100.201')
    end
  end
end
