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

  puts '--- Get Attendance Logs ---'
  logs = conn.get_attendance_logs
  logs.each do |log|
    puts "User ID: #{log.user_id}"
    puts "Timestamp: #{log.timestamp}"
    puts "Status: #{log.status}"
    puts "Punch: #{log.punch}"
    puts "UID: #{log.uid}"
    puts "---"
  end

  # Re-enable the device when done
  puts 'Enabling device...'
  conn.enable_device
rescue => e
  puts "Error: #{e.message}"
ensure
  # Always disconnect when done
  conn.disconnect if conn
end
