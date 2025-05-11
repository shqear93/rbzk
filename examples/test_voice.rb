#!/usr/bin/env ruby
# Test voice command for ZKTeco devices
# Usage: ruby test_voice.rb [--ip IP_ADDRESS] [--port PORT] [--index VOICE_INDEX]

require 'optparse'
require_relative '../lib/rbzk'

# Parse command line options
options = {
  ip: '192.168.100.201',
  port: 4370,
  index: 0,
  verbose: true
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby test_voice.rb [options]"

  opts.on("--ip IP", "Device IP address (default: #{options[:ip]})") do |ip|
    options[:ip] = ip
  end

  opts.on("--port PORT", Integer, "Device port (default: #{options[:port]})") do |port|
    options[:port] = port
  end

  opts.on("--index INDEX", Integer, "Voice index to play (default: #{options[:index]})") do |index|
    options[:index] = index
  end

  opts.on("--[no-]verbose", "Run verbosely (default: #{options[:verbose]})") do |v|
    options[:verbose] = v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Voice index descriptions
VOICE_DESCRIPTIONS = {
  0 => "Thank You",
  1 => "Incorrect Password",
  2 => "Access Denied",
  3 => "Invalid ID",
  4 => "Please try again",
  5 => "Duplicate ID",
  6 => "The clock is flow",
  7 => "The clock is full",
  8 => "Duplicate finger",
  9 => "Duplicated punch",
  10 => "Beep kuko",
  11 => "Beep siren",
  12 => "-",
  13 => "Beep bell",
  24 => "Beep standard",
  30 => "Invalid user",
  31 => "Invalid time period",
  32 => "Invalid combination",
  33 => "Illegal Access",
  34 => "Disk space full",
  35 => "Duplicate fingerprint",
  36 => "Fingerprint not registered",
  51 => "Focus eyes on the green box"
}

# Print available voice indexes if no specific index is provided
if ARGV.empty? && options[:index] == 0
  puts "Available voice indexes:"
  VOICE_DESCRIPTIONS.each do |index, description|
    puts "  #{index}: #{description}"
  end
  puts "\nUsage: ruby test_voice.rb --index INDEX"
  puts "Example: ruby test_voice.rb --index 13  # Play 'Beep bell'"
end

# Connect to the device
puts "Connecting to ZKTeco device at #{options[:ip]}:#{options[:port]}..."
conn = RBZK::ZK.new(options[:ip], port: options[:port], verbose: options[:verbose])

begin
  # Connect to the device
  if conn.connect
    puts "✓ Connected successfully!"

    # Disable the device to ensure exclusive access
    puts "\nDisabling device..."
    conn.disable_device
    puts "✓ Device disabled"

    # Test voice
    voice_description = VOICE_DESCRIPTIONS[options[:index]] || "Unknown"
    puts "\nTesting voice #{options[:index]} (#{voice_description})..."

    # Update the test_voice method to accept an index parameter
    result = conn.test_voice(options[:index])

    if result
      puts "✓ Voice command sent successfully"
    else
      puts "✗ Failed to send voice command"
    end
  else
    puts "✗ Connection failed!"
    exit 1
  end
rescue => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace if options[:verbose]
ensure
  # Disconnect from the device
  puts "\nDisconnecting from device..."
  conn.disconnect if conn.connected?
  puts "✓ Disconnected"
end

puts "\nTest completed!"
