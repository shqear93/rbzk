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

### Complete Example

See the `examples/complete_example.rb` file for a comprehensive example that demonstrates all the main functionality of the gem.

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
