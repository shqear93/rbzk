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

  # Get attendance logs
  puts 'Fetching attendance logs...'
  logs = zk.get_attendance_logs
  puts "Found #{logs.size} log(s)."

  # Display the logs
  if logs.empty?
    puts 'No attendance logs to display.'
  else
    puts '--- Attendance Logs ---'
    logs.each_with_index do |log, index|
      puts log.inspect
      puts "Log ##{index + 1}:"
      puts "  User ID:   #{log.user_id}"
      puts "  Timestamp: #{log.timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
      puts "  Status:    #{log.status}"
      puts "  Punch:     #{log.punch}"
      puts '-------------------------'
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
