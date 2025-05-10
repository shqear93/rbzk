# frozen_string_literal: true

RSpec.describe "Getting users from ZK device" do
  # Configuration for the test
  let(:ip) { '192.168.100.201' }  # Device IP address
  let(:port) { 4370 }
  let(:timeout) { 30 }
  let(:password) { 0 }
  let(:zk) { RBZK::ZK.new(ip, port: port, timeout: timeout, password: password) }
  let(:conn) { zk.connect }

  # Mock user data for testing
  let(:mock_users) do
    [
      RBZK::User.new(1, "101", "John Doe", RBZK::Constants::USER_DEFAULT, "", 0, 0),
      RBZK::User.new(2, "102", "Jane Smith", RBZK::Constants::USER_ADMIN, "password", 0, 0),
      RBZK::User.new(3, "103", "Bob Johnson", RBZK::Constants::USER_ENROLLER, "", 1, 12345)
    ]
  end

  # This context uses mocks to test the functionality without a real device
  context "with mocked connection" do
    before do
      # Mock the connection process
      allow(zk).to receive(:ping).and_return(true)
      allow(zk).to receive(:send_command)
      allow(zk).to receive(:recv_reply).and_return("OK")
      allow(zk).to receive(:recv_long).and_return(84)  # 3 users * 28 bytes

      # Create mock user data binary string (simplified)
      mock_data = ""
      mock_users.each do |user|
        # Simulate the binary data format from the device
        user_data = [
          user.uid,
          user.user_id.ljust(9, "\x00"),
          user.name.ljust(24, "\x00"),
          user.privilege,
          user.password.ljust(1, "\x00"),
          user.group_id,
          user.card
        ].pack('S<A9A24CCA14S<')
        mock_data += user_data
      end

      allow(zk).to receive(:recv_chunk).and_return(mock_data)

      # Set connected state
      zk.instance_variable_set(:@connected, true)
    end

    it "connects to the device successfully" do
      expect(conn).to eq(zk)
      expect(conn.connected?).to be true
    end

    it "retrieves users from the device" do
      users = conn.get_users

      expect(users).to be_an(Array)
      expect(users.size).to eq(3)

      # Check first user details
      expect(users[0].uid).to eq(1)
      expect(users[0].user_id).to eq("101")
      expect(users[0].name).to eq("John Doe")
      expect(users[0].privilege).to eq(RBZK::Constants::USER_DEFAULT)

      # Check second user details
      expect(users[1].uid).to eq(2)
      expect(users[1].user_id).to eq("102")
      expect(users[1].name).to eq("Jane Smith")
      expect(users[1].privilege).to eq(RBZK::Constants::USER_ADMIN)

      # Check third user details
      expect(users[2].uid).to eq(3)
      expect(users[2].user_id).to eq("103")
      expect(users[2].name).to eq("Bob Johnson")
      expect(users[2].privilege).to eq(RBZK::Constants::USER_ENROLLER)
      expect(users[2].card).to eq(12345)
    end

    it "handles user privileges correctly" do
      users = conn.get_users

      # Check privilege mapping
      expect(users[0].privilege).to eq(RBZK::Constants::USER_DEFAULT)
      expect(users[1].privilege).to eq(RBZK::Constants::USER_ADMIN)
      expect(users[2].privilege).to eq(RBZK::Constants::USER_ENROLLER)

      # Verify privilege constants
      expect(RBZK::Constants::USER_DEFAULT).to eq(0)
      expect(RBZK::Constants::USER_ADMIN).to eq(14)
      expect(RBZK::Constants::USER_ENROLLER).to eq(2)
    end
  end

  # This context is for real device testing (disabled by default)
  context "with real device", skip: "Requires a real ZK device" do
    before do
      # Connect to the real device
      conn.disable_device
    end

    after do
      # Clean up after tests
      conn.enable_device
      conn.disconnect if conn && conn.connected?
    end

    it "connects to the device successfully" do
      expect(conn.connected?).to be true
    end

    it "retrieves users from the device" do
      users = conn.get_users

      expect(users).to be_an(Array)
      puts "Found #{users.size} users on the device"

      # Print user details for debugging
      users.each do |user|
        puts "UID: #{user.uid}, Name: #{user.name}, User ID: #{user.user_id}"
      end

      # Basic validation that we got something
      expect(users).to be_an(Array)
    end

    it "gets device information" do
      version = conn.get_firmware_version
      time = conn.get_time
      info = conn.get_free_sizes

      puts "Firmware version: #{version}"
      puts "Device time: #{time}"
      puts "Device capacity: Users=#{info[:users]}, Fingers=#{info[:fingers]}, Logs=#{info[:logs]}"

      expect(version).not_to be_nil
      expect(time).to be_a(Time)
      expect(info).to be_a(Hash)
      expect(info).to have_key(:users)
    end
  end

  # This context tests error handling
  context "error handling" do
    before do
      allow(zk).to receive(:ping).and_return(false)
    end

    it "raises an error when device is unreachable" do
      expect { zk.connect }.to raise_error(RBZK::ZKNetworkError)
    end
  end

  # This context tests the full workflow with mocks
  context "full workflow" do
    before do
      # Mock the connection process
      allow(zk).to receive(:ping).and_return(true)
      allow(zk).to receive(:send_command)
      allow(zk).to receive(:recv_reply).and_return("OK")
      allow(zk).to receive(:recv_long).and_return(84)  # 3 users * 28 bytes
      allow(zk).to receive(:recv_chunk).and_return("")

      # Set connected state
      zk.instance_variable_set(:@connected, true)
    end

    it "follows the correct workflow for getting users" do
      # Connect
      expect(conn.connected?).to be true

      # Disable device
      expect(conn.disable_device).to be true

      # Get users (empty in this mock)
      users = conn.get_users
      expect(users).to be_an(Array)

      # Enable device
      expect(conn.enable_device).to be true

      # Disconnect
      expect(conn.disconnect).to be true
    end
  end
end
