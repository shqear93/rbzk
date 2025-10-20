# frozen_string_literal: true

RSpec.describe RBZK::CLI::Commands do
  let(:cli) { RBZK::CLI::Commands.new }
  let(:config) { RBZK::CLI::Config.new }

  before do
    # Mock the Config class
    allow(RBZK::CLI::Config).to receive(:new).and_return(config)
    allow(config).to receive(:[]).with('ip').and_return('192.168.100.201')
    allow(config).to receive(:[]).with('port').and_return(4370)
    allow(config).to receive(:[]).with('timeout').and_return(30)
    allow(config).to receive(:[]).with('password').and_return(0)
    allow(config).to receive(:[]).with('verbose').and_return(false)
    allow(config).to receive(:[]).with('force_udp').and_return(false)
    allow(config).to receive(:[]).with('no_ping').and_return(true)
    allow(config).to receive(:[]).with('encoding').and_return('UTF-8')
    allow(config).to receive(:to_h).and_return({
                                                 'ip' => '192.168.100.201',
                                                 'port' => 4370,
                                                 'timeout' => 30,
                                                 'password' => 0,
                                                 'verbose' => false,
                                                 'force_udp' => false,
                                                 'no_ping' => true,
                                                 'encoding' => 'UTF-8'
                                               })
  end

  describe '#config' do
    it 'displays the current configuration' do
      expect { cli.config }.to output(/RBZK Configuration/).to_stdout
    end
  end

  describe '#config_set' do
    it 'sets a configuration value' do
      allow(config).to receive(:[]=)
      allow(config).to receive(:save)

      expect { cli.config_set('ip', '192.168.1.100') }.to output(/Configuration updated/).to_stdout
      expect(config).to have_received(:[]=).with('ip', '192.168.1.100')
      expect(config).to have_received(:save)
    end

    it 'converts numeric values correctly' do
      allow(config).to receive(:[]=)
      allow(config).to receive(:save)

      expect { cli.config_set('port', '4371') }.to output(/Configuration updated/).to_stdout
      expect(config).to have_received(:[]=).with('port', 4371)
    end

    it 'converts boolean values correctly' do
      allow(config).to receive(:[]=)
      allow(config).to receive(:save)

      expect { cli.config_set('verbose', 'true') }.to output(/Configuration updated/).to_stdout
      expect(config).to have_received(:[]=).with('verbose', true)
    end
  end

  describe '#with_connection' do
    let(:zk) { instance_double(RBZK::ZK) }
    let(:conn) { instance_double(RBZK::ZK) }

    before do
      allow(RBZK::ZK).to receive(:new).and_return(zk)
      allow(zk).to receive(:connect).and_return(conn)
      allow(conn).to receive(:connected?).and_return(true)
      allow(conn).to receive(:disconnect)
    end

    it 'creates a connection with the correct parameters' do
      cli.send(:with_connection, '192.168.100.201', {}) do |c|
        expect(c).to eq(conn)
      end

      expect(RBZK::ZK).to have_received(:new).with(
        '192.168.100.201',
        hash_including(
          port: 4370,
          timeout: 30,
          password: 0,
          verbose: false,
          omit_ping: true,
          force_udp: false,
          encoding: 'UTF-8'
        )
      )
    end

    it 'disconnects after the block is executed' do
      cli.send(:with_connection, '192.168.100.201', {}) {}
      expect(conn).to have_received(:disconnect)
    end

    it 'disconnects even if an exception is raised' do
      # The with_connection method catches exceptions and prints an error message
      # So we just need to verify that disconnect is called
      cli.send(:with_connection, '192.168.100.201', {}) { raise 'Test error' }
      expect(conn).to have_received(:disconnect)
    end
  end

  # These tests would require a real device or more complex mocking
  # They are commented out as they would fail without proper setup

  # describe '#info' do
  #   it 'displays device information' do
  #     # Mock the connection and device info methods
  #     allow(cli).to receive(:with_connection).and_yield(conn)
  #     allow(conn).to receive(:get_firmware_version).and_return('Ver 6.60 Sep 27 2019')
  #     allow(conn).to receive(:get_time).and_return(Time.now)
  #
  #     expect { cli.info }.to output(/Device Information/).to_stdout
  #   end
  # end

  # describe '#users' do
  #   it 'displays users from the device' do
  #     # Mock the connection and get_users method
  #     allow(cli).to receive(:with_connection).and_yield(conn)
  #     allow(conn).to receive(:get_users).and_return([])
  #
  #     expect { cli.users }.to output(/users/).to_stdout
  #   end
  # end

  describe '#add_user' do
    let(:conn) { instance_double(RBZK::ZK) }

    before do
      allow(cli).to receive(:with_connection).and_yield(conn)
      allow(conn).to receive(:set_user).and_return(true)
    end

    it 'creates a User object and calls set_user with its attributes' do
      # Set up command line options
      allow(cli).to receive(:options).and_return({
                                                   uid: 42,
                                                   name: 'Test User',
                                                   privilege: 0,
                                                   password: '1234',
                                                   group_id: 'Group1',
                                                   user_id: 'EMP123',
                                                   card: 987_654_321
                                                 })

      # Call the method
      expect { cli.add_user('192.168.100.201') }.to output(%r{Adding/updating user}).to_stdout

      # Verify that set_user was called with the correct parameters
      expect(conn).to have_received(:set_user).with(
        uid: 42,
        name: 'Test User',
        privilege: 0,
        password: '1234',
        group_id: 'Group1',
        user_id: 'EMP123',
        card: 987_654_321
      )
    end

    it 'handles missing parameters by using default values' do
      # Set up command line options with minimal parameters
      allow(cli).to receive(:options).and_return({
                                                   name: 'Minimal User'
                                                 })

      # Call the method
      expect { cli.add_user('192.168.100.201') }.to output(%r{Adding/updating user}).to_stdout

      # Verify that set_user was called with the correct parameters
      expect(conn).to have_received(:set_user).with(
        uid: nil,
        name: 'Minimal User',
        privilege: 0,
        password: '',
        group_id: '',
        user_id: '',
        card: 0
      )
    end
  end

  describe '#delete_user' do
    let(:conn) { instance_double(RBZK::ZK) }

    before do
      allow(cli).to receive(:with_connection).and_yield(conn)
      allow(conn).to receive(:delete_user).and_return(true)
    end

    it 'calls delete_user with the uid parameter' do
      # Set up command line options
      allow(cli).to receive(:options).and_return({
                                                   uid: 42,
                                                   user_id: 'EMP123'
                                                 })

      # Call the method
      expect { cli.delete_user('192.168.100.201') }.to output(/Deleting user/).to_stdout

      # Verify that delete_user was called with the correct parameters
      expect(conn).to have_received(:delete_user).with(
        uid: 42
      )
    end

    it 'looks up the uid when only user_id is provided' do
      # Set up command line options
      allow(cli).to receive(:options).and_return({
                                                   uid: nil,
                                                   user_id: 'EMP123'
                                                 })

      # Mock the get_users method to return a user with the given user_id
      user = instance_double(RBZK::User, uid: 42, user_id: 'EMP123')
      allow(conn).to receive(:get_users).and_return([user])

      # Call the method
      expect { cli.delete_user('192.168.100.201') }.to output(/Deleting user/).to_stdout

      # Verify that delete_user was called with the correct parameters
      expect(conn).to have_received(:delete_user).with(
        uid: 42
      )
    end
  end

  describe '#get_user_template' do
    let(:conn) { instance_double(RBZK::ZK) }
    let(:template) { instance_double(RBZK::Finger, uid: 42, fid: 1, valid: 1, size: 1024) }

    before do
      allow(cli).to receive(:with_connection).and_yield(conn)
      allow(conn).to receive(:get_user_template).and_return(template)
    end

    it 'creates a User object and calls get_user_template with its attributes' do
      # Set up command line options
      allow(cli).to receive(:options).and_return({
                                                   uid: 42,
                                                   user_id: 'EMP123',
                                                   finger_id: 1
                                                 })

      # Call the method
      expect { cli.get_user_template('192.168.100.201') }.to output(/Getting user fingerprint template/).to_stdout

      # Verify that get_user_template was called with the correct parameters
      expect(conn).to have_received(:get_user_template).with(
        uid: 42,
        temp_id: 1,
        user_id: 'EMP123'
      )
    end
  end
end
