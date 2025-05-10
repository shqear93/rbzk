#!/usr/bin/env ruby
# frozen_string_literal: true

# This example shows how to use the RBZK gem in a real project
# It demonstrates all the main functionality of the gem

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rbzk'

# Configuration
ZK_IP = '192.168.1.201'  # Replace with your device IP
ZK_PORT = 4370           # Default port, change if needed
ZK_TIMEOUT = 60          # Connection timeout in seconds
ZK_PASSWORD = 0          # Device password, 0 means no password

# Create a new ZK instance with verbose output
zk = RBZK::ZK.new(
  ZK_IP,
  port: ZK_PORT,
  timeout: ZK_TIMEOUT,
  password: ZK_PASSWORD,
  verbose: true
)

begin
  puts "Connecting to device at #{ZK_IP}:#{ZK_PORT}..."
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
  
  # Get firmware version
  puts "\nGetting firmware version..."
  version = conn.get_firmware_version
  puts "✓ Firmware version: #{version}"
  
  # Get device time
  puts "\nGetting device time..."
  time = conn.get_time
  puts "✓ Device time: #{time}"
  
  # Set device time to current time
  puts "\nSetting device time to current time..."
  conn.set_time
  puts "✓ Device time set to current time"
  
  # Get device info
  puts "\nGetting device info..."
  info = conn.get_free_sizes
  if info
    puts "✓ Device info:"
    puts "  - Users: #{info[:users]}"
    puts "  - Fingers: #{info[:fingers]}"
    puts "  - Capacity: #{info[:capacity]}"
    puts "  - Logs: #{info[:logs]}"
    puts "  - Passwords: #{info[:passwords]}"
  else
    puts "✗ Failed to get device info"
  end
  
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
  
  # Get attendance logs
  puts "\nGetting attendance logs..."
  logs = conn.get_attendance_logs
  if logs && !logs.empty?
    puts "✓ Found #{logs.size} attendance logs:"
    logs.first(5).each do |log|
      puts "  - User ID: #{log.user_id}"
      puts "    Timestamp: #{log.timestamp}"
      puts "    Status: #{log.status}"
      puts "    Punch: #{log.punch}"
      puts "    UID: #{log.uid}"
      puts "    ---"
    end
    
    if logs.size > 5
      puts "  ... and #{logs.size - 5} more logs"
    end
  else
    puts "✓ No attendance logs found"
  end
  
  # Get fingerprint templates
  puts "\nGetting fingerprint templates..."
  templates = conn.get_templates
  if templates && !templates.empty?
    puts "✓ Found #{templates.size} fingerprint templates:"
    templates.first(5).each do |template|
      puts "  - UID: #{template.uid}"
      puts "    Finger ID: #{template.fid}"
      puts "    Valid: #{template.valid == 1 ? 'Yes' : 'No'}"
      puts "    Template size: #{template.template.size} bytes"
      puts "    ---"
    end
    
    if templates.size > 5
      puts "  ... and #{templates.size - 5} more templates"
    end
  else
    puts "✓ No fingerprint templates found"
  end
  
  # Test the device voice
  puts "\nTesting device voice..."
  conn.test_voice
  puts "✓ Voice test completed"
  
  # Re-enable the device when done
  puts "\nEnabling device..."
  conn.enable_device
  puts "✓ Device enabled"
  
  # Disconnect from the device
  puts "\nDisconnecting from device..."
  conn.disconnect
  puts "✓ Disconnected successfully"
  
rescue => e
  puts "\n✗ Error: #{e.message}"
  puts e.backtrace.join("\n")
ensure
  # Always try to disconnect and re-enable the device when done
  begin
    if conn && conn.connected?
      conn.enable_device
      conn.disconnect
      puts "✓ Device enabled and disconnected in ensure block"
    end
  rescue => e
    puts "✗ Error in ensure block: #{e.message}"
  end
end
