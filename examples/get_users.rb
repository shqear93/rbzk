#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rbzk'

# Create a new ZK instance
zk = RBZK::ZK.new('192.168.1.201', port: 4370)

begin
  # Connect to the device
  conn = zk.connect
  
  # Disable the device to ensure exclusive access
  puts 'Disabling device...'
  conn.disable_device
  
  puts '--- Get Users ---'
  users = conn.get_users
  users.each do |user|
    privilege = 'User'
    privilege = 'Admin' if user.privilege == RBZK::Constants::USER_ADMIN
    
    puts "UID: #{user.uid}"
    puts "Name: #{user.name}"
    puts "Privilege: #{privilege}"
    puts "Password: #{user.password}"
    puts "Group ID: #{user.group_id}"
    puts "User ID: #{user.user_id}"
    puts "---"
  end
  
  # Test the device voice
  puts "Testing voice..."
  conn.test_voice
  
  # Re-enable the device when done
  puts 'Enabling device...'
  conn.enable_device
rescue => e
  puts "Error: #{e.message}"
ensure
  # Always disconnect when done
  conn.disconnect if conn
end
