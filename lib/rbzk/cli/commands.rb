require 'thor'
require 'rbzk'
require 'date'
require 'rbzk/cli/config'

# Check if terminal-table is available
begin
  require 'terminal-table'
  HAS_TERMINAL_TABLE = true
rescue LoadError
  HAS_TERMINAL_TABLE = false
end

module RBZK
  module CLI
    # Thor-based command-line interface for RBZK
    class Commands < Thor
      # Load configuration before running any command
      def initialize(*args)
        super
        @config = Config.new
      end
      # Default IP address can be provided as an option
      class_option :ip, type: :string, desc: "Device IP address (default: 192.168.100.201)"
      class_option :port, type: :numeric, default: 4370, desc: "Device port"
      class_option :timeout, type: :numeric, default: 30, desc: "Connection timeout in seconds"
      class_option :password, type: :numeric, default: 0, desc: "Device password"
      class_option :verbose, type: :boolean, default: false, desc: "Enable verbose output"
      class_option :force_udp, type: :boolean, default: false, desc: "Use UDP instead of TCP"
      class_option :no_ping, type: :boolean, default: true, desc: "Skip ping check"
      class_option :encoding, type: :string, default: 'UTF-8', desc: "Character encoding"

      desc "info [IP]", "Get device information"
      def info(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']
        with_connection(ip, options) do |conn|
          # Get firmware version
          firmware_version = conn.get_firmware_version

          # Get device time
          device_time = conn.get_time

          # Display information
          if defined?(::Terminal) && defined?(::Terminal::Table) && HAS_TERMINAL_TABLE
            # Pretty table output
            table = ::Terminal::Table.new do |t|
              t.title = "Device Information"
              t << ['IP Address', ip]
              t << ['Port', options[:port]]
              t << ['Firmware Version', firmware_version]
              t << ['Device Time', device_time]
            end

            puts table
          else
            # Fallback plain text output
            puts "Device Information:"
            puts "IP Address: #{ip}"
            puts "Port: #{options[:port]}"
            puts "Firmware Version: #{firmware_version}"
            puts "Device Time: #{device_time}"
          end
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

      # Add aliases for common log commands
      desc "logs-today [IP]", "Get today's attendance logs"
      map "logs-today" => "logs"
      def logs_today(ip = nil)
        invoke :logs, [ip], today: true
      end

      desc "logs-yesterday [IP]", "Get yesterday's attendance logs"
      map "logs-yesterday" => "logs"
      def logs_yesterday(ip = nil)
        invoke :logs, [ip], yesterday: true
      end

      desc "logs-week [IP]", "Get this week's attendance logs"
      map "logs-week" => "logs"
      def logs_week(ip = nil)
        invoke :logs, [ip], week: true
      end

      desc "logs-month [IP]", "Get this month's attendance logs"
      map "logs-month" => "logs"
      def logs_month(ip = nil)
        invoke :logs, [ip], month: true
      end

      desc "logs-custom START_DATE END_DATE [IP]", "Get logs for a custom date range (YYYY-MM-DD)"
      def logs_custom(start_date, end_date, ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']
        invoke :logs, [ip], start_date: start_date, end_date: end_date
      end

      desc "logs [IP]", "Get all attendance logs"
      def logs(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']
        with_connection(ip, options) do |conn|
          puts "Getting attendance logs..."
          logs = conn.get_attendance_logs

          # Filter logs based on options
          if options[:today]
            today = Date.today
            logs = filter_logs_by_date(logs, today, today)
            title = "Today's Attendance Logs (#{today})"
          elsif options[:yesterday]
            yesterday = Date.today - 1
            logs = filter_logs_by_date(logs, yesterday, yesterday)
            title = "Yesterday's Attendance Logs (#{yesterday})"
          elsif options[:week]
            today = Date.today
            start_of_week = today - today.wday
            logs = filter_logs_by_date(logs, start_of_week, today)
            title = "This Week's Attendance Logs (#{start_of_week} to #{today})"
          elsif options[:month]
            today = Date.today
            start_of_month = Date.new(today.year, today.month, 1)
            logs = filter_logs_by_date(logs, start_of_month, today)
            title = "This Month's Attendance Logs (#{start_of_month} to #{today})"
          elsif options[:start_date] && options[:end_date]
            begin
              start_date = Date.parse(options[:start_date])
              end_date = Date.parse(options[:end_date])
              logs = filter_logs_by_date(logs, start_date, end_date)
              title = "Attendance Logs (#{start_date} to #{end_date})"
            rescue ArgumentError
              puts "Error: Invalid date format. Please use YYYY-MM-DD format."
              return
            end
          else
            title = "All Attendance Logs"
          end

          display_logs(logs, title)
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

      desc "test-voice [IP]", "Test the device voice"
      map "test-voice" => :test_voice
      def test_voice(ip = nil)
        # Use IP from options if not provided as argument
        ip ||= options[:ip] || @config['ip']
        with_connection(ip, options) do |conn|
          puts "Testing device voice..."
          result = conn.test_voice
          puts "✓ Voice test command sent successfully!" if result
        end
      end

      desc "config", "Show current configuration"
      def config
        if defined?(::Terminal) && defined?(::Terminal::Table) && HAS_TERMINAL_TABLE
          table = ::Terminal::Table.new do |t|
            t.title = "RBZK Configuration"
            @config.to_h.each do |key, value|
              t << [key, value]
            end
          end
          puts table
        else
          puts "RBZK Configuration:"
          @config.to_h.each do |key, value|
            puts "#{key}: #{value}"
          end
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
        puts "✓ Configuration updated: #{key} = #{typed_value}"
      end

      desc "config-reset", "Reset configuration to defaults"
      def config_reset
        if yes?("Are you sure you want to reset all configuration to defaults? (y/N)")
          FileUtils.rm_f(@config.default_config_file)
          @config = Config.new
          puts "✓ Configuration reset to defaults"
        else
          puts "Operation cancelled"
        end
      end

      private

      def with_connection(ip, options)
        # Merge command-line options with configuration
        # Command-line options take precedence over configuration
        connection_options = {
          port: options[:port] || @config['port'],
          timeout: options[:timeout] || @config['timeout'],
          password: options[:password] || @config['password'],
          verbose: options.key?(:verbose) ? options[:verbose] : @config['verbose'],
          omit_ping: options.key?(:no_ping) ? options[:no_ping] : @config['no_ping'],
          force_udp: options.key?(:force_udp) ? options[:force_udp] : @config['force_udp'],
          encoding: options[:encoding] || @config['encoding']
        }

        puts "Connecting to ZKTeco device at #{ip}:#{connection_options[:port]}..."
        puts "Please ensure the device is powered on and connected to the network."

        zk = RBZK::ZK.new(
          ip,
          port: connection_options[:port],
          timeout: connection_options[:timeout],
          password: connection_options[:password],
          verbose: connection_options[:verbose],
          omit_ping: connection_options[:omit_ping],
          force_udp: connection_options[:force_udp],
          encoding: connection_options[:encoding]
        )

        conn = nil
        begin
          conn = zk.connect

          if conn.connected?
            puts "✓ Connected successfully!"
            yield conn
          else
            puts "✗ Connection failed!"
          end
        rescue RBZK::ZKNetworkError => e
          puts "✗ Network Error: #{e.message}"
          puts "Please check that the device is powered on and connected to the network."
          puts "Also verify that the IP address and port are correct."
        rescue RBZK::ZKErrorResponse => e
          puts "✗ Device Error: #{e.message}"
          puts "The device returned an error response. This might be due to:"
          puts "- Incorrect password"
          puts "- Device is busy or in an error state"
          puts "- Command not supported by this device model"
        rescue => e
          puts "✗ Unexpected Error: #{e.message}"
          puts "An unexpected error occurred while communicating with the device."
          puts e.backtrace.join("\n") if options[:verbose]
        ensure
          if conn && conn.connected?
            puts "\nDisconnecting from device..."
            conn.disconnect
            puts "✓ Disconnected"
          end
        end
      end

      def filter_logs_by_date(logs, start_date, end_date)
        logs.select do |log|
          log_date = log.timestamp.to_date
          log_date >= start_date && log_date <= end_date
        end
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
        when 2 then "Admin"
        when 3 then "Super Admin"
        else "Unknown (#{privilege})"
        end
      end

      def display_logs(logs, title = "Attendance Logs")
        if logs && !logs.empty?
          puts "✓ Found #{logs.size} attendance logs:"

          # Create a table for the first 20 logs
          display_logs = logs.first(20)

          if defined?(::Terminal) && defined?(::Terminal::Table) && HAS_TERMINAL_TABLE
            # Pretty table output
            table = ::Terminal::Table.new do |t|
              t.title = "#{title} (showing #{display_logs.size} of #{logs.size})"
              t.headings = ['User ID', 'Timestamp', 'Status', 'Punch']

              display_logs.each do |log|
                t << [
                  log.user_id,
                  log.timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                  format_status(log.status),
                  log.punch
                ]
              end
            end

            puts table
          else
            # Fallback plain text output
            puts "#{title} (showing #{display_logs.size} of #{logs.size}):"
            puts "#{'User ID'.ljust(10)} | #{'Timestamp'.ljust(19)} | #{'Status'.ljust(15)} | Punch"
            puts "-" * 60

            display_logs.each do |log|
              puts "#{log.user_id.to_s.ljust(10)} | #{log.timestamp.strftime('%Y-%m-%d %H:%M:%S').ljust(19)} | #{format_status(log.status).ljust(15)} | #{log.punch}"
            end
          end

          if logs.size > 20
            puts "... and #{logs.size - 20} more records"
          end

          # Show statistics
          today = Date.today
          today_logs = logs.select { |log| log.timestamp.to_date == today }

          puts "\nStatistics:"

          if defined?(::Terminal) && defined?(::Terminal::Table) && HAS_TERMINAL_TABLE
            stats_table = ::Terminal::Table.new do |t|
              t << ['Total Records', logs.size]
              t << ['Today\'s Records', today_logs.size]
              t << ['Unique Users', logs.map(&:user_id).uniq.size]

              if logs.size > 0
                t << ['Date Range', "#{logs.map(&:timestamp).min.strftime('%Y-%m-%d')} to #{logs.map(&:timestamp).max.strftime('%Y-%m-%d')}"]
              end
            end

            puts stats_table
          else
            puts "Total Records: #{logs.size}"
            puts "Today's Records: #{today_logs.size}"
            puts "Unique Users: #{logs.map(&:user_id).uniq.size}"

            if logs.size > 0
              puts "Date Range: #{logs.map(&:timestamp).min.strftime('%Y-%m-%d')} to #{logs.map(&:timestamp).max.strftime('%Y-%m-%d')}"
            end
          end
        else
          puts "✓ No attendance logs found"
        end
      end

      def display_users(users)
        if users && !users.empty?
          puts "✓ Found #{users.size} users:"

          # Create a table for the users
          display_users = users.first(20)

          if defined?(::Terminal) && defined?(::Terminal::Table) && HAS_TERMINAL_TABLE
            # Pretty table output
            table = ::Terminal::Table.new do |t|
              t.title = "Users (showing #{display_users.size} of #{users.size})"
              t.headings = ['UID', 'User ID', 'Name', 'Privilege', 'Password', 'Group ID', 'Card']

              display_users.each do |user|
                t << [
                  user.uid,
                  user.user_id,
                  user.name,
                  format_privilege(user.privilege),
                  (user.password.nil? || user.password.empty?) ? '(none)' : '********',
                  user.group_id,
                  user.card.zero? ? '(none)' : user.card.to_s
                ]
              end
            end

            puts table
          else
            # Fallback plain text output
            puts "Users (showing #{display_users.size} of #{users.size}):"
            puts "#{'UID'.ljust(5)} | #{'User ID'.ljust(10)} | #{'Name'.ljust(20)} | #{'Privilege'.ljust(12)} | #{'Password'.ljust(10)} | #{'Group ID'.ljust(10)} | Card"
            puts "-" * 90

            display_users.each do |user|
              puts "#{user.uid.to_s.ljust(5)} | #{user.user_id.to_s.ljust(10)} | #{user.name.to_s.ljust(20)} | #{format_privilege(user.privilege).ljust(12)} | #{((user.password.nil? || user.password.empty?) ? '(none)' : '********').ljust(10)} | #{user.group_id.to_s.ljust(10)} | #{user.card.zero? ? '(none)' : user.card.to_s}"
            end
          end

          if users.size > 20
            puts "... and #{users.size - 20} more users"
          end

          # Show statistics
          puts "\nStatistics:"

          if defined?(::Terminal) && defined?(::Terminal::Table) && HAS_TERMINAL_TABLE
            stats_table = ::Terminal::Table.new do |t|
              t << ['Total Users', users.size]
              t << ['Admins', users.count { |u| u.privilege >= 2 }]
              t << ['Regular Users', users.count { |u| u.privilege < 2 }]
              t << ['With Password', users.count { |u| u.password && !u.password.empty? }]
              t << ['With Card', users.count { |u| u.card != 0 }]
            end

            puts stats_table
          else
            puts "Total Users: #{users.size}"
            puts "Admins: #{users.count { |u| u.privilege >= 2 }}"
            puts "Regular Users: #{users.count { |u| u.privilege < 2 }}"
            puts "With Password: #{users.count { |u| u.password && !u.password.empty? }}"
            puts "With Card: #{users.count { |u| u.card != 0 }}"
          end
        else
          puts "✓ No users found"
        end
      end
    end
  end
end
