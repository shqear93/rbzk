#!/usr/bin/env ruby

require 'rbzk'

# --- Configuration ---
DEVICE_IP = '127.0.0.1' # Replace with your device's IP address
DEVICE_PORT = 4370 # Default port, change if necessary

# --- Main Logic ---
begin
  # Create a new ZK instance and connect to the device
  zk = RBZK::ZK.new(DEVICE_IP, port: DEVICE_PORT)
  puts "Connecting to device at #{DEVICE_IP}:#{DEVICE_PORT}..."
  zk.connect
  puts 'Connected successfully!'

  # Get users
  puts 'Fetching users...'
  users = zk.get_users
  puts "Found #{users.size} user(s)."

  # Display the users
  if users.empty?
    puts 'No users found on the device.'
  else
    puts '--- User List ---'
    users.each_with_index do |user, index|
      puts user.inspect
      puts "User ##{index + 1}:"
      puts "  UID:       #{user.uid}"        # Device-generated ID
      puts "  User ID:   #{user.user_id}"    # Your custom ID (PIN2)
      puts "  Name:      #{user.name}"
      puts "  Privilege: #{user.privilege}"
      puts '---------------------'
    end
  end
rescue RBZK::ZKNetworkError => e
  puts 'Error: Could not connect to the device. Please check the IP address and port.'
  puts "Details: #{e.message}"
rescue StandardError => e
  puts "An unexpected error occurred: #{e.message}"
  puts "Backtrace: #{e.backtrace.join("\n")}"
ensure
  # Always ensure the connection is disconnected
  if zk&.connected?
    zk.disconnect
    puts 'Disconnected from device.'
  end
end
