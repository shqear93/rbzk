# RBZK

A Ruby implementation of the ZK protocol for fingerprint and biometric attendance devices.

This project is inspired by and based on the [pyzk Python library](https://github.com/fananimi/pyzk), adapting its protocol implementation to Ruby while maintaining compatibility with ZKTeco devices.

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

## Library Usage

The `rbzk` gem provides a `RBZK::ZK` class to interact with ZKTeco devices.

### Basic Connection

```ruby
require 'rbzk'

# Create a new ZK instance
# Replace with your device's IP address
zk = RBZK::ZK.new('192.168.1.201', port: 4370, timeout: 60, password: 0)

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

  # Disable the device to ensure exclusive access for sensitive operations
  puts 'Disabling device...'
  conn.disable_device

  # --- Your operations here ---
  puts "Device Firmware Version: #{conn.get_firmware_version}"
  puts "Serial Number: #{conn.get_serialnumber}"
  # --- End of operations ---

  # Re-enable the device when done
  puts 'Enabling device...'
  conn.enable_device
rescue RBZK::ZKError => e # Catch specific RBZK errors
  puts "ZK Error: #{e.message}"
rescue => e # Catch other potential errors
  puts "Generic Error: #{e.message}"
ensure
  # Always disconnect when done
  conn.disconnect if conn && conn.connected?
  puts "Disconnected."
end
```

### Device Information

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance
# (See Basic Connection example)

puts "--- Device Information ---"
puts "Firmware Version: #{conn.get_firmware_version}"
puts "Serial Number: #{conn.get_serialnumber}"
puts "MAC Address: #{conn.get_mac}"
puts "Device Name: #{conn.get_device_name}"
puts "Platform: #{conn.get_platform}"
puts "Fingerprint Algorithm Version: #{conn.get_fp_version}"
# puts "Face Algorithm Version: #{conn.get_face_version}" # If applicable
puts "Device Time: #{conn.get_time}"

# Get user, fingerprint, and record counts/capacities
conn.read_sizes # Updates internal counts
puts "User Count: #{conn.instance_variable_get(:@users)}"
puts "Fingerprint Count: #{conn.instance_variable_get(:@fingers)}"
puts "Attendance Record Count: #{conn.instance_variable_get(:@records)}"
puts "User Capacity: #{conn.instance_variable_get(:@users_cap)}"
puts "Fingerprint Capacity: #{conn.instance_variable_get(:@fingers_cap)}"
puts "Record Capacity: #{conn.instance_variable_get(:@rec_cap)}"
```

### Device Control

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

# Restart the device
# conn.restart
# puts "Device restarting..."

# Power off the device (use with caution)
# conn.poweroff
# puts "Device powering off..."

# Test a voice prompt (e.g., "Thank you")
# conn.test_voice(RBZK::Constants::EF_THANKYOU) # Check Constants for available voice enums
# puts "Tested voice prompt."

# Unlock the door for 5 seconds
conn.unlock(5)
puts "Door unlocked for 5 seconds."

# Get door lock state
state = conn.get_lock_state
puts "Door is #{state ? 'Open' : 'Closed'}."
```

### LCD Operations

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

# Write text to LCD (line number, text)
conn.write_lcd(1, "Hello from RBZK!")
puts "Text written to LCD line 1."
conn.write_lcd(2, Time.now.strftime("%H:%M:%S"))
puts "Text written to LCD line 2."

# Clear the LCD display
# sleep 5 # Keep text for 5 seconds
# conn.clear_lcd
# puts "LCD cleared."
```

### User Management

#### Getting Users

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

puts '--- Get Users ---'
users = conn.get_users
users.each do |user|
  privilege = 'User'
  privilege = 'Admin' if user.privilege == RBZK::Constants::USER_ADMIN

  puts "UID: #{user.uid}"
  puts "Name: #{user.name}"
  puts "Privilege: #{privilege}"
  puts "Password: #{user.password}" # Be mindful of displaying passwords
  puts "Group ID: #{user.group_id}"
  puts "User ID (PIN2): #{user.user_id}"
  puts "Card: #{user.card}"
  puts "---"
end
```

#### Add/Update User

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

puts '--- Add/Update User ---'
# For a new user, UID can often be omitted if the device assigns it.
# To update an existing user, provide their UID.
# conn.read_sizes # Ensure @next_uid is populated if device assigns UIDs
# new_uid = conn.instance_variable_get(:@next_uid) # Example for new user

user_attributes = {
  uid: 123, # Specify UID to update, or omit for device to assign (check device behavior)
  name: 'John Doe',
  privilege: RBZK::Constants::USER_DEFAULT,
  password: '1234',
  group_id: '1',
  user_id: 'JD123', # Custom User ID / PIN2
  card: 7890
}

if conn.set_user(**user_attributes)
  puts "User #{user_attributes[:name]} (UID: #{user_attributes[:uid] || 'auto'}) added/updated successfully."
  conn.refresh_data # Good practice to refresh data after modifications
else
  puts "Failed to add/update user."
end
```

#### Delete User

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

puts '--- Delete User ---'
uid_to_delete = 123 # UID of the user to delete

if conn.delete_user(uid: uid_to_delete)
  puts "User with UID #{uid_to_delete} deleted successfully."
  conn.refresh_data
else
  puts "Failed to delete user with UID #{uid_to_delete} (may not exist)."
end
```

### Attendance Log Management

#### Getting Attendance Logs

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

puts '--- Get Attendance Logs ---'
logs = conn.get_attendance_logs
if logs.empty?
  puts "No attendance logs found."
else
  logs.each_with_index do |log, index|
    puts "Log ##{index + 1}:"
    puts "  Device UID: #{log.uid}" # Internal device UID for the record
    puts "  User ID (PIN2): #{log.user_id}"
    # Status: Check-in, Check-out, etc. (Refer to ZK documentation for specific status codes)
    puts "  Status: #{log.status}"
    # Punch: Fingerprint, Password, Card, etc. (Refer to ZK documentation)
    puts "  Punch Type: #{log.punch}"
    puts "  Timestamp: #{log.timestamp.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "---"
  end
end
```

#### Clear Attendance Logs

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

# puts '--- Clear Attendance Logs ---'
# puts "WARNING: This will delete all attendance logs from the device."
# print "Are you sure? (yes/N): "
# confirmation = gets.chomp
# if confirmation.downcase == 'yes'
#   if conn.clear_attendance
#     puts "Attendance logs cleared successfully."
#     conn.refresh_data
#   else
#     puts "Failed to clear attendance logs."
#   end
# else
#   puts "Operation cancelled."
# end
```

### Fingerprint Template Management

*(Note: Fingerprint template data is binary and device-specific. Handling it requires careful understanding of the ZK protocol and template formats.)*

#### Get All Fingerprint Templates

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

puts '--- Get All Fingerprint Templates ---'
templates = conn.get_templates
if templates.empty?
  puts "No fingerprint templates found."
else
  templates.each do |fp_template|
    puts "UID: #{fp_template.uid}, Finger ID: #{fp_template.fid}, Valid: #{fp_template.valid}, Size: #{fp_template.size}"
  end
end
```

#### Get a Specific User's Fingerprint Template

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

user_uid = '123' # The user's main UID (often a string from device)
finger_id = 0    # Finger index (0-9)

begin
  fp_template = conn.get_user_template(user_uid, finger_id)
  if fp_template
    puts "Template for UID #{user_uid}, Finger ID #{finger_id}: Size #{fp_template.size}, Valid: #{fp_template.valid}"
    # fp_template.template contains the binary data
  else
    puts "Template not found for UID #{user_uid}, Finger ID #{finger_id}."
  end
rescue RBZK::ZKErrorResponse => e
  puts "Error getting template: #{e.message}"
end
```

#### Set a User's Fingerprint Template

*(This is an advanced operation. You need valid template data.)*
```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance
# And `valid_template_data` is a binary string of a valid fingerprint template

# user_uid = '123'
# finger_id = 0
# valid_flag = 1 # 1 for valid, 0 for invalid/duplicate
# valid_template_data = "BINARY_TEMPLATE_DATA_HERE" # Replace with actual binary data

# begin
#   if conn.set_user_template(valid_template_data, user_uid, finger_id, valid_flag)
#     puts "Fingerprint template set successfully for UID #{user_uid}, Finger ID #{finger_id}."
#     conn.refresh_data
#   else
#     puts "Failed to set fingerprint template."
#   end
# rescue RBZK::ZKErrorResponse => e
#   puts "Error setting template: #{e.message}"
# end
```

#### Delete/Clear Fingerprint Templates

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

# Delete a specific fingerprint for a user
# user_uid_for_fp_delete = '123'
# finger_id_to_delete = 0
# if conn.delete_user_template(user_uid_for_fp_delete, finger_id_to_delete)
#   puts "Template for UID #{user_uid_for_fp_delete}, FID #{finger_id_to_delete} deleted."
#   conn.refresh_data
# else
#   puts "Failed to delete template."
# end

# Clear all fingerprint templates for a specific user
# user_uid_to_clear_fps = '123'
# if conn.clear_user_template(user_uid_to_clear_fps) # Method name might vary, e.g., delete_user_fingerprints
#   puts "All templates for UID #{user_uid_to_clear_fps} cleared."
#   conn.refresh_data
# else
#   puts "Failed to clear user templates."
# end

# Clear ALL fingerprint templates on the device (Use with extreme caution!)
# puts "WARNING: This will delete ALL fingerprint templates from the device."
# print "Are you sure? (yes/N): "
# confirmation_clear_all_fp = gets.chomp
# if confirmation_clear_all_fp.downcase == 'yes'
#   if conn.clear_templates # Or clear_fingerprints
#     puts "All fingerprint templates cleared from device."
#     conn.refresh_data
#   else
#     puts "Failed to clear all fingerprint templates."
#   end
# else
#   puts "Operation cancelled."
# end
```

### Device Time

```ruby
# Assuming 'conn' is an active and connected RBZK::ZK instance

# Get device time
current_device_time = conn.get_time
puts "Current device time: #{current_device_time}"

# Set device time (to current system time)
# new_time = Time.now
# if conn.set_time(new_time)
#   puts "Device time set to #{new_time} successfully."
# else
#   puts "Failed to set device time."
# end
```

## Command Line Interface (CLI)

The `rbzk` gem also provides a command-line tool named `rbzk` for quick interactions with your ZKTeco devices.

### Global Options

These options can be used with most commands:

*   `--ip <IP_ADDRESS>`: IP address of the device.
*   `--port <PORT>`: Port number (default: 4370).
*   `--timeout <SECONDS>`: Connection timeout in seconds (default: 30 or 60).
*   `--password <PASSWORD>`: Device communication password (default: 0).
*   `--verbose`: Enable verbose output.
*   `--force-udp`: Force UDP mode for communication.
*   `--no-ping`: Skip the initial ping check.
*   `--encoding <ENCODING>`: String encoding (default: UTF-8).

### Available Commands

Here are some of the primary commands available:

*   `rbzk info [--ip IP]`: Get detailed device information.
*   `rbzk refresh [--ip IP]`: Refresh the device's internal data (useful after making changes).
*   `rbzk users [--ip IP]`: List all users on the device.
*   `rbzk logs [--ip IP] [options]`: Get attendance logs.
    *   `--today`: Get today's logs.
    *   `--yesterday`: Get yesterday's logs.
    *   `--week`: Get logs for the current week.
    *   `--month`: Get logs for the current month.
    *   `--start-date YYYY-MM-DD`: Filter logs from a specific start date.
    *   `--end-date YYYY-MM-DD`: Filter logs up to a specific end date.
    *   `--limit N`: Limit the number of logs displayed (0 for all).
    *   Aliases: `rbzk logs-today`, `rbzk logs-yesterday`, `rbzk logs-week`, `rbzk logs-month`.
*   `rbzk logs-all [--ip IP]`: Get all attendance logs without any limit.
*   `rbzk logs-custom <START_DATE> <END_DATE> [--ip IP]`: Get logs for a custom date range (YYYY-MM-DD).
*   `rbzk clear-logs [--ip IP]`: Clear all attendance logs from the device (prompts for confirmation).
*   `rbzk unlock [--ip IP] [--time SECONDS]`: Unlock the connected door (default 3 seconds).
*   `rbzk door-state [--ip IP]`: Get the current state of the door lock (Open/Closed).
*   `rbzk write-lcd <LINE_NUMBER> <TEXT> [--ip IP]`: Write text to the device's LCD screen.
*   `rbzk clear-lcd [--ip IP]`: Clear the device's LCD screen.
*   `rbzk add-user [--ip IP] [options]`: Add or update a user.
    *   `--uid <UID
