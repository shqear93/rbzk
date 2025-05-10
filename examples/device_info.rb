#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rbzk'

# Create a new ZK instance
zk = RBZK::ZK.new('192.168.1.201', port: 4370)

begin
  # Connect to the device
  conn = zk.connect

  # Get firmware version
  version = conn.get_firmware_version
  puts "Firmware version: #{version}"

  # Get device time
  time = conn.get_time
  puts "Device time: #{time}"

  # Set device time to current time
  conn.set_time
  puts "Device time set to current time"

  # Get device info
  info = conn.get_free_sizes
  puts "Users: #{info[:users]}"
  puts "Fingers: #{info[:fingers]}"
  puts "Capacity: #{info[:capacity]}"
  puts "Logs: #{info[:logs]}"
  puts "Passwords: #{info[:passwords]}"

rescue => e
  puts "Error: #{e.message}"
ensure
  # Always disconnect when done
  conn.disconnect if conn
end
