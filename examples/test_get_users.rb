#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates how to connect to a ZK device and retrieve users
# using the rbzk gem

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rbzk'

# Configuration - replace with your device's IP address
ZK_IP = '192.168.100.201'  # Device IP address
ZK_PORT = 4370           # Default port, change if needed
ZK_TIMEOUT = 30          # Connection timeout in seconds
ZK_PASSWORD = 0          # Device password, 0 means no password

# Create a new ZK instance (exactly like Python implementation)
zk = RBZK::ZK.new(
  ZK_IP,
  port: ZK_PORT,
  timeout: 5,        # Use a shorter timeout like Python (5 seconds)
  password: ZK_PASSWORD,
  verbose: true,     # Set to true for detailed logging
  omit_ping: true,   # Skip ping check (like Python implementation)
  force_udp: false,  # Use TCP (like Python implementation)
  encoding: 'UTF-8'  # Use UTF-8 encoding for user names
)

begin
  puts "Connecting to ZKTeco device at #{ZK_IP}:#{ZK_PORT}..."
  puts "Please ensure the device is powered on and connected to the network."

  conn = zk.connect

  if conn.connected?
    puts "✓ Connected successfully!"
  else
    puts "✗ Connection failed!"
    exit 1
  end

  # Disable the device to ensure exclusive access
  puts "\nDisabling device..."
  conn.disable_device
  puts "✓ Device disabled"

  # Get device information
  puts "\nGetting device information..."
  version = conn.get_firmware_version
  puts "✓ Firmware version: #{version}"

  time = conn.get_time
  puts "✓ Device time: #{time}"

  # Get device capacity information
  info = conn.get_free_sizes
  puts "✓ Device capacity:"
  puts "  - Users: #{info[:users]}"
  puts "  - Fingers: #{info[:fingers]}"
  puts "  - Capacity: #{info[:capacity]}"
  puts "  - Logs: #{info[:logs]}"
  puts "  - Passwords: #{info[:passwords]}"

  # Get users
  puts "\nGetting users..."
  users = conn.get_users
  if users && !users.empty?
    puts "✓ Found #{users.size} users:"
    users.each do |user|
      privilege = 'User'
      privilege = 'Admin' if user.privilege == RBZK::Constants::USER_ADMIN

      puts "  - UID: #{user.uid}"
      puts "    Name: #{user.name}"
      puts "    Privilege: #{privilege}"
      puts "    User ID: #{user.user_id}"
      puts "    Group ID: #{user.group_id}"
      puts "    Password: #{user.password ? '[SET]' : '[NONE]'}"
      puts "    Card: #{user.card}"
      puts "    ---"
    end
  else
    puts "✓ No users found"
  end

  # Test the device voice
  puts "\nTesting device voice..."
  conn.test_voice
  puts "✓ Voice test completed"

  # Re-enable the device when done
  puts "\nEnabling device..."
  conn.enable_device
  puts "✓ Device enabled"

rescue RBZK::ZKNetworkError => e
  puts "\n✗ Network Error: #{e.message}"
  puts "Please check that the device is powered on and connected to the network."
  puts "Also verify that the IP address and port are correct."
  puts e.backtrace.join("\n") if zk.instance_variable_get(:@verbose)
rescue RBZK::ZKErrorResponse => e
  puts "\n✗ Device Error: #{e.message}"
  puts "The device returned an error response. This might be due to:"
  puts "- Incorrect password"
  puts "- Device is busy or in an error state"
  puts "- Command not supported by this device model"
  puts e.backtrace.join("\n") if zk.instance_variable_get(:@verbose)
rescue => e
  puts "\n✗ Unexpected Error: #{e.message}"
  puts "An unexpected error occurred while communicating with the device."
  puts e.backtrace.join("\n") if zk.instance_variable_get(:@verbose)
ensure
  # Always disconnect when done
  if conn && conn.connected?
    puts "\nDisconnecting from device..."
    conn.disconnect
    puts "✓ Disconnected"
  end
end

puts "\nTest completed!"
