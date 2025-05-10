# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'date'

module RBZK
  # Helper class for ZK (like Python's ZK_helper)
  class ZKHelper
    def initialize(ip, port = 4370)
      @ip = ip
      @port = port
      @address = [ip, port]
    end

    def test_ping
      # Like Python's test_ping
      begin
        system("ping -c 1 -W 5 #{@ip} > /dev/null 2>&1")
        return $?.success?
      rescue => e
        return false
      end
    end

    def test_tcp
      # Match Python's test_tcp method exactly
      begin
        # Create socket like Python's socket(AF_INET, SOCK_STREAM)
        client = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM)

        # Set timeout like Python's settimeout(10)
        client.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [10, 0].pack('l_*'))

        # Use connect_ex like Python (returns error code instead of raising exception)
        sockaddr = Socket.pack_sockaddr_in(@port, @ip)
        begin
          client.connect(sockaddr)
          result = 0  # Success, like Python's connect_ex returns 0 on success
        rescue Errno::EISCONN
          # Already connected
          result = 0
        rescue => e
          # Connection failed, return error code
          result = e.errno || 1
        end

        # Close socket
        client.close

        # Return result code (0 = success, non-zero = error)
        return result
      rescue => e
        # Something went wrong with socket creation
        return e.errno || 1
      end
    end
  end

  class ZK
    include RBZK::Constants

    def initialize(ip, port: 4370, timeout: 60, password: 0, force_udp: false, omit_ping: false, verbose: false, encoding: 'UTF-8')
      # Match Python's __init__ method
      RBZK::User.encoding = encoding
      @address = [ ip, port ]

      @ip = ip
      @port = port
      @timeout = timeout
      @password = password
      @force_udp = force_udp
      @omit_ping = omit_ping
      @verbose = verbose
      @encoding = encoding

      # Set TCP mode based on force_udp (like Python's self.tcp = not force_udp)
      @tcp = !force_udp

      # Socket will be created during connect
      @socket = nil

      # Initialize session variables (like Python)
      @session_id = 0
      @reply_id = USHRT_MAX - 1
      @data_recv = nil
      @data = nil
      @connected = false
      @next_uid = 1

      # Storage for user and attendance data
      @users = {}
      @attendances = []
      @fingers = {}
      @tcp_header_size = 8

      # Create helper for ping and TCP tests
      @helper = ZKHelper.new(ip, port)

      if @verbose
        puts "ZK instance created for device at #{@ip}:#{@port}"
        puts "Using #{@force_udp ? 'UDP' : 'TCP'} mode"
      end
    end

    # Remove this method as we now use the helper class
    # def test_tcp
    # end

    def connect
      # Match Python's connect method
      return self if @connected

      # Skip ping check if requested (like Python's ommit_ping)
      if !@omit_ping && !@helper.test_ping
        raise RBZK::ZKNetworkError, "Can't reach device (ping #{@ip})"
      end

      # Test TCP connection (like Python's connect)
      if !@force_udp && @helper.test_tcp == 0
        # Default user packet size for ZK8
        @user_packet_size = 72
      end

      # Create socket (like Python's __create_socket)
      create_socket

      # Reset session variables (like Python's connect)
      @session_id = 0
      @reply_id = USHRT_MAX - 1

      # Send connect command (like Python's connect)
      if @verbose
        puts "Sending connect command to device"
      end

      begin
        # Send connect command (like Python's connect)
        # In Python: cmd_response = self.__send_command(const.CMD_CONNECT)
        # No command string is needed for the connect command
        cmd_response = send_command(CMD_CONNECT)

        # Update session ID from header (like Python's connect)
        @session_id = @header[2]

        # Authenticate if needed (like Python's connect)
        if cmd_response[:code] == CMD_ACK_UNAUTH
          if @verbose
            puts "try auth"
          end

          # Create auth command string (like Python's make_commkey)
          command_string = make_commkey(@password, @session_id)

          # Send auth command
          cmd_response = send_command(CMD_AUTH, command_string)
        end

        # Check response status (like Python's connect)
        if cmd_response[:status]
          @connected = true
          return self
        else
          if cmd_response[:code] == CMD_ACK_UNAUTH
            raise RBZK::ZKErrorResponse, "Unauthenticated"
          end

          if @verbose
            puts "Connect error response: #{cmd_response[:code]}"
          end

          raise RBZK::ZKErrorResponse, "Invalid response: Can't connect"
        end
      rescue => e
        @connected = false
        if @verbose
          puts "Connection error: #{e.message}"
        end
        raise e
      end
    end

    def connected?
      @connected
    end

    def disconnect
      return unless @connected

      self.send_command(CMD_EXIT)
      self.recv_reply

      @connected = false
      @socket.close if @socket
      @tcp.close if @tcp

      @socket = nil
      @tcp = nil

      true
    end

    def enable_device
      self.send_command(CMD_ENABLEDEVICE)
      self.recv_reply
      true
    end

    def disable_device
      self.send_command(CMD_DISABLEDEVICE)
      self.recv_reply
      true
    end

    def get_firmware_version
      self.send_command(CMD_GET_VERSION)
      reply = self.recv_reply

      if reply && reply.size >= 8
        version = reply[8..-1].unpack('H*')[0]
        return "#{version[1]}.#{version[3]}.#{version[5]}.#{version[7]}"
      end

      nil
    end

    def restart
      self.send_command(CMD_RESTART)
      self.recv_reply
      true
    end

    def poweroff
      self.send_command(CMD_POWEROFF)
      self.recv_reply
      true
    end

    def test_voice
      self.send_command(CMD_TESTVOICE)
      self.recv_reply
      true
    end

    def get_users
      users = []

      if @verbose
        puts "Requesting user data from device"
      end

      # Send command to prepare data
      response = self.send_command(CMD_PREPARE_DATA, [ FCT_USER ].pack('C'))

      if !response || !response[:status]
        if @verbose
          puts "Error: Failed to prepare user data, response: #{response.inspect}"
        end
        return users
      end

      # Get data size
      data_size = self.recv_long

      if @verbose
        puts "Expecting #{data_size} bytes of user data"
      end

      # Get user data
      users_data = self.recv_chunk(data_size)

      if users_data && !users_data.empty?
        if @verbose
          puts "Received #{users_data.size} bytes of user data"
          puts "User data: #{users_data.bytes.map { |b| b.to_s(16).rjust(2, '0') }.join(' ')}" if @verbose
        end

        offset = 0
        while offset < data_size
          if data_size - offset >= 28
            user_info = users_data[offset..offset + 27] # 28 bytes per user record

            # Unpack user data
            # Format: uid(2), user_id(9), name(24), privilege(1), password(1), group_id(1), card(2)
            uid, user_id_raw, name_raw, privilege, password_raw, group_id, card = user_info.unpack('S<A9A24CCA14S<')

            # Clean up strings
            user_id = user_id_raw.strip.gsub(/\x00/, '')
            name = name_raw.strip.gsub(/\x00/, '')
            password = password_raw.strip.gsub(/\x00/, '')

            if @verbose
              puts "Found user: UID=#{uid}, ID=#{user_id}, Name=#{name}, Privilege=#{privilege}"
            end

            users << RBZK::User.new(uid, user_id, name, privilege, password, group_id, card)
          else
            if @verbose
              puts "Warning: Incomplete user record at offset #{offset}"
            end
          end

          offset += 28 # Move to next user record
        end
      else
        if @verbose
          puts "No user data received from device"
        end
      end

      users
    end

    def get_attendance_logs
      logs = []

      self.send_command(CMD_PREPARE_DATA, [ FCT_ATTLOG ].pack('C'))
      self.recv_reply

      data_size = self.recv_long
      logs_data = self.recv_chunk(data_size)

      if logs_data && !logs_data.empty?
        offset = 0
        while offset < data_size
          if data_size - offset >= 16
            log_info = logs_data[offset..offset + 16]
            user_id, timestamp, status, punch, uid = log_info.unpack('S<L<CCS<')

            time = Time.at(timestamp)
            logs << RBZK::Attendance.new(user_id, time, status, punch, uid)
          end

          offset += 16
        end
      end

      logs
    end

    def get_time
      self.send_command(CMD_GET_TIME)
      reply = self.recv_reply

      if reply && reply.size >= 8
        time_data = reply[8..-1].unpack('S<5')
        year, month, day, hour, minute, second = time_data
        second = 0 if time_data.size < 6

        return Time.new(year, month, day, hour, minute, second)
      end

      nil
    end

    def set_time(time = nil)
      time ||= Time.now

      data = [ time.year, time.month, time.day, time.hour, time.min, time.sec ].pack('S<6')
      self.send_command(CMD_SET_TIME, data)
      self.recv_reply

      true
    end

    def clear_attendance_logs
      self.send_command(CMD_CLEAR_ATTLOG)
      self.recv_reply
      true
    end

    def clear_data
      self.send_command(CMD_CLEAR_DATA)
      self.recv_reply
      true
    end

    def get_free_sizes
      self.send_command(CMD_GET_FREE_SIZES)
      reply = self.recv_reply

      if reply && reply.size >= 8
        sizes_data = reply[8..-1].unpack('S<*')

        return {
          users: sizes_data[0],
          fingers: sizes_data[2],
          capacity: sizes_data[4],
          logs: sizes_data[6],
          passwords: sizes_data[8]
        }
      end

      nil
    end

    def get_templates
      fingers = []

      self.send_command(CMD_PREPARE_DATA, [ FCT_FINGERTMP ].pack('C'))
      self.recv_reply

      data_size = self.recv_long
      templates_data = self.recv_chunk(data_size)

      if templates_data && !templates_data.empty?
        offset = 0
        while offset < data_size
          if data_size - offset >= 608
            template_data = templates_data[offset..offset + 608]
            uid, fid, valid, template = template_data.unpack('S<S<C a*')

            fingers << RBZK::Finger.new(uid, fid, valid, template)
          end

          offset += 608
        end
      end

      fingers
    end

    def get_user_template(uid, finger_id)
      self.send_command(CMD_GET_USERTEMP, [ uid, finger_id ].pack('S<S<'))
      reply = self.recv_reply

      if reply && reply.size >= 8
        template_data = reply[8..-1]
        valid = template_data[0].ord
        template = template_data[1..-1]

        return RBZK::Finger.new(uid, finger_id, valid, template)
      end

      nil
    end

    private

    def create_socket
      # Match Python's __create_socket method exactly
      if @verbose
        puts "Creating socket for #{@tcp ? 'TCP' : 'UDP'} connection"
      end

      if @tcp
        # Create TCP socket (like Python's socket(AF_INET, SOCK_STREAM))
        @socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM)
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [@timeout, 0].pack('l_*'))

        # Connect with connect_ex (like Python's connect_ex)
        begin
          # Use connect_ex like Python (returns error code instead of raising exception)
          sockaddr = Socket.pack_sockaddr_in(@port, @ip)
          @socket.connect_nonblock(sockaddr)
          if @verbose
            puts "TCP socket connected successfully"
          end
        rescue IO::WaitWritable
          # Socket is in progress of connecting
          ready = IO.select(nil, [@socket], nil, @timeout)
          if ready
            begin
              @socket.connect_nonblock(sockaddr)
            rescue Errno::EISCONN
              # Already connected, which is fine
              if @verbose
                puts "TCP socket connected successfully"
              end
            rescue => e
              # Connection failed
              if @verbose
                puts "TCP socket connection failed: #{e.message}"
              end
              raise e
            end
          else
            # Connection timed out
            if @verbose
              puts "TCP socket connection timed out"
            end
            raise Errno::ETIMEDOUT
          end
        rescue Errno::EISCONN
          # Already connected, which is fine
          if @verbose
            puts "TCP socket already connected"
          end
        end
      else
        # Create UDP socket (like Python's socket(AF_INET, SOCK_DGRAM))
        @socket = Socket.new(Socket::AF_INET, Socket::SOCK_DGRAM)
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [@timeout, 0].pack('l_*'))

        if @verbose
          puts "UDP socket created successfully"
        end
      end
    rescue => e
      if @verbose
        puts "Socket creation failed: #{e.message}"
      end
      raise RBZK::ZKNetworkError, "Failed to create socket: #{e.message}"
    end

    def test_tcp_top(packet)
      # Match Python's __test_tcp_top method exactly
      # In Python: if len(packet)<=8: return 0
      return 0 if packet.nil? || packet.size <= 8

      # Ensure packet is a binary string
      packet = packet.to_s.b

      # In Python: tcp_header = unpack('<HHI', packet[:8])
      # In Ruby: tcp_header = packet[0..7].unpack('S<S<I<')
      tcp_header = packet[0..7].unpack('S<S<I<')

      # In Python: if tcp_header[0] == const.MACHINE_PREPARE_DATA_1 and tcp_header[1] == const.MACHINE_PREPARE_DATA_2: return tcp_header[2]
      if tcp_header[0] == MACHINE_PREPARE_DATA_1 && tcp_header[1] == MACHINE_PREPARE_DATA_2
        return tcp_header[2]
      end

      # In Python: return 0
      return 0
    end

    def ping
      if @verbose
        puts "Pinging device at #{@ip}:#{@port}..."
      end

      # Try TCP ping first
      begin
        Timeout.timeout(5) do
          s = TCPSocket.new(@ip, @port)
          s.close
          if @verbose
            puts "TCP ping successful"
          end
          return true
        end
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        if @verbose
          puts "TCP ping failed: #{e.message}"
        end
      end

      # If TCP ping fails, try UDP ping
      begin
        udp_socket = UDPSocket.new
        udp_socket.connect(@ip, @port)
        udp_socket.send("\x00" * 8, 0)
        ready = IO.select([udp_socket], nil, nil, 5)

        if ready
          if @verbose
            puts "UDP ping successful"
          end
          udp_socket.close
          return true
        else
          if @verbose
            puts "UDP ping timed out"
          end
          udp_socket.close
          return false
        end
      rescue => e
        if @verbose
          puts "UDP ping failed: #{e.message}"
        end
        return false
      end
    end

    def calculate_checksum(buf)
      # Match Python's __create_checksum method exactly
      # In Python:
      # def __create_checksum(self, p):
      #     l = len(p)
      #     checksum = 0
      #     while l > 1:
      #         checksum += unpack('H', pack('BB', p[0], p[1]))[0]
      #         p = p[2:]
      #         if checksum > const.USHRT_MAX:
      #             checksum -= const.USHRT_MAX
      #         l -= 2
      #     if l:
      #         checksum = checksum + p[-1]
      #     while checksum > const.USHRT_MAX:
      #         checksum -= const.USHRT_MAX
      #     checksum = ~checksum
      #     while checksum < 0:
      #         checksum += const.USHRT_MAX
      #     return pack('H', checksum)

      # Get the length of the buffer
      l = buf.size
      checksum = 0
      i = 0

      # Process pairs of bytes
      while l > 1
        # In Python: checksum += unpack('H', pack('BB', p[0], p[1]))[0]
        # This is combining two bytes into a 16-bit value (little-endian)
        checksum += (buf[i] | (buf[i+1] << 8))
        i += 2

        # In Python: if checksum > const.USHRT_MAX: checksum -= const.USHRT_MAX
        # Handle overflow immediately after each addition
        if checksum > USHRT_MAX
          checksum -= USHRT_MAX
        end

        l -= 2
      end

      # Handle odd byte if present
      # In Python: if l: checksum = checksum + p[-1]
      if l > 0
        checksum += buf[i]
      end

      # Handle overflow
      # In Python: while checksum > const.USHRT_MAX: checksum -= const.USHRT_MAX
      while checksum > USHRT_MAX
        checksum -= USHRT_MAX
      end

      # Bitwise complement
      # In Python: checksum = ~checksum
      checksum = ~checksum

      # Handle negative values
      # In Python: while checksum < 0: checksum += const.USHRT_MAX
      while checksum < 0
        checksum += USHRT_MAX
      end

      # Return the checksum
      checksum
    end

    # Helper method to debug binary data in both Python and Ruby formats
    def debug_binary(name, data)
      return unless @verbose
      puts "#{name} (hex): #{data.bytes.map { |b| "\\x#{b.to_s(16).rjust(2, '0')}" }.join('')}"
      puts "#{name} (Ruby): #{data.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
    end

    def create_tcp_top(packet)
      # Match Python's __create_tcp_top method exactly
      puts "\n*** DEBUG: create_tcp_top called ***" if @verbose
      length = packet.size
      # In Python: pack('<HHI', const.MACHINE_PREPARE_DATA_1, const.MACHINE_PREPARE_DATA_2, length)
      # In Ruby: [MACHINE_PREPARE_DATA_1, MACHINE_PREPARE_DATA_2, length].pack('S<S<I<')
      top = [MACHINE_PREPARE_DATA_1, MACHINE_PREPARE_DATA_2, length].pack('S<S<I<')

      if @verbose
        puts "\nTCP header components:"
        puts "  MACHINE_PREPARE_DATA_1: 0x#{MACHINE_PREPARE_DATA_1.to_s(16)} (#{MACHINE_PREPARE_DATA_1}) - should be 'PP' in ASCII"
        puts "  MACHINE_PREPARE_DATA_2: 0x#{MACHINE_PREPARE_DATA_2.to_s(16)} (#{MACHINE_PREPARE_DATA_2}) - should be '\\x82\\x7d' in hex"
        puts "  packet length: #{length}"

        # Show the expected Python representation
        expected_python_header = "PP\\x82\\x7d\\x#{(length & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 8) & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 16) & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 24) & 0xFF).to_s(16).rjust(2, '0')}"
        puts "  Expected Python header: #{expected_python_header}"

        # Show the actual bytes of the constants
        puts "  MACHINE_PREPARE_DATA_1 bytes: #{[MACHINE_PREPARE_DATA_1].pack('S<').bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
        puts "  MACHINE_PREPARE_DATA_2 bytes: #{[MACHINE_PREPARE_DATA_2].pack('S<').bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"

        debug_binary("TCP header only", top) # This is just the 8-byte header
        debug_binary("Full TCP packet (what Python calls 'top')", top + packet) # This is what we return
      end

      # Print debug info right before returning
      if @verbose
        puts "\n*** FINAL TCP PACKET DEBUG ***"
        puts "In both Python and Ruby, the variable 'top' is just the TCP header, but the method returns 'top + packet':"
        puts "TCP header format: b'PP\\x82\\x7d\\x#{(length & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 8) & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 16) & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 24) & 0xFF).to_s(16).rjust(2, '0')}'"
        puts "Return value format (top + packet): TCP header + command packet"
        puts "Ruby 'top + packet' format: #{(top + packet).bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
        puts "Hex format: #{(top + packet).bytes.map { |b| "\\x#{b.to_s(16).rjust(2, '0')}" }.join('')}"
      end

      # Return top + packet (like Python's return top + packet)
      result = top + packet

      if @verbose
        puts "\n*** SUPER EXPLICIT DEBUG ***"
        puts "top bytes: #{top.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
        puts "packet bytes: #{packet.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
        puts "result bytes: #{result.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
        puts "result size: #{result.size} bytes"
      end

      result
    end

    def create_header(command, command_string = "".b, session_id = 0, reply_id = 0)
      # Match Python's __create_header method exactly
      # In Python:
      # def __create_header(self, command, command_string, session_id, reply_id):
      #     buf = pack('<4H', command, 0, session_id, reply_id) + command_string
      #     buf = unpack('8B' + '%sB' % len(command_string), buf)
      #     checksum = unpack('H', self.__create_checksum(buf))[0]
      #     reply_id += 1
      #     if reply_id >= const.USHRT_MAX:
      #         reply_id -= const.USHRT_MAX
      #     buf = pack('<4H', command, checksum, session_id, reply_id)
      #     return buf + command_string

      # Ensure command_string is a binary string
      command_string = command_string.to_s.b

      # Step 1: Create initial header and combine with command_string
      # In Python: buf = pack('<4H', command, 0, session_id, reply_id) + command_string
      buf = [command, 0, session_id, reply_id].pack('S<4') + command_string

      # Step 2: Convert to bytes array for checksum calculation
      # In Python: buf = unpack('8B' + '%sB' % len(command_string), buf)
      # This unpacks the buffer into individual bytes
      # In Ruby, we can use String#bytes to get an array of bytes
      buf_bytes = buf.bytes  # Convert the entire buffer to bytes array, just like Python

      # Step 3: Calculate checksum
      # In Python: checksum = unpack('H', self.__create_checksum(buf))[0]
      checksum = calculate_checksum(buf_bytes)

      # Step 4: Update reply_id
      # In Python: reply_id += 1; if reply_id >= const.USHRT_MAX: reply_id -= const.USHRT_MAX
      reply_id += 1
      if reply_id >= USHRT_MAX
        reply_id -= USHRT_MAX
      end

      # Step 5: Create final header with updated values
      # In Python: buf = pack('<4H', command, checksum, session_id, reply_id)
      final_header = [command, checksum, session_id, reply_id].pack('S<4')

      # Step 6: Return final header + command_string
      # In Python: return buf + command_string
      result = final_header + command_string

      if @verbose
        puts "Header components:"
        puts "  Command: #{command}"
        puts "  Checksum: #{checksum}"
        puts "  Session ID: #{session_id}"
        puts "  Reply ID: #{reply_id}"

        if !command_string.empty?
          debug_binary("Command string", command_string)
        else
          puts "Command string: (empty)"
        end

        debug_binary("Initial header", [command, 0, session_id, reply_id].pack('S<4'))
        debug_binary("Final header", final_header)
        debug_binary("Final buffer (header + command_string)", result)
      end

      result
    end

    def send_command(command, command_string = "".b, response_size = 8)
      # Match Python's __send_command method exactly

      # Check connection status (except for connect and auth commands)
      if command != CMD_CONNECT && command != CMD_AUTH && !@connected
        raise RBZK::ZKErrorConnection, "Instance are not connected."
      end

      # In Python, command_string is a bytes object (b'')
      # In Ruby, we use binary strings (ASCII-8BIT encoding)
      command_string = command_string.to_s.b

      if @verbose
        puts "command_string class: #{command_string.class}"
        puts "command_string encoding: #{command_string.encoding}"
        puts "command_string bytes: #{command_string.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
      end

      # Create command header (like Python's __create_header)
      buf = create_header(command, command_string, @session_id, @reply_id)

      if @verbose
        puts "\nSending command #{command} with session id #{@session_id} and reply id #{@reply_id}"
      end

      begin
        puts "\n*** DEBUG: Using #{@tcp ? 'TCP' : 'UDP'} mode ***" if @verbose
        if @tcp
          # Create TCP header (like Python's __create_tcp_top)
          puts "\n*** Before create_tcp_top ***" if @verbose
          puts "buf size: #{buf.size} bytes" if @verbose
          top = create_tcp_top(buf)
          puts "\n*** After create_tcp_top ***" if @verbose
          puts "top size: #{top.size} bytes" if @verbose

          if @verbose
            puts "\nSending TCP packet:"
            puts "Note: In send_command, 'top' variable contains the full packet (header + command packet)"
            puts "This is because create_tcp_top returns the full packet, not just the header"
            debug_binary("Command packet (buf)", buf)
            debug_binary("Full TCP packet (top)", top) # 'top' contains the full packet here
          end

          @socket.send(top, 0)
          @tcp_data_recv = @socket.recv(response_size + 8)
          @tcp_length = test_tcp_top(@tcp_data_recv)

          if @verbose
            puts "\nReceived TCP response:"
            debug_binary("TCP response", @tcp_data_recv)
          end

          if @tcp_length == 0
            raise RBZK::ZKNetworkError, "TCP packet invalid"
          end

          @header = @tcp_data_recv[8..15].unpack('S<4')
          @data_recv = @tcp_data_recv[8..-1]
        else
          # Send UDP packet
          @socket.send(buf, 0, @ip, @port)
          @data_recv = @socket.recv(response_size)
          @header = @data_recv[0..7].unpack('S<4')
        end
      rescue => e
        if @verbose
          puts "Connection error during send: #{e.message}"
        end
        raise RBZK::ZKNetworkError, e.message
      end

      # Process response (like Python's __send_command)
      @response = @header[0]
      @reply_id = @header[3]
      @data = @data_recv[8..-1]

      # Return response status (like Python's __send_command)
      if @response == CMD_ACK_OK || @response == CMD_PREPARE_DATA || @response == CMD_DATA
        return {
          status: true,
          code: @response
        }
      else
        return {
          status: false,
          code: @response
        }
      end
    end

    def recv_reply
      begin
        if @verbose
          puts "Waiting for TCP reply"
        end

        # Set a timeout for the read operation
        Timeout.timeout(5) do
          # Read TCP header (8 bytes)
          tcp_header = @tcp.read(8)
          return nil unless tcp_header && tcp_header.size >= 8

          # Parse TCP header
          tcp_format1, tcp_format2, tcp_length = tcp_header.unpack('S<S<I<')

          if @verbose
            puts "TCP header: format1=#{tcp_format1}, format2=#{tcp_format2}, length=#{tcp_length}"
          end

          # Verify TCP header format
          if tcp_format1 != MACHINE_PREPARE_DATA_1 || tcp_format2 != MACHINE_PREPARE_DATA_2
            if @verbose
              puts "Invalid TCP header format: #{tcp_format1}, #{tcp_format2}"
            end
            return nil
          end

          # Read command header (8 bytes)
          cmd_header = @tcp.read(8)
          return nil unless cmd_header && cmd_header.size >= 8

          # Parse command header
          command, checksum, session_id, reply_id = cmd_header.unpack('S<4')

          if @verbose
            puts "Command header: cmd=#{command}, checksum=#{checksum}, session=#{session_id}, reply=#{reply_id}"
          end

          # Calculate data size (TCP length - 8 bytes for command header)
          data_size = tcp_length - 8

          # Read data if available
          data = ""
          if data_size > 0
            if @verbose
              puts "Reading #{data_size} bytes of data"
            end

            # Read data in chunks to handle large responses (like Python implementation)
            remaining = data_size
            while remaining > 0
              chunk_size = [remaining, 4096].min
              chunk = @tcp.read(chunk_size)
              if chunk.nil? || chunk.empty?
                if @verbose
                  puts "Failed to read data chunk, got #{chunk.inspect}"
                end
                break
              end

              data += chunk
              remaining -= chunk.size

              if @verbose && remaining > 0
                puts "Read #{chunk.size} bytes, #{remaining} remaining"
              end
            end
          end

          # Store data for later use
          @data_recv = data

          # Update session ID
          @session_id = session_id

          # Check command type and handle accordingly (like Python implementation)
          if command == CMD_ACK_OK
            if @verbose
              puts "Received ACK_OK"
            end
            return cmd_header + data
          elsif command == CMD_ACK_ERROR
            if @verbose
              puts "Received ACK_ERROR"
            end
            return nil
          elsif command == CMD_ACK_DATA
            if @verbose
              puts "Received ACK_DATA"
            end
            if data_size > 0
              return cmd_header + data
            else
              return nil
            end
          else
            if @verbose
              puts "Received unknown command: #{command}"
            end
            return cmd_header + data
          end
        end
      rescue Timeout::Error => e
        if @verbose
          puts "Timeout waiting for response: #{e.message}"
        end
        raise RBZK::ZKErrorResponse, "Timeout waiting for response"
      rescue Errno::ECONNRESET, Errno::EPIPE => e
        if @verbose
          puts "Connection error during receive: #{e.message}"
        end
        raise RBZK::ZKNetworkError, "Connection error: #{e.message}"
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK => e
        if @verbose
          puts "Timeout waiting for response: #{e.message}"
        end
        raise RBZK::ZKErrorResponse, "Timeout waiting for response"
      end

      nil
    end

    def recv_long
      if @data_recv && @data_recv.size >= 4
        data = @data_recv[0..3]
        @data_recv = @data_recv[4..-1]
        return data.unpack('L<')[0]
      end

      0
    end

    def recv_chunk(size)
      if @verbose
        puts "Receiving chunk of #{size} bytes"
      end

      if @data_recv && @data_recv.size >= size
        data = @data_recv[0...size]
        @data_recv = @data_recv[size..-1]

        if @verbose
          puts "Received #{data.size} bytes from buffer"
        end

        return data
      end

      if @verbose
        puts "Warning: No data available in buffer"
      end

      # Return empty string if no data is available
      ''
    end

    def make_commkey(key, session_id, ticks = 50)
      key = key.to_i
      session_id = session_id.to_i
      k = 0

      32.times do |i|
        if (key & (1 << i)) != 0
          k = (k << 1 | 1)
        else
          k = k << 1
        end
      end

      k += session_id

      # Pack the integer into 4 bytes and unpack as individual bytes
      k_bytes = [ k ].pack('L<').unpack('C4')

      # XOR with 'ZKSO'
      k_bytes = [
        k_bytes[0] ^ 'Z'.ord,
        k_bytes[1] ^ 'K'.ord,
        k_bytes[2] ^ 'S'.ord,
        k_bytes[3] ^ 'O'.ord
      ]

      # Pack the bytes back into a string and unpack as 2 shorts
      k_shorts = k_bytes.pack('C4').unpack('S<2')

      # Swap the shorts
      k_shorts = [ k_shorts[1], k_shorts[0] ]

      # Get the low byte of ticks
      b = 0xff & ticks

      # Pack the shorts back into a string and unpack as 4 bytes
      k_bytes = k_shorts.pack('S<2').unpack('C4')

      # XOR with ticks and pack back into a string
      [ k_bytes[0] ^ b, k_bytes[1] ^ ticks, k_bytes[2] ^ b, k_bytes[3] ^ ticks ].pack('C4')
    end
  end
end
