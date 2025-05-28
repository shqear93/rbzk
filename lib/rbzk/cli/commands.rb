#!/usr/bin/env ruby
# frozen_string_literal: true

require 'thor'
require 'yaml'
require 'fileutils'
require 'date'
require 'rbzk'
require 'rbzk/cli/config'
require 'terminal-table'

module RBZK
  module CLI
    class Commands < Thor

      # Global options
      class_option :ip, type: :string, desc: 'IP address of the device'
      class_option :port, type: :numeric, desc: 'Port number (default: 4370)'
      class_option :timeout, type: :numeric, desc: 'Connection timeout in seconds (default: 30)'
      class_option :password, type: :numeric, desc: 'Device password (default: 0)'
      class_option :verbose, type: :boolean, desc: 'Enable verbose output'
      class_option :force_udp, type: :boolean, desc: 'Force UDP mode'
      class_option :no_ping, type: :boolean, desc: 'Skip ping check'
      class_option :encoding, type: :string, desc: 'Encoding for strings (default: UTF-8)'

      desc "info [IP]", "Get device information"

      def info(ip = nil)

        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        with_connection(ip, options) do |conn|
          # Get device information
          # First read sizes to get user counts and capacities
          conn.read_sizes

          device_info = {
            'Serial Number' => conn.get_serialnumber,
            'MAC Address' => conn.get_mac,
            'Device Name' => conn.get_device_name,
            'Firmware Version' => conn.get_firmware_version,
            'Platform' => conn.get_platform,
            'Face Version' => conn.get_face_version,
            'Fingerprint Version' => conn.get_fp_version,
            'Device Time' => conn.get_time,
            'Users' => conn.instance_variable_get(:@users),
            'Fingerprints' => conn.instance_variable_get(:@fingers),
            'Attendance Records' => conn.instance_variable_get(:@records),
            'User Capacity' => conn.instance_variable_get(:@users_cap),
            'Fingerprint Capacity' => conn.instance_variable_get(:@fingers_cap),
            'Record Capacity' => conn.instance_variable_get(:@rec_cap),
            'Face Capacity' => conn.instance_variable_get(:@faces_cap),
            'Faces' => conn.instance_variable_get(:@faces)
          }

          # Display information
          if defined?(::Terminal) && defined?(::Terminal::Table)
            # Pretty table output
            table = ::Terminal::Table.new do |t|
              t.title = "Device Information"
              device_info.each do |key, value|
                t << [ key, value ]
              end
            end

            puts table
          else
            # Fallback plain text output
            puts "Device Information:"
            device_info.each do |key, value|
              puts "#{key}: #{value}"
            end
          end
        end
      end

      desc "refresh [IP]", "Refresh device data"

      def refresh(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        with_connection(ip, options) do |conn|
          puts "Refreshing device data..."
          result = conn.refresh_data
          puts "✓ Device data refreshed successfully!" if result
        end
      end

      desc "users [IP]", "Get users from the device"

      def users(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']
        with_connection(ip, options) do |conn|
          puts "Getting users..."
          users = conn.get_users
          display_users(users)
        end
      end

      desc "logs [IP]", "Get attendance logs"
      method_option :today, type: :boolean, desc: "Get only today's logs"
      method_option :yesterday, type: :boolean, desc: "Get only yesterday's logs"
      method_option :week, type: :boolean, desc: "Get this week's logs"
      method_option :month, type: :boolean, desc: "Get this month's logs"
      method_option :start_date, type: :string, desc: "Start date for custom range (YYYY-MM-DD)"
      method_option :end_date, type: :string, desc: "End date for custom range (YYYY-MM-DD)"
      method_option :limit, type: :numeric, default: 25, desc: "Limit the number of logs displayed (default: 25, use 0 for all)"

      # Add aliases for common log commands
      desc "logs-today [IP]", "Get today's attendance logs"
      map "logs-today" => "logs"

      def logs_today(ip = nil)

        invoke :logs, [ ip ], today: true
      end

      desc "logs-yesterday [IP]", "Get yesterday's attendance logs"
      map "logs-yesterday" => "logs"

      def logs_yesterday(ip = nil)
        invoke :logs, [ ip ], yesterday: true
      end

      desc "logs-week [IP]", "Get this week's attendance logs"
      map "logs-week" => "logs"

      def logs_week(ip = nil)
        invoke :logs, [ ip ], week: true
      end

      desc "logs-month [IP]", "Get this month's attendance logs"
      map "logs-month" => "logs"

      def logs_month(ip = nil)
        invoke :logs, [ ip ], month: true
      end

      desc "logs-all [IP]", "Get all attendance logs without limit"

      def logs_all(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        with_connection(ip, options) do |conn|
          # Get attendance logs
          puts "Getting all attendance logs (this may take a while)..."
          logs = conn.get_attendance_logs
          total_logs = logs.size
          puts "Total logs: #{total_logs}" if options[:verbose]

          # Display logs
          if logs && !logs.empty?
            puts "\nFound #{logs.size} attendance records:"

            if defined?(::Terminal) && defined?(::Terminal::Table)
              # Pretty table output
              table = ::Terminal::Table.new do |t|
                t.title = "All Attendance Logs (Showing All Records)"
                t.headings = [ 'User ID', 'Time', 'Status' ]

                # Show all logs in the table
                logs.each do |log|
                  t << [
                    log.user_id,
                    log.timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                    format_status(log.status)
                  ]
                end
              end

              puts table
            else
              # Fallback plain text output
              logs.each do |log|
                puts "  User ID: #{log.user_id}, Time: #{log.timestamp.strftime('%Y-%m-%d %H:%M:%S')}, Status: #{format_status(log.status)}"
              end
            end
          else
            puts "\nNo attendance records found"
          end
        end
      end

      desc "logs-custom START_DATE END_DATE [IP]", "Get logs for a custom date range (YYYY-MM-DD)"

      def logs_custom(start_date, end_date, ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']
        invoke :logs, [ ip ], start_date: start_date, end_date: end_date
      end

      desc "logs [IP]", "Get all attendance logs"

      def logs(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']
        with_connection(ip, options) do |conn|
          # Get attendance logs
          puts "Getting attendance logs..."
          logs = conn.get_attendance_logs
          total_logs = logs.size
          puts "Total logs: #{total_logs}" if options[:verbose]

          # Filter logs based on options
          title = if options[:today]
                    today = Date.today
                    logs = filter_logs_by_date(logs, today, today)
                    "Today's Attendance Logs (#{today})"
                  elsif options[:yesterday]
                    yesterday = Date.today - 1
                    logs = filter_logs_by_date(logs, yesterday, yesterday)
                    "Yesterday's Attendance Logs (#{yesterday})"
                  elsif options[:week]
                    today = Date.today
                    start_of_week = today - today.wday
                    logs = filter_logs_by_date(logs, start_of_week, today)
                    "This Week's Attendance Logs (#{start_of_week} to #{today})"
                  elsif options[:month]
                    today = Date.today
                    start_of_month = Date.new(today.year, today.month, 1)
                    logs = filter_logs_by_date(logs, start_of_month, today)
                    "This Month's Attendance Logs (#{start_of_month} to #{today})"
                  elsif options[:start_date] && options[:end_date]
                    begin
                      start_date = Date.parse(options[:start_date])
                      end_date = Date.parse(options[:end_date])

                      # Print debug info
                      puts "Filtering logs from #{start_date} to #{end_date}..." if options[:verbose]

                      # Use the filter_logs_by_date method
                      logs = filter_logs_by_date(logs, start_date, end_date)

                      "Attendance Logs (#{start_date} to #{end_date})"
                    rescue ArgumentError
                      puts "Error: Invalid date format. Please use YYYY-MM-DD format."
                      return
                    end
                  elsif options[:start_date]
                    begin
                      start_date = Date.parse(options[:start_date])
                      end_date = Date.today

                      # Print debug info
                      puts "Filtering logs from #{start_date} onwards..." if options[:verbose]

                      # Use the filter_logs_by_date method
                      logs = filter_logs_by_date(logs, start_date, end_date)

                      "Attendance Logs (#{start_date} to #{end_date})"
                    rescue ArgumentError
                      puts "Error: Invalid date format. Please use YYYY-MM-DD format."
                      return
                    end
                  elsif options[:end_date]
                    begin
                      end_date = Date.parse(options[:end_date])
                      # Default start date to 30 days before end date
                      start_date = end_date - 30

                      # Print debug info
                      puts "Filtering logs from #{start_date} to #{end_date}..." if options[:verbose]

                      # Use the filter_logs_by_date method
                      logs = filter_logs_by_date(logs, start_date, end_date)

                      "Attendance Logs (#{start_date} to #{end_date})"
                    rescue ArgumentError
                      puts "Error: Invalid date format. Please use YYYY-MM-DD format."
                      return
                    end
                  else
                    "All Attendance Logs"
                  end

          # Display logs
          if logs && !logs.empty?
            puts "\nFound #{logs.size} attendance records:"

            # Determine how many logs to display
            limit = options[:limit] || 25
            display_logs = limit > 0 ? logs.first(limit) : logs

            if defined?(::Terminal) && defined?(::Terminal::Table)
              # Pretty table output
              table = ::Terminal::Table.new do |t|
                t.title = title || "Attendance Logs"
                t.headings = [ 'User ID', 'Time', 'Status' ]

                # Show logs in the table based on limit
                display_logs.each do |log|
                  t << [
                    log.user_id,
                    log.timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                    format_status(log.status)
                  ]
                end
              end

              puts table

              # Show summary if logs were limited
              if limit > 0 && logs.size > limit
                puts "Showing #{display_logs.size} of #{logs.size} records. Use --limit option to change the number of records displayed."
              end
            else
              # Fallback plain text output
              display_logs.each do |log|
                puts "  User ID: #{log.user_id}, Time: #{log.timestamp.strftime('%Y-%m-%d %H:%M:%S')}, Status: #{format_status(log.status)}"
              end

              if logs.size > display_logs.size
                puts "  ... and #{logs.size - display_logs.size} more records"
              end
            end
          else
            puts "\nNo attendance records found"
          end
        end
      end

      desc "clear-logs [IP]", "Clear attendance logs"
      map "clear-logs" => :clear_logs

      def clear_logs(ip = nil)

        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']
        with_connection(ip, options) do |conn|
          puts "WARNING: This will delete all attendance logs from the device."
          return unless yes?("Are you sure you want to continue? (y/N)")

          puts "Clearing attendance logs..."
          result = conn.clear_attendance
          puts "✓ Attendance logs cleared successfully!" if result
        end
      end

      desc "unlock [IP]", "Unlock the door"
      method_option :time, type: :numeric, default: 3, desc: "Unlock time in seconds (default: 3)"
      map "unlock" => :unlock_door

      def unlock_door(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        # Get the unlock time
        time = options[:time] || 3

        with_connection(ip, options) do |conn|
          puts "Unlocking door for #{time} seconds..."
          result = conn.unlock(time)
          puts "✓ Door unlocked successfully!" if result
        end
      end

      desc "door-state [IP]", "Get the door lock state"
      map "door-state" => :door_state

      def door_state(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        with_connection(ip, options) do |conn|
          state = conn.get_lock_state
          puts "Door state: #{state ? 'Open' : 'Closed'}"
        end
      end

      desc "write-lcd [IP] LINE_NUMBER TEXT", "Write text to LCD display"
      map "write-lcd" => :write_lcd

      def write_lcd(line_number, text, ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        # Convert line_number to integer
        line_number = line_number.to_i

        with_connection(ip, options) do |conn|
          puts "Writing text to LCD line #{line_number}..."
          result = conn.write_lcd(line_number, text)
          puts "✓ Text written to LCD successfully!" if result
        end
      end

      desc "clear-lcd [IP]", "Clear the LCD display"
      map "clear-lcd" => :clear_lcd

      def clear_lcd(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        with_connection(ip, options) do |conn|
          puts "Clearing LCD display..."
          result = conn.clear_lcd
          puts "✓ LCD cleared successfully!" if result
        end
      end

      desc "add-user [IP]", "Add or update a user"
      method_option :uid, type: :numeric, desc: "User ID (generated by device if not provided)"
      method_option :name, type: :string, default: "", desc: "User name"
      method_option :privilege, type: :numeric, default: 0, desc: "User privilege (0=User, 14=Admin)"
      method_option :password, type: :string, default: "", desc: "User password"
      method_option :group_id, type: :string, default: "", desc: "Group ID"
      method_option :user_id, type: :string, default: "", desc: "Custom user ID"
      method_option :card, type: :numeric, default: 0, desc: "Card number"
      map "add-user" => :add_user

      def add_user(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        with_connection(ip, options) do |conn|
          puts "Adding/updating user..."

          # Extract user parameters from options
          user_params = {
            uid: options[:uid],
            name: options[:name] || "",
            privilege: options[:privilege] || 0,
            password: options[:password] || "",
            group_id: options[:group_id] || "",
            user_id: options[:user_id] || "",
            card: options[:card] || 0
          }

          # Ensure all string parameters are strings, not nil
          user_params[:name] = "" if user_params[:name].nil?
          user_params[:password] = "" if user_params[:password].nil?
          user_params[:group_id] = "" if user_params[:group_id].nil?
          user_params[:user_id] = "" if user_params[:user_id].nil?

          result = conn.set_user(**user_params)
          puts "✓ User added/updated successfully!" if result
        end
      end

      desc "delete-user [IP]", "Delete a user"
      method_option :uid, type: :numeric, desc: "User ID (generated by device)"
      method_option :user_id, type: :string, desc: "Custom user ID"
      map "delete-user" => :delete_user

      def delete_user(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        # Ensure at least one of uid or user_id is provided
        if options[:uid].nil? && (options[:user_id].nil? || options[:user_id].empty?)
          puts "Error: You must provide either --uid or --user-id"
          return
        end

        with_connection(ip, options) do |conn|
          puts "Deleting user..."

          # Extract user parameters from options
          user_params = {
            uid: options[:uid] || 0,
            user_id: options[:user_id] || ""
          }

          result = conn.delete_user(**user_params)
          if result
            puts "✓ User deleted successfully!"
          else
            puts "✗ User not found or could not be deleted."
          end
        end
      end

      desc "get-templates [IP]", "Get all fingerprint templates"
      map "get-templates" => :get_templates

      def get_templates(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        with_connection(ip, options) do |conn|
          puts "Getting fingerprint templates..."
          templates = conn.get_templates

          if templates && !templates.empty?
            puts "✓ Found #{templates.size} fingerprint templates:"

            # Use Terminal::Table for pretty output
            table = ::Terminal::Table.new do |t|
              t.title = "Fingerprint Templates"
              t.headings = ['UID', 'Finger ID', 'Valid', 'Size']

              templates.each do |template|
                t << [
                  template.uid,
                  template.fid,
                  template.valid == 1 ? 'Yes' : 'No',
                  template.size
                ]
              end
            end

            puts table
          else
            puts "✓ No fingerprint templates found"
          end
        end
      end

      desc "get-user-template [IP]", "Get a specific user's fingerprint template"
      method_option :uid, type: :numeric, desc: "User ID (generated by device)"
      method_option :user_id, type: :string, desc: "Custom user ID"
      method_option :finger_id, type: :numeric, default: 0, desc: "Finger ID (0-9)"
      map "get-user-template" => :get_user_template

      def get_user_template(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        # Ensure at least one of uid or user_id is provided
        if options[:uid].nil? && (options[:user_id].nil? || options[:user_id].empty?)
          puts "Error: You must provide either --uid or --user-id"
          return
        end

        with_connection(ip, options) do |conn|
          puts "Getting user fingerprint template..."

          # Extract parameters from options
          uid = options[:uid] || 0
          user_id = options[:user_id] || ""
          finger_id = options[:finger_id] || 0

          template = conn.get_user_template(uid: uid, temp_id: finger_id, user_id: user_id)

          if template
            puts "✓ Found fingerprint template:"
            puts "  User ID: #{template.uid}"
            puts "  Finger ID: #{template.fid}"
            puts "  Valid: #{template.valid == 1 ? 'Yes' : 'No'}"
            puts "  Size: #{template.size} bytes"
          else
            puts "✗ Fingerprint template not found"
          end
        end
      end

      desc "delete-template [IP]", "Delete a specific fingerprint template"
      method_option :uid, type: :numeric, desc: "User ID (generated by device)"
      method_option :user_id, type: :string, desc: "Custom user ID"
      method_option :finger_id, type: :numeric, default: 0, desc: "Finger ID (0-9)"
      map "delete-template" => :delete_template

      def delete_template(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        # Ensure at least one of uid or user_id is provided
        if options[:uid].nil? && (options[:user_id].nil? || options[:user_id].empty?)
          puts "Error: You must provide either --uid or --user-id"
          return
        end

        with_connection(ip, options) do |conn|
          puts "Deleting fingerprint template..."

          # Extract parameters from options
          uid = options[:uid] || 0
          user_id = options[:user_id] || ""
          finger_id = options[:finger_id] || 0

          result = conn.delete_user_template(uid: uid, temp_id: finger_id, user_id: user_id)

          if result
            puts "✓ Fingerprint template deleted successfully!"
          else
            puts "✗ Fingerprint template not found or could not be deleted"
          end
        end
      end

      desc "test-voice [IP]", "Test the device voice"
      method_option :index, type: :numeric, desc: "Sound index to play (0-35, default: 0)"
      map "test-voice" => :test_voice

      def test_voice(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        # Get the sound index
        index = options[:index] || 0

        # Print available sound indices if verbose
        if options[:verbose]
          puts "Available sound indices:"
          puts " 0: Thank You"
          puts " 1: Incorrect Password"
          puts " 2: Access Denied"
          puts " 3: Invalid ID"
          puts " 4: Please try again"
          puts " 5: Duplicate ID"
          puts " 6: The clock is flow"
          puts " 7: The clock is full"
          puts " 8: Duplicate finger"
          puts " 9: Duplicated punch"
          puts "10: Beep kuko"
          puts "11: Beep siren"
          puts "13: Beep bell"
          puts "18: Windows(R) opening sound"
          puts "20: Fingerprint not emolt"
          puts "21: Password not emolt"
          puts "22: Badges not emolt"
          puts "23: Face not emolt"
          puts "24: Beep standard"
          puts "30: Invalid user"
          puts "31: Invalid time period"
          puts "32: Invalid combination"
          puts "33: Illegal Access"
          puts "34: Disk space full"
          puts "35: Duplicate fingerprint"
          puts "51: Focus eyes on the green box"
        end

        with_connection(ip, options) do |conn|
          puts "Testing device voice with index #{index}..."
          result = conn.test_voice(index)
          puts "✓ Voice test successful!" if result
        end
      end

      desc "restart [IP]", "Restart the device"

      def restart(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        if yes?("Are you sure you want to restart the device? (y/N)")
          with_connection(ip, options) do |conn|
            puts "Restarting device..."
            result = conn.restart
            puts "✓ Device restart command sent successfully!" if result
            puts "The device will restart now. You may need to wait a few moments before reconnecting."
          end
        else
          puts "Operation cancelled."
        end
      end

      desc "poweroff [IP]", "Power off the device"

      def poweroff(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']

        if yes?("Are you sure you want to power off the device? (y/N)")
          with_connection(ip, options) do |conn|
            puts "Powering off device..."
            result = conn.poweroff
            puts "✓ Device poweroff command sent successfully!" if result
            puts "The device will power off now. You will need to manually power it back on."
          end
        else
          puts "Operation cancelled."
        end
      end

      desc "config", "Show current configuration"

      def config
        puts "RBZK Configuration"
        puts "=================="
        @config.to_h.each do |key, value|
          puts "#{key}: #{value}"
        end
      end

      desc "config-set KEY VALUE", "Set a configuration value"

      def config_set(key, value)
        # Convert value to appropriate type
        typed_value = case key
                      when 'port', 'timeout', 'password'
                        value.to_i
                      when 'verbose', 'force_udp', 'no_ping'
                        value.downcase == 'true'
                      else
                        value
                      end

        @config[key] = typed_value
        @config.save
        puts "Configuration updated: #{key} = #{typed_value}"
      end

      desc "config-reset", "Reset configuration to defaults"

      def config_reset
        if yes?("Are you sure you want to reset all configuration to defaults? (y/N)")
          FileUtils.rm_f(@config.config_file)
          @config = RBZK::CLI::Config.new
          puts "Configuration reset to defaults."
          invoke :config
        else
          puts "Operation cancelled."
        end
      end

      private

      def initialize(*args)
        super
        @config = RBZK::CLI::Config.new
      end

      def with_connection(ip, options = {})
        puts "Connecting to ZKTeco device at #{ip}:#{options[:port] || @config['port'] || 4370}..."
        puts "Please ensure the device is powered on and connected to the network."

        begin
          # Create ZK instance with options from config and command line
          zk_options = {
            port: options[:port] || @config['port'] || 4370,
            timeout: options[:timeout] || @config['timeout'] || 30,
            password: options[:password] || @config['password'] || 0,
            verbose: options[:verbose] || @config['verbose'] || false,
            force_udp: options[:force_udp] || @config['force_udp'] || false,
            omit_ping: options[:no_ping] || @config['no_ping'] || false,
            encoding: options[:encoding] || @config['encoding'] || 'UTF-8'
          }

          zk = RBZK::ZK.new(ip, **zk_options)
          conn = zk.connect

          if conn.connected?
            puts "✓ Connected successfully!" unless options[:quiet]
            yield conn if block_given?
          else
            puts "✗ Failed to connect to device."
          end
        rescue RBZK::ZKNetworkError => e
          puts "✗ Network Error: #{e.message}"
          puts "Please check the IP address and ensure the device is reachable."
        rescue RBZK::ZKErrorResponse => e
          puts "✗ Device Error: #{e.message}"
          puts "The device returned an error response."
        rescue => e
          puts "✗ Unexpected Error: #{e.message}"
          puts "An unexpected error occurred while communicating with the device."
          puts e.backtrace.join("\n") if options[:verbose]
        ensure
          if conn && conn.connected?
            puts "Disconnecting from device..." unless options[:quiet]
            conn.disconnect
            puts "✓ Disconnected" unless options[:quiet]
          end
        end
      end

      def display_users(users)
        if users && !users.empty?
          puts "✓ Found #{users.size} users:"

          # Use Terminal::Table for pretty output
          table = ::Terminal::Table.new do |t|
            t.title = "Users"
            t.headings = [ 'UID', 'User ID', 'Name', 'Privilege', 'Password', 'Group ID', 'Card' ]

            users.each do |user|
              t << [
                user.uid,
                user.user_id,
                user.name,
                format_privilege(user.privilege),
                (user.password.nil? || user.password.empty?) ? '(none)' : '(set)',
                user.group_id,
                user.card
              ]
            end
          end

          puts table
        else
          puts "✓ No users found"
        end
      end

      def filter_logs_by_date(logs, start_date, end_date)
        # Convert Date objects to strings for comparison
        total_logs = logs.size
        start_date_str = start_date.strftime('%Y-%m-%d')
        end_date_str = end_date.strftime('%Y-%m-%d')

        if options[:verbose]
          puts "Filtering logs from #{start_date_str} to #{end_date_str}..."
          puts "Total logs before filtering: #{total_logs}"
        end

        # Filter logs by date range using string comparison
        filtered_logs = []
        logs.each do |log|
          log_date_str = log.timestamp.strftime('%Y-%m-%d')
          if log_date_str >= start_date_str && log_date_str <= end_date_str
            filtered_logs << log
          end
        end

        if options[:verbose]
          puts "Filtered logs: #{filtered_logs.size} of #{total_logs}"
        end

        # Return the filtered logs
        filtered_logs
      end

      def format_status(status)
        case status
        when 0 then "Check In"
        when 1 then "Check Out"
        when 2 then "Break Out"
        when 3 then "Break In"
        when 4 then "Overtime In"
        when 5 then "Overtime Out"
        else "Unknown (#{status})"
        end
      end

      def format_privilege(privilege)
        case privilege
        when 0 then "User"
        when 1 then "Enroller"
        when 2 then "Manager"
        when 3 then "Administrator"
        when 14 then "Super Admin"
        else "Unknown (#{privilege})"
        end
      end
    end
  end
end
