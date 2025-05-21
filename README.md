# RBZK

A Ruby implementation of the ZK protocol for fingerprint and biometric attendance devices.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rbzk'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install rbzk
```

## Usage

### Basic Connection

```ruby
require 'rbzk'

# Create a new ZK instance
zk = RBZK::ZK.new('192.168.1.201', port: 4370)

# Connect to the device
begin
  conn = zk.connect

  # Check if connected successfully
  if conn.connected?
    puts "Connected successfully!"
  else
    puts "Connection failed!"
    exit 1
  end

  # Disable the device to ensure exclusive access
  puts 'Disabling device...'
  conn.disable_device

  # Your operations here...

  # Re-enable the device when done
  puts 'Enabling device...'
  conn.enable_device
rescue => e
  puts "Error: #{e.message}"
ensure
  # Always disconnect when done
  conn.disconnect if conn && conn.connected?
end
```

### Getting Users

```ruby
require 'rbzk'

zk = RBZK::ZK.new('192.168.1.201')
begin
  conn = zk.connect
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

  conn.enable_device
rescue => e
  puts "Error: #{e.message}"
ensure
  conn.disconnect if conn && conn.connected?
end
```

### Getting Attendance Logs

```ruby
require 'rbzk'

zk = RBZK::ZK.new('192.168.1.201')
begin
  conn = zk.connect
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

  conn.enable_device
rescue => e
  puts "Error: #{e.message}"
ensure
  conn.disconnect if conn && conn.connected?
end
```

### Device Operations

```ruby
require 'rbzk'

zk = RBZK::ZK.new('192.168.1.201')
begin
  conn = zk.connect

  # Get device time
  time = conn.get_time
  puts "Device time: #{time}"

  # Set device time to current time
  conn.set_time

  # Get device info
  info = conn.get_free_sizes
  puts "Users: #{info[:users]}"
  puts "Fingers: #{info[:fingers]}"
  puts "Capacity: #{info[:capacity]}"
  puts "Logs: #{info[:logs]}"
  puts "Passwords: #{info[:passwords]}"

  # Test the device voice
  conn.test_voice

rescue => e
  puts "Error: #{e.message}"
ensure
  conn.disconnect if conn && conn.connected?
end
```

### Getting Fingerprint Templates

```ruby
require 'rbzk'

zk = RBZK::ZK.new('192.168.1.201')
begin
  conn = zk.connect
  conn.disable_device

  puts '--- Get Fingerprint Templates ---'
  templates = conn.get_templates
  templates.each do |template|
    puts "UID: #{template.uid}"
    puts "Finger ID: #{template.fid}"
    puts "Valid: #{template.valid == 1 ? 'Yes' : 'No'}"
    puts "Template size: #{template.template.size} bytes"
    puts "---"
  end

  # Get a specific user's template
  if templates.any?
    user_template = conn.get_user_template(templates.first.uid, templates.first.fid)
    puts "Got specific template for user #{user_template.uid}, finger #{user_template.fid}"
  end

  conn.enable_device
rescue => e
  puts "Error: #{e.message}"
ensure
  conn.disconnect if conn && conn.connected?
end
```

## Command Line Interface

RBZK provides a powerful command-line interface for interacting with ZKTeco devices. The CLI is built using Thor, which provides a clean, intuitive interface similar to Git and other modern command-line tools.

### Installation

After installing the gem, you can use the `rbzk` command directly:

```bash
# Install the gem
gem install rbzk

# Use the command
bin/rbzk info 192.168.100.201
```

If you're using Bundler, you can run the command through `bundle exec`:

```bash
bundle exec rbzk info 192.168.100.201
```

### Available Commands

```bash
# Get help
bin/rbzk help

# Get help for a specific command
bin/rbzk help logs
```

#### Device Information

```bash
# Get device information
bin/rbzk info 192.168.100.201 [options]
```

#### Users

```bash
# Get users from the device
bin/rbzk users 192.168.100.201 [options]
```

#### Attendance Logs

```bash
# Get all attendance logs
bin/rbzk logs 192.168.100.201 [options]

# Get today's logs
bin/rbzk logs 192.168.100.201 --today [options]

# Get yesterday's logs
bin/rbzk logs 192.168.100.201 --yesterday [options]

# Get this week's logs
bin/rbzk logs 192.168.100.201 --week [options]

# Get this month's logs
bin/rbzk logs 192.168.100.201 --month [options]

# Get logs for a custom date range
bin/rbzk logs 192.168.100.201 --start-date=2023-01-01 --end-date=2023-01-31 [options]
```

#### Clear Logs

```bash
# Clear attendance logs (will prompt for confirmation)
bin/rbzk clear_logs 192.168.100.201 [options]
```

#### Test Voice

```bash
# Test the device voice
bin/rbzk test_voice 192.168.100.201 [options]
```

### Global Options

These options can be used with any command:

```
--ip=IP                    # Device IP address (default: from config or 192.168.100.201)
--port=PORT                # Device port (default: from config or 4370)
--timeout=SECONDS          # Connection timeout in seconds (default: from config or 30)
--password=PASSWORD        # Device password (default: from config or 0)
--verbose                  # Enable verbose output (default: from config or false)
--force-udp                # Use UDP instead of TCP (default: from config or false)
--no-ping                  # Skip ping check (default: from config or true)
--encoding=ENCODING        # Character encoding (default: from config or UTF-8)
```

### Configuration

RBZK supports persistent configuration through a configuration file. This allows you to set default values for IP address and other options without having to specify them every time.

#### Configuration File Location

The configuration file is stored in one of the following locations (in order of precedence):

1. `$XDG_CONFIG_HOME/rbzk/config.yml` (if `$XDG_CONFIG_HOME` is set)
2. `$HOME/.config/rbzk/config.yml` (on most systems)
3. `.rbzk.yml` in the current directory (fallback)

#### Configuration Commands

```bash
# Show current configuration
bin/rbzk config

# Set a configuration value
bin/rbzk config-set ip 192.168.1.201
bin/rbzk config-set port 4371
bin/rbzk config-set password 12345
bin/rbzk config-set verbose true

# Reset configuration to defaults
bin/rbzk config-reset
```

When you run commands, the CLI will use values from the configuration file as defaults. Command-line options will override the configuration file values.

### Examples

```bash
# Get device information
bin/rbzk info 192.168.100.201

# Get users with custom port and password
bin/rbzk users 192.168.100.201 --port=4371 --password=12345

# Get today's attendance logs with verbose output
bin/rbzk logs 192.168.100.201 --today --verbose

# Get logs for a custom date range (two ways)
bin/rbzk logs-custom 2023-01-01 2023-01-31 192.168.100.201
bin/rbzk logs 192.168.100.201 --start-date=2023-01-01 --end-date=2023-01-31

# Get logs from a specific date to today
bin/rbzk logs 192.168.100.201 --start-date=2023-01-01

# Get logs from 30 days before to a specific date
bin/rbzk logs 192.168.100.201 --end-date=2023-01-31

# Test voice with UDP connection
bin/rbzk test_voice 192.168.100.201 --force-udp
```

### Pretty Output

The command line interface uses the `terminal-table` gem for prettier output if it's available. To enable this feature, install the gem:

```bash
gem install terminal-table
```

If the gem is not available, the CLI will fall back to plain text output.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can
also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the
version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version,
push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shqear93/rbzk.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
