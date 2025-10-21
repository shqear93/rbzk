# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'date'

module RBZK
  # Helper class for ZK
  class ZKHelper
    def initialize(ip, port = 4370)
      @ip = ip
      @port = port
      @address = [ ip, port ]
    end

    def test_ping
      begin
        Timeout.timeout(5) do
          s = TCPSocket.new(@ip, @port)
          s.close
          return true
        end
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
        return false
      rescue => e
        return false
      end
    end

    def test_tcp
      begin
        client = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM)
        client.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [ 10, 0 ].pack('l_*'))

        sockaddr = Socket.pack_sockaddr_in(@port, @ip)
        begin
          client.connect(sockaddr)
          result = 0 # Success code
        rescue Errno::EISCONN
          result = 0 # Already connected
        rescue => e
          # Some exceptions (e.g., Socket::ResolutionError) don't provide errno
          result = e.respond_to?(:errno) ? e.errno : 1 # Connection failed
        end

        client.close
        return result
      rescue => e
        # Some exceptions (e.g., Socket::ResolutionError) don't provide errno
        return e.respond_to?(:errno) ? e.errno : 1
      end
    end
  end

  class ZK
    include RBZK::Constants

    def initialize(ip, port: 4370, timeout: 60, password: 0, force_udp: false, omit_ping: false, verbose: false, encoding: 'UTF-8')
      # Initialize the ZK device connection
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

      @tcp = !force_udp
      @socket = nil

      # Initialize session variables
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

      # Initialize device info variables
      @users = 0
      @fingers = 0
      @records = 0
      @dummy = 0
      @cards = 0
      @fingers_cap = 0
      @users_cap = 0
      @rec_cap = 0
      @faces = 0
      @faces_cap = 0
      @fingers_av = 0
      @users_av = 0
      @rec_av = 0

      # Create helper for ping and TCP tests
      @helper = ZKHelper.new(ip, port)

      if @verbose
        puts "ZK instance created for device at #{@ip}:#{@port}"
        puts "Using #{@force_udp ? 'UDP' : 'TCP'} mode"
      end
    end

    def connect
      return self if @connected

      # Skip ping check if requested
      if !@omit_ping && !@helper.test_ping
        raise RBZK::ZKNetworkError, "Can't reach device (ping #{@ip})"
      end

      # Set user packet size if TCP connection is available
      if !@force_udp && @helper.test_tcp == 0
        @user_packet_size = 72 # Default for ZK8
      end

      create_socket

      # Reset session variables
      @session_id = 0
      @reply_id = USHRT_MAX - 1

      if @verbose
        puts "Sending connect command to device"
      end

      begin
        cmd_response = send_command(CMD_CONNECT)
        @session_id = @header[2]

        # Authenticate if needed
        if cmd_response[:code] == CMD_ACK_UNAUTH
          if @verbose
            puts "try auth"
          end

          command_string = make_commkey(@password, @session_id)
          cmd_response = send_command(CMD_AUTH, command_string)
        end

        # Check response status
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

      send_command(CMD_EXIT)
      recv_reply

      @connected = false
      @socket.close if @socket

      @socket = nil
      @tcp = nil

      true
    end

    def enable_device
      send_command(CMD_ENABLEDEVICE)
      recv_reply
      true
    end

    def disable_device
      cmd_response = self.send_command(CMD_DISABLEDEVICE)
      if cmd_response[:status]
        @is_enabled = false
        true
      else
        raise RBZK::ZKErrorResponse, "Can't disable device"
      end
    end

    def get_firmware_version
      command = CMD_GET_VERSION
      response_size = 1024
      response = send_command(command, '', response_size)

      if response && response[:status]
        firmware_version = @data.split("\x00")[0]
        firmware_version.to_s
      else
        raise RBZK::ZKErrorResponse, "Can't read firmware version"
      end
    end

    def get_serialnumber
      command = CMD_OPTIONS_RRQ
      command_string = "~SerialNumber\x00".b
      response_size = 1024

      response = send_command(command, command_string, response_size)

      if response && response[:status]
        serialnumber = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        serialnumber = serialnumber.gsub("=", "")
        serialnumber.to_s
      else
        raise RBZK::ZKErrorResponse, "Can't read serial number"
      end
    end

    def get_mac
      command = CMD_OPTIONS_RRQ
      command_string = "MAC\x00".b
      response_size = 1024

      response = send_command(command, command_string, response_size)

      if response && response[:status]
        mac = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        mac.to_s
      else
        raise RBZK::ZKErrorResponse, "Can't read MAC address"
      end
    end

    def get_device_name
      command = CMD_OPTIONS_RRQ
      command_string = "~DeviceName\x00".b
      response_size = 1024

      response = send_command(command, command_string, response_size)

      if response && response[:status]
        device = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        device.to_s
      else
        ''
      end
    end

    def get_face_version
      command = CMD_OPTIONS_RRQ
      command_string = "ZKFaceVersion\x00".b
      response_size = 1024

      response = send_command(command, command_string, response_size)

      if response && response[:status]
        version = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        version.to_i rescue 0
      else
        nil
      end
    end

    def get_extend_fmt
      command = CMD_OPTIONS_RRQ
      command_string = "~ExtendFmt\x00".b
      response_size = 1024

      response = send_command(command, command_string, response_size)

      if response && response[:status]
        fmt = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        fmt.to_i rescue 0
      else
        nil
      end
    end

    def get_platform
      command = CMD_OPTIONS_RRQ
      command_string = "~Platform\x00".b
      response_size = 1024

      response = send_command(command, command_string, response_size)

      if response && response[:status]
        platform = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        platform = platform.gsub("=", "")
        platform.to_s
      else
        raise RBZK::ZKErrorResponse, "Can't read platform name"
      end
    end

    def get_fp_version
      command = CMD_OPTIONS_RRQ
      command_string = "~ZKFPVersion\x00".b
      response_size = 1024

      response = send_command(command, command_string, response_size)

      if response && response[:status]
        version = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        version = version.gsub("=", "")
        version.to_i rescue 0
      else
        raise RBZK::ZKErrorResponse, "Can't read fingerprint version"
      end
    end

    def restart
      send_command(CMD_RESTART)
      recv_reply
      true
    end

    def poweroff
      send_command(CMD_POWEROFF)
      recv_reply
      true
    end

    def test_voice(index = 0)
      command_string = [ index ].pack('L<')
      response = send_command(CMD_TESTVOICE, command_string)

      if response && response[:status]
        true
      else
        false
      end
    end

    # Unlock the door
    # @param time [Integer] define delay in seconds
    # @return [Boolean] true if successful, raises exception otherwise
    def unlock(time = 3)
      command_string = [ time * 10 ].pack('L<')
      response = send_command(CMD_UNLOCK, command_string)

      if response && response[:status]
        true
      else
        raise RBZK::ZKErrorResponse, "Can't open door"
      end
    end

    # Get the lock state
    # @return [Boolean] true if door is open, false otherwise
    def get_lock_state
      response = send_command(CMD_DOORSTATE_RRQ)

      if response && response[:status]
        true
      else
        false
      end
    end

    # Write text to LCD
    # @param line_number [Integer] line number
    # @param text [String] text to write
    # @return [Boolean] true if successful, raises exception otherwise
    def write_lcd(line_number, text)
      command_string = [line_number, 0].pack('s<c') + ' ' + text.encode(@encoding, invalid: :replace, undef: :replace)
      response = self.send_command(CMD_WRITE_LCD, command_string)

      if response && response[:status]
        true
      else
        raise RBZK::ZKErrorResponse, "Can't write lcd"
      end
    end

    # Clear LCD
    # @return [Boolean] true if successful, raises exception otherwise
    def clear_lcd
      response = send_command(CMD_CLEAR_LCD)

      if response && response[:status]
        true
      else
        raise RBZK::ZKErrorResponse, "Can't clear lcd"
      end
    end

    # Refresh the device data
    # @return [Boolean] true if successful, raises exception otherwise
    def refresh_data
      response = send_command(CMD_REFRESHDATA)

      if response && response[:status]
        true
      else
        raise RBZK::ZKErrorResponse, "Can't refresh data"
      end
    end

    # Create or update user by uid
    # @param uid [Integer] user ID that are generated from device
    # @param name [String] name of the user
    # @param privilege [Integer] user privilege level (default or admin)
    # @param password [String] user password
    # @param group_id [String] group ID
    # @param user_id [String] your own user ID
    # @param card [Integer] card number
    # @return [Boolean] true if successful, raises exception otherwise
    def set_user(uid: nil, name: '', privilege: 0, password: '', group_id: '', user_id: '', card: 0)
      # If uid is not provided, use next_uid
      if uid.nil?
        ensure_user_metadata!
        uid = @next_uid
        user_id = @next_user_id if user_id.empty? && @next_user_id
      end

      # If uid is not provided, use next_uid
      user_id = uid.to_s if user_id.nil? || user_id.empty? # ZK6 needs uid2 == uid

      # Validate privilege
      privilege = USER_DEFAULT if privilege != USER_DEFAULT && privilege != USER_ADMIN
      privilege = privilege.to_i

      # Create command string based on user_packet_size
      if @user_packet_size == 28 # firmware == 6
        group_id = 0 if group_id.empty?

        begin
          command_string = [ uid, privilege ].pack('S<C') +
                           password.encode(@encoding, invalid: :replace, undef: :replace).ljust(5, "\x00")[0...5] +
                           name.encode(@encoding, invalid: :replace, undef: :replace).ljust(8, "\x00")[0...8] +
                           [ card.to_i, 0, group_id.to_i, 0, user_id.to_i ].pack('L<CS<S<L<')
        rescue StandardError => e
          puts "Error packing user: #{e.message}" if @verbose
          raise RBZK::ZKErrorResponse, "Can't pack user"
        end
      else
        # For other firmware versions
        name_pad = name.encode(@encoding, invalid: :replace, undef: :replace).ljust(24, "\x00")[0...24]
        card_str = [ card.to_i ].pack('L<')[0...4]
        command_string = "#{[ uid,
                              privilege ].pack('S<C')}#{password.encode(@encoding, invalid: :replace, undef: :replace).ljust(8,
                                                                                                                             "\x00")[0...8]}#{name_pad}#{card_str}\u0000#{group_id.encode(@encoding, invalid: :replace, undef: :replace).ljust(7,
                                                                                                                                                                                                                                               "\x00")[0...7]}\u0000#{user_id.encode(@encoding, invalid: :replace, undef: :replace).ljust(
                                                                                                                                                                                                                                                 24, "\x00"
                                                                                                                                                                                                                                               )[0...24]}"
      end

      # Send command
      response = send_command(CMD_USER_WRQ, command_string, 1024)

      if response && response[:status]
        # Update next_uid and next_user_id if necessary
        refresh_data
        @next_uid += 1 if @next_uid == uid
        @next_user_id = @next_uid.to_s if @next_user_id == user_id
        true
      else
        code = response[:code] if response
        data_msg = @data && !@data.empty? ? " Data: #{format_as_python_bytes(@data)}" : ''
        raise RBZK::ZKErrorResponse, "Can't set user (device response: #{code || 'NO_CODE'})#{data_msg}"
      end
    end

    def ensure_user_metadata!
      @next_uid ||= 1
      @next_user_id ||= '1'
      @user_packet_size ||= 28

      return unless @next_uid <= 1 || @next_user_id.nil? || @user_packet_size.nil?

      get_users
    rescue StandardError => e
      puts "Warning: unable to refresh user metadata before creating user: #{e.message}" if @verbose
      @next_uid ||= 1
      @next_user_id ||= '1'
      @user_packet_size ||= 28
    end
    private :ensure_user_metadata!

    # Delete user by uid
    # @param uid [Integer] user ID that are generated from device
    # @return [Boolean] true if successful, raises exception otherwise
    def delete_user(uid: 0)
      # Send command
      command_string = [ uid ].pack('S<')
      response = send_command(CMD_DELETE_USER, command_string)

      unless response && response[:status]
        raise RBZK::ZKErrorResponse, "Can't delete user. User not found or other error."
      end

      refresh_data
      # Update next_uid if necessary
      @next_uid = uid if uid == (@next_uid - 1)
      true
    end

    # Helper method to read data with buffer (ZK6: 1503)
    def read_with_buffer(command, fct = 0, ext = 0)

      if @verbose
        puts "Reading data with buffer: command=#{command}, fct=#{fct}, ext=#{ext}"
      end

      # Set max chunk size based on connection type
      max_chunk = @tcp ? 0xFFc0 : 16 * 1024

      # Pack the command parameters into a binary string
      # Format: 1 byte signed char, 2 byte short, 4 byte long, 4 byte long
      # All in little-endian format
      command_string = [ 1, command, fct, ext ].pack('cs<l<l<')

      if @verbose
        puts "Command string: #{python_format(command_string)}"
      end

      # Send the command to prepare the buffer
      response_size = 1024
      data = []
      start = 0
      response = self.send_command(CMD_PREPARE_BUFFER, command_string, response_size)

      if !response || !response[:status]
        raise RBZK::ZKErrorResponse, "Read with buffer not supported"
      end

      # Get data from the response
      data = @data

      if @verbose
        puts "Received #{data.size} bytes of data"
      end

      # Check if we need more data
      if response[:code] == CMD_DATA
        if @tcp
          if @verbose
            puts "DATA! is #{data.size} bytes, tcp length is #{@tcp_length}"
          end

          if data.size < (@tcp_length - 8)
            need = (@tcp_length - 8) - data.size
            if @verbose
              puts "need more data: #{need}"
            end

            # Receive more data to complete the buffer
            more_data = receive_raw_data(need)

            if @verbose
              puts "Read #{more_data.size} more bytes"
            end

            # Combine the data
            result = data + more_data
            return result, data.size + more_data.size
          else
            if @verbose
              puts "Enough data"
            end
            size = data.size
            return data, size
          end
        else
          size = data.size
          return data, size
        end
      end

      # Get the size from the first 4 bytes (unsigned long, little-endian)
      size = data[1..4].unpack1('L<')

      if @verbose
        puts "size fill be #{size}"
      end

      # Calculate chunks
      remain = size % max_chunk
      # Calculate number of full-sized packets (integer division)
      packets = (size - remain).div(max_chunk)

      if @verbose
        puts "rwb: ##{packets} packets of max #{max_chunk} bytes, and extra #{remain} bytes remain"
      end

      # Read chunks
      result_data = []
      start = 0

      packets.times do
        if @verbose
          puts "recieve chunk: prepare data size is #{max_chunk}"
        end
        chunk = read_chunk(start, max_chunk)
        result_data << chunk
        start += max_chunk
      end

      if remain > 0
        if @verbose
          puts "recieve chunk: prepare data size is #{remain}"
        end
        chunk = read_chunk(start, remain)
        result_data << chunk
        start += remain
      end

      # Free data (equivalent to Python's self.free_data())
      free_data

      if @verbose
        puts "_read w/chunk #{start} bytes"
      end

      # In Python: return b''.join(data), start
      result = result_data.join
      [ result, start ]
    end

    # Helper method to get data size from the current data
    def get_data_size
      if @data && @data.size >= 4
        size = @data[0...4].unpack('L<')[0]
        size
      else
        0
      end
    end

    # Helper method to receive TCP data
    def receive_tcp_data(data_recv, size)
      data = []
      tcp_length = test_tcp_top(data_recv)

      puts "tcp_length #{tcp_length}, size #{size}" if @verbose

      if tcp_length <= 0
        puts 'Incorrect tcp packet' if @verbose
        return nil, ''.b
      end

      if (tcp_length - 8) < size
        puts 'tcp length too small... retrying' if @verbose

        # Recursive call to handle smaller packet
        resp, bh = receive_tcp_data(data_recv, tcp_length - 8)
        data << resp if resp
        size -= resp.size

        puts "new tcp DATA packet to fill misssing #{size}" if @verbose

        # Get more data to fill missing
        data_recv = bh + @socket.recv(size + 16)

        puts "new tcp DATA starting with #{data_recv.size} bytes" if @verbose

        # Another recursive call with new data
        resp, bh = receive_tcp_data(data_recv, size)
        data << resp

        puts "for misssing #{size} recieved #{resp ? resp.size : 0} with extra #{bh.size}" if @verbose

        return data.join, bh
      end

      received = data_recv.size

      puts "received #{received}, size #{size}" if @verbose

      # In Python: response = unpack('HHHH', data_recv[8:16])[0]
      # This unpacks 4 shorts (8 bytes) but only uses the first one
      response = data_recv[8...16].unpack1('S<S<S<S<')

      if received >= (size + 32)
        if response == CMD_DATA
          resp = data_recv[16...(size + 16)]

          puts "resp complete len #{resp.size}" if @verbose

          return resp, data_recv[(size + 16)..]
        else
          puts "incorrect response!!! #{response}" if @verbose

          return nil, "".b
        end
      else
        puts "try DATA incomplete (actual valid #{received - 16})" if @verbose

        data << data_recv[16...(size + 16)]
        size -= received - 16
        broken_header = ''.b

        if size < 0
          broken_header = data_recv[size..]

          if @verbose
            puts "broken: #{broken_header.bytes.map { |b| format('%02x', b) }.join}"
          end
        end

        if size > 0
          data_recv = receive_raw_data(size)
          data << data_recv
        end

        [ data.join, broken_header ]
      end
    end

    # Helper method to receive a chunk (like Python's __recieve_chunk)
    def receive_chunk
      if @response == CMD_DATA
        if @tcp
          puts "_rc_DATA! is #{@data.size} bytes, tcp length is #{@tcp_length}" if @verbose

          if @data.size < (@tcp_length - 8)
            need = (@tcp_length - 8) - @data.size
            puts "need more data: #{need}" if @verbose
            more_data = receive_raw_data(need)
            return @data + more_data
          else
            puts "Enough data" if @verbose
            return @data
          end
        else
          puts "_rc len is #{@data.size}" if @verbose
          return @data
        end
      elsif @response == CMD_PREPARE_DATA
        data = []
        size = get_data_size

        puts "recieve chunk: prepare data size is #{size}" if @verbose

        if @tcp
          if @data.size >= (8 + size)
            data_recv = @data[8..]
          else
            # [80, 80, 130, 125, 92, 7, 0, 0, 221, 5, 142, 172, 0, 0, 4, 0, 80, 7, 0, 0, 1, 0, 14, 0, 0, 0, 0, 0, 0, 0, 0, 65, 98, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 2, 0, 14, 0, 0, 0, 0, 0, 0, 0, 0, 65, 110, 97, 115, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 50, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 83, 111, 110, 100, 111, 115, 44, 65, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 51, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 65, 116, 97, 0, 111, 115, 44, 65, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 52, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 77, 97, 121, 115, 0, 115, 44, 65, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 53, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 82, 97, 119, 97, 110, 0, 44, 65, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 54, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 74, 101, 110, 97, 110, 0, 44, 65, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 55, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 70, 97, 114, 97, 104, 0, 44, 65, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 56, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 83, 97, 98, 114, 101, 101, 110, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 57, 0, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 83, 97, 101, 101, 100, 0, 110, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 48, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 71, 111, 102, 114, 97, 110, 0, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 49, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 68, 97, 110, 105, 97, 0, 0, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 50, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 83, 97, 109, 105, 97, 0, 0, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 51, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 82, 101, 101, 109, 0, 0, 0, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 52, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 87, 97, 108, 97, 97, 0, 0, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 53, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 82, 97, 110, 101, 101, 109, 0, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 54, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 79, 108, 97, 0, 101, 109, 0, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 55, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 77, 97, 114, 97, 104, 0, 0, 0, 98, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 56, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 19, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 83, 111, 110, 100, 111, 115, 72, 65, 0, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 57, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 77, 111, 0, 100, 111, 115, 72, 65, 0, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 52, 53, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 21, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 65, 119, 115, 0, 111, 115, 72, 65, 0, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 49, 52, 54, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 22, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 83, 97, 109, 97, 114, 97, 0, 65, 0, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 52, 53, 50, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 23, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 84, 97, 115, 110, 101, 101, 109, 0, 0, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 50, 48, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 69, 115, 114, 97, 97, 0, 109, 0, 0, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 50, 49, 0, 0, 1, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 25, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 83, 97, 114, 97, 106, 0, 109, 0, 0, 117, 107, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 50, 49, 51, 53, 0, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 26, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 65, 108, 97, 97, 110, 97, 115, 115, 101, 114, 0, 104, 100, 97, 105, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 50, 50, 0, 53, 0, 0, 0, 0, 25, 0, 0, 0, 0, 254, 6, 119, 255, 255, 255, 255, 212, 10, 159, 127, 80, 80, 130, 125, 8, 0, 0, 0, 208, 7, 73, 81, 226, 166, 4, 0]
            data_recv = @data[8..] + @socket.recv(size + 32)
          end

          puts "data_recv: #{python_format(data_recv)}" if @verbose

          # hault_for_debuggg_DO_NOT_REMOVE
          resp, broken_header = receive_tcp_data(data_recv, size)
          data << resp if resp

          # get CMD_ACK_OK
          if broken_header.size < 16
            data_recv = broken_header + @socket.recv(16)
          else
            data_recv = broken_header
          end

          if data_recv.size < 16
            puts "trying to complete broken ACK #{data_recv.size} /16"
            if @verbose
              puts "data_recv: #{data_recv.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
            end
            data_recv += @socket.recv(16 - data_recv.size) # TODO: CHECK HERE_!
          end

          if !test_tcp_top(data_recv)
            if @verbose
              puts "invalid chunk tcp ACK OK"
            end
            return nil
          end

          # In Python: response = unpack('HHHH', data_recv[8:16])[0]
          # This unpacks 4 shorts (8 bytes) but only uses the first one
          # In Ruby, we need to use 'S<4' to unpack 4 shorts in little-endian format
          response = data_recv[8...16].unpack1('S<4')

          if response == CMD_ACK_OK
            if @verbose
              puts "chunk tcp ACK OK!"
            end
            return data.join
          end

          if @verbose
            puts "bad response #{format_as_python_bytes(data_recv)}"
            puts "data: #{data.map { |d| format_as_python_bytes(d) }.join(', ')}"
          end

          return nil
        else
          # Non-TCP implementation
          loop do
            data_recv = @socket.recv(1024 + 8)
            response = data_recv[0...8].unpack1('S<S<S<S<')

            if @verbose
              puts "# packet response is: #{response}"
            end

            if response == CMD_DATA
              data << data_recv[8..]
              size -= 1024
            elsif response == CMD_ACK_OK
              break
            else
              if @verbose
                puts "broken!"
              end
              break
            end

            if @verbose
              puts "still needs #{size}"
            end
          end

          return data.join
        end
      else
        if @verbose
          puts "invalid response #{@response}"
        end
        nil
      end
    end

    # Helper method to receive raw data (like Python's __recieve_raw_data)
    def receive_raw_data(size)
      data = []
      if @verbose
        puts "expecting #{size} bytes raw data"
      end

      while size > 0
        data_recv = @socket.recv(size)
        received = data_recv.size

        if @verbose
          puts "partial recv #{received}"
          if received < 100
            puts "   recv #{data_recv.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
          end
        end

        data << data_recv
        size -= received

        if @verbose
          puts "still need #{size}"
        end
      end

      data.join
    end

    # Helper method to clear buffer (like Python's free_data)
    def free_data
      command = CMD_FREE_DATA
      response = send_command(command)

      if response && response[:status]
        true
      else
        raise RBZK::ZKErrorResponse, "Can't free data"
      end
    end

    # Send data with buffer
    # @param buffer [String] data to send
    # @return [Boolean] true if successful, raises exception otherwise
    def send_with_buffer(buffer)
      max_chunk = 1024
      size = buffer.size
      free_data

      command = CMD_PREPARE_DATA
      command_string = [ size ].pack('L<')
      response = send_command(command, command_string)

      if !response || !response[:status]
        raise RBZK::ZKErrorResponse, "Can't prepare data"
      end

      remain = size % max_chunk
      packets = (size - remain) / max_chunk
      start = 0

      packets.times do
        send_chunk(buffer[start, max_chunk])
        start += max_chunk
      end

      send_chunk(buffer[start, remain]) if remain > 0

      true
    end

    # Send a chunk of data
    # @param command_string [String] data to send
    # @return [Boolean] true if successful, raises exception otherwise
    def send_chunk(command_string)
      command = CMD_DATA
      response = send_command(command, command_string)

      if response && response[:status]
        true
      else
        raise RBZK::ZKErrorResponse, "Can't send chunk"
      end
    end

    # Helper method to read a chunk of data
    def read_chunk(start, size)
      if @verbose
        puts "Reading chunk: start=#{start}, size=#{size}"
      end

      3.times do |_retries|
        # In Python: command = const._CMD_READ_BUFFER (which is 1504)
        # In Ruby, we should use CMD_READ_BUFFER (1504) instead of CMD_READFILE_DATA (81)
        command = 1504 # CMD_READ_BUFFER

        # In Python: command_string = pack('<ii', start, size)
        command_string = [ start, size ].pack('l<l<')

        # In Python: response_size = size + 32 if self.tcp else 1024 + 8
        response_size = @tcp ? size + 32 : 1024 + 8

        # In Python: cmd_response = self.__send_command(command, command_string, response_size)
        response = send_command(command, command_string, response_size)

        if !response || !response[:status]
          if @verbose
            puts "Failed to read chunk on attempt #{_retries + 1}"
          end
          next
        end

        # In Python: data = self.__recieve_chunk()
        data = receive_chunk

        if data
          if @verbose
            puts "Received chunk of #{data.size} bytes"
          end

          return data
        end
      end

      # If we get here, all retries failed
      raise RBZK::ZKErrorResponse, "can't read chunk #{start}:[#{size}]"
    end

    def get_users
      # Read sizes
      read_sizes

      puts "Device has #{@users} users" if @verbose

      # If no users, return empty array
      if @users == 0
        @next_uid = 1
        @next_user_id = '1'
        return []
      end

      users = []
      max_uid = 0
      userdata, size = read_with_buffer(CMD_USERTEMP_RRQ, FCT_USER)
      puts "user size #{size} (= #{userdata.length})" if @verbose

      if size <= 4
        puts 'WRN: missing user data'
        return []
      end

      total_size = userdata[0, 4].unpack1('L<')
      @user_packet_size = total_size / @users

      if ![ 28, 72 ].include?(@user_packet_size)
        puts "WRN packet size would be #{@user_packet_size}" if @verbose
      end

      userdata = userdata[4..-1]

      if @user_packet_size == 28
        while userdata.length >= 28
          uid, privilege, password, name, card, group_id, timezone, user_id = userdata.ljust(28, "\x00")[0, 28].unpack('S<Ca5a8L<xCs<L<')
          max_uid = uid if uid > max_uid
          password = password.split("\x00").first&.force_encoding(@encoding)&.encode('UTF-8', invalid: :replace)
          name = name.split("\x00").first&.force_encoding(@encoding)&.encode('UTF-8', invalid: :replace)&.strip
          group_id = group_id.to_s
          user_id = user_id.to_s
          name = "NN-#{user_id}" if !name
          user = User.new(uid, name, privilege, password, group_id, user_id, card)
          users << user
          puts "[6]user: #{uid}, #{privilege}, #{password}, #{name}, #{card}, #{group_id}, #{timezone}, #{user_id}" if @verbose
          userdata = userdata[28..-1]
        end
      else
        while userdata.length >= 72
          uid, privilege, password, name, card, group_id, user_id = userdata.ljust(72, "\x00")[0, 72].unpack('S<Ca8a24L<xa7xa24')
          max_uid = uid if uid > max_uid
          password = password.split("\x00").first&.force_encoding(@encoding)&.encode('UTF-8', invalid: :replace)
          name = name.split("\x00").first&.force_encoding(@encoding)&.encode('UTF-8', invalid: :replace)&.strip
          group_id = group_id.split("\x00").first&.force_encoding(@encoding)&.encode('UTF-8', invalid: :replace)&.strip
          user_id = user_id.split("\x00").first&.force_encoding(@encoding)&.encode('UTF-8', invalid: :replace)
          name = "NN-#{user_id}" if !name
          user = User.new(uid, name, privilege, password, group_id, user_id, card)
          users << user
          userdata = userdata[72..-1]
        end
      end

      max_uid += 1
      @next_uid = max_uid
      @next_user_id = max_uid.to_s

      loop do
        if users.any? { |u| u.user_id == @next_user_id }
          max_uid += 1
          @next_user_id = max_uid.to_s
        else
          break
        end
      end

      users
    end

    def get_attendance_logs
      # First, read device sizes to get record count
      read_sizes

      # If no records, return empty array
      if @records == 0
        return []
      end

      # Get users for lookup
      users = get_users

      if @verbose
        puts "Found #{users.size} users"
      end

      logs = []

      # Read attendance data with buffer
      attendance_data, size = read_with_buffer(CMD_ATTLOG_RRQ)

      if size < 4
        if @verbose
          puts "WRN: no attendance data"
        end
        return []
      end

      # Get total size from first 4 bytes
      total_size = attendance_data[0...4].unpack1('I')

      # Calculate record size
      record_size = @records > 0 ? total_size / @records : 0

      if @verbose
        puts "record_size is #{record_size}"
      end

      # Remove the first 4 bytes (total size)
      attendance_data = attendance_data[4..-1]

      if record_size == 8
        # Handle 8-byte records
        while attendance_data && attendance_data.size >= 8
          # In Python: uid, status, timestamp, punch = unpack('HB4sB', attendance_data.ljust(8, b'\x00')[:8])
          uid, status, timestamp_raw, punch = attendance_data[0...8].ljust(8, "\x00".b).unpack('S<C4sC')

          if @verbose
            puts "Attendance data (hex): #{attendance_data[0...8].bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
          end

          attendance_data = attendance_data[8..-1]

          # Look up user by uid
          tuser = users.find { |u| u.uid == uid }
          if !tuser
            user_id = uid.to_s
          else
            user_id = tuser.user_id
          end

          # Decode timestamp
          timestamp = decode_time(timestamp_raw)

          # Create attendance record
          attendance = RBZK::Attendance.new(user_id, timestamp, status, punch, uid)
          logs << attendance
        end
      elsif record_size == 16
        # Handle 16-byte records
        while attendance_data && attendance_data.size >= 16
          # In Python: user_id, timestamp, status, punch, reserved, workcode = unpack('<I4sBB2sI', attendance_data.ljust(16, b'\x00')[:16])
          user_id_raw, timestamp_raw, status, punch, reserved, workcode = attendance_data[0...16].ljust(16, "\x00".b).unpack('L<4sCCa2L<')

          if @verbose
            puts "Attendance data (hex): #{attendance_data[0...16].bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
          end

          attendance_data = attendance_data[16..-1]

          # Convert user_id to string
          user_id = user_id_raw.to_s

          # Look up user by user_id and uid
          tuser = users.find { |u| u.user_id == user_id }
          if !tuser
            if @verbose
              puts "no uid #{user_id}"
            end
            uid = user_id
            tuser = users.find { |u| u.uid.to_s == user_id }
            if !tuser
              uid = user_id
            else
              uid = tuser.uid
              user_id = tuser.user_id
            end
          else
            uid = tuser.uid
          end

          # Decode timestamp
          timestamp = decode_time(timestamp_raw)

          # Create attendance record
          attendance = RBZK::Attendance.new(user_id, timestamp, status, punch, uid)
          logs << attendance
        end
      else
        # Handle 40-byte records (default)
        while attendance_data && attendance_data.size >= 40
          # In Python: uid, user_id, status, timestamp, punch, space = unpack('<H24sB4sB8s', attendance_data.ljust(40, b'\x00')[:40])
          uid, user_id_raw, status, timestamp_raw, punch, space = attendance_data[0...40].ljust(40, "\x00".b).unpack('S<a24Ca4Ca8')

          if @verbose
            puts "Attendance data (hex): #{attendance_data[0...40].bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
          end

          # Extract user_id from null-terminated string
          user_id = user_id_raw.split("\x00")[0].to_s

          # Decode timestamp
          timestamp = decode_time(timestamp_raw)

          # Create attendance record
          attendance = RBZK::Attendance.new(user_id, timestamp, status, punch, uid)
          logs << attendance

          attendance_data = attendance_data[record_size..-1]
        end
      end

      logs
    end

    def decode_time(t)
      # Convert binary timestamp to integer
      t = t.unpack1('L<')

      # Extract time components
      second = t % 60
      t = t / 60

      minute = t % 60
      t = t / 60

      hour = t % 24
      t = t / 24

      day = t % 31 + 1
      t = t / 31

      month = t % 12 + 1
      t = t / 12

      year = t + 2000

      # Create Time object
      Time.new(year, month, day, hour, minute, second)
    end

    # Decode a timestamp in hex format (6 bytes)
    # Match Python's __decode_timehex method
    def decode_timehex(timehex)
      # Extract time components
      year, month, day, hour, minute, second = timehex.unpack('C6')
      year += 2000

      # Create Time object
      Time.new(year, month, day, hour, minute, second)
    end

    def encode_time(t)
      # Calculate encoded timestamp
      d = (
        ((t.year % 100) * 12 * 31 + ((t.month - 1) * 31) + t.day - 1) *
          (24 * 60 * 60) + (t.hour * 60 + t.minute) * 60 + t.second
      )
      d
    end

    def get_time
      command = CMD_GET_TIME
      response_size = 1032
      response = send_command(command, '', response_size)

      if response && response[:status]
        decode_time(@data[0...4])
      else
        raise RBZK::ZKErrorResponse, "Can't get time"
      end
    end

    def set_time(timestamp = nil)
      # Default to current time if not provided
      timestamp ||= Time.now

      command = CMD_SET_TIME
      command_string = [ encode_time(timestamp) ].pack('L<')
      response = send_command(command, command_string)

      if response && response[:status]
        true
      else
        raise RBZK::ZKErrorResponse, "Can't set time"
      end
    end

    def clear_attendance_logs
      send_command(CMD_CLEAR_ATTLOG)
      recv_reply
      true
    end

    def clear_data
      send_command(CMD_CLEAR_DATA)
      recv_reply
      true
    end

    # Helper method to print binary data in Python format
    def format_as_python_bytes(binary_string)
      return "b''" if binary_string.nil? || binary_string.empty?

      result = "b'"
      binary_string.each_byte do |byte|
        case byte
        when 0x0d # Carriage return - Python shows as \r
          result += "\\r"
        when 0x0a # Line feed - Python shows as \n
          result += "\\n"
        when 0x09 # Tab - Python shows as \t
          result += "\\t"
        when 0x07 # Bell - Python can show as \a or \x07
          result += "\\x07"
        when 0x08 # Backspace - Python shows as \b
          result += "\\b"
        when 0x0c # Form feed - Python shows as \f
          result += "\\f"
        when 0x0b # Vertical tab - Python shows as \v
          result += "\\v"
        when 0x5c # Backslash - Python shows as \\
          result += "\\\\"
        when 0x27 # Single quote - Python shows as \'
          result += "\\'"
        when 0x22 # Double quote - Python shows as \"
          result += "\\\""
        when 32..126 # Printable ASCII
          result += byte.chr
        else
          # All other bytes - Python shows as \xHH
          result += "\\x#{byte.to_s(16).rjust(2, '0')}"
        end
      end
      result += "'"
      result
    end

    # Helper method to compare binary data between Python and Ruby
    def compare_binary(binary_string, python_expected)
      ruby_formatted = format_as_python_bytes(binary_string)

      if @verbose
        puts "Ruby binary: #{ruby_formatted}"
        puts "Python expected: #{python_expected}"

        if ruby_formatted != python_expected
          puts 'DIFFERENCE DETECTED!'
          # Show byte-by-byte comparison
          ruby_bytes = binary_string.bytes
          # Parse Python bytes string (format: b'\x01\x02')
          python_bytes = []
          python_str = python_expected[2..-2] # Remove b'' wrapper
          i = 0
          while i < python_str.length
            if python_str[i] == '\\' && python_str[i + 1] == 'x'
              # Handle \xNN format
              hex_val = python_str[i + 2..i + 3]
              python_bytes << hex_val.to_i(16)
              i += 4
            elsif python_str[i] == '\\'
              # Handle escape sequences
              case python_str[i + 1]
              when 't'
                python_bytes << 9
              when 'n'
                python_bytes << 10
              when 'r'
                python_bytes << 13
              when '\\'
                python_bytes << 92
              when "'"
                python_bytes << 39
              end
              i += 2
            else
              # Regular character
              python_bytes << python_str[i].ord
              i += 1
            end
          end

          # Show differences
          puts 'Byte-by-byte comparison:'
          max_len = [ ruby_bytes.length, python_bytes.length ].max
          (0...max_len).each do |j|
            ruby_byte = j < ruby_bytes.length ? ruby_bytes[j] : nil
            python_byte = j < python_bytes.length ? python_bytes[j] : nil
            match = ruby_byte == python_byte ? "✓" : "✗"
            puts "  Byte #{j}: Ruby=#{ruby_byte.nil? ? 'nil' : "0x#{ruby_byte.to_s(16).rjust(2, '0')}"}, Python=#{python_byte.nil? ? 'nil' : "0x#{python_byte.to_s(16).rjust(2, '0')}"} #{match}"
          end
        else
          puts 'Binary data matches exactly!'
        end
      end

      ruby_formatted == python_expected
    end

    # Alias for backward compatibility
    alias python_format format_as_python_bytes

    # Helper method to debug binary data in Python format only
    def debug_python_binary(label, data)
      puts "#{label}: #{format_as_python_bytes(data)}"
    end

    def read_sizes
      command = CMD_GET_FREE_SIZES
      response_size = 1024
      cmd_response = send_command(command, '', response_size)

      if cmd_response && cmd_response[:status]
        if @verbose
          puts "Data hex: #{@data.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
          puts "Data Python format: #{python_format(@data)}"
        end

        size = @data.size
        if @verbose
          puts "Data size: #{size} bytes"
        end

        if @data.size >= 80
          # In Python: fields = unpack('20i', self.__data[:80])
          # In Ruby, 'l<' is a signed 32-bit integer (4 bytes) in little-endian format, which matches Python's 'i'
          fields = @data[0...80].unpack('l<20')

          if @verbose
            puts "Unpacked fields: #{fields.inspect}"
          end

          @users = fields[4]
          @fingers = fields[6]
          @records = fields[8]
          @dummy = fields[10] # ???
          @cards = fields[12]
          @fingers_cap = fields[14]
          @users_cap = fields[15]
          @rec_cap = fields[16]
          @fingers_av = fields[17]
          @users_av = fields[18]
          @rec_av = fields[19]
          @data = @data[80..-1]

          # Check for face information (added to match Python implementation)
          if @data.size >= 12 # face info
            # In Python: fields = unpack('3i', self.__data[:12]) #dirty hack! we need more information
            face_fields = @data[0...12].unpack('l<3')
            @faces = face_fields[0]
            @faces_cap = face_fields[2]

            if @verbose
              puts "Face info: faces=#{@faces}, capacity=#{@faces_cap}"
            end
          end

          if @verbose
            puts "Device info: users=#{@users}, fingers=#{@fingers}, records=#{@records}"
            puts "Capacity: users=#{@users_cap}, fingers=#{@fingers_cap}, records=#{@rec_cap}"
          end

          return true
        end
      else
        raise RBZK::ZKErrorResponse, "Can't read sizes"
      end

      false
    end

    def get_free_sizes
      send_command(CMD_GET_FREE_SIZES)
      reply = recv_reply

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

      send_command(CMD_PREPARE_DATA, [ FCT_FINGERTMP ].pack('C'))
      recv_reply

      data_size = recv_long
      templates_data = recv_chunk(data_size)

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
      send_command(CMD_GET_USERTEMP, [ uid, finger_id ].pack('S<S<'))
      reply = recv_reply

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
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [ @timeout, 0 ].pack('l_*'))

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
          ready = IO.select(nil, [ @socket ], nil, @timeout)
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
        @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [ @timeout, 0 ].pack('l_*'))

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
      # If packet is nil or too small, return 0
      return 0 if packet.nil? || packet.size <= 8

      # Ensure packet is a binary string
      # packet = packet.to_s.b

      # Unpack the TCP header - equivalent to Python's unpack('<HHI', packet[:8])
      # S< - unsigned short (2 bytes) little-endian - matches Python's H
      # L< - unsigned long (4 bytes) little-endian - matches Python's I
      tcp_header = packet[0...8].unpack('S<S<L<')

      # Check if the header matches the expected values
      if tcp_header[0] == MACHINE_PREPARE_DATA_1 && tcp_header[1] == MACHINE_PREPARE_DATA_2
        return tcp_header[2] # Return the size (3rd element)
      end

      # Default return 0
      0
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
        ready = IO.select([ udp_socket ], nil, nil, 5)

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
      # Get the length of the buffer
      l = buf.size
      checksum = 0
      i = 0

      # Process pairs of bytes
      while l > 1
        # In Python: checksum += unpack('H', pack('BB', p[0], p[1]))[0]
        # This is combining two bytes into a 16-bit value (little-endian)
        checksum += (buf[i] | (buf[i + 1] << 8))
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
      puts "#{name} (Python): #{format_as_python_bytes(data)}"
    end

    def create_tcp_top(packet)
      puts "\n*** DEBUG: create_tcp_top called ***" if @verbose
      length = packet.size
      top = [ MACHINE_PREPARE_DATA_1, MACHINE_PREPARE_DATA_2, length ].pack('S<S<I<')

      if @verbose
        puts 'TCP header components:'
        puts "  MACHINE_PREPARE_DATA_1: 0x#{MACHINE_PREPARE_DATA_1.to_s(16)}"
        puts "  MACHINE_PREPARE_DATA_2: 0x#{MACHINE_PREPARE_DATA_2.to_s(16)}"
        puts "  packet length: #{length}"
        debug_binary('TCP header', top)
        debug_binary('Full TCP packet', top + packet)
      end

      top + packet
    end

    def create_header(command, command_string = ''.b, session_id = 0, reply_id = 0)
      # Ensure command_string is a binary string
      command_string = command_string.to_s.b

      # Create initial header and combine with command_string
      buf = [ command, 0, session_id, reply_id ].pack('v4') + command_string

      # Convert to bytes array for checksum calculation
      buf = buf.unpack("C#{8 + command_string.length}")

      # Calculate checksum
      checksum = calculate_checksum(buf)

      # Update reply_id
      reply_id += 1
      if reply_id >= USHRT_MAX
        reply_id -= USHRT_MAX
      end

      # Create final header with updated values
      buf = [ command, checksum, session_id, reply_id ].pack('v4')

      if @verbose
        puts 'Header components:'
        puts "  Command: #{command}"
        puts "  Checksum: #{checksum}"
        puts "  Session ID: #{session_id}"
        puts "  Reply ID: #{reply_id}"

        if !command_string.empty?
          debug_binary('Command string', command_string)
        else
          puts 'Command string: (empty)'
        end
        debug_binary('Final header', buf)
      end

      buf + command_string
    end

    def send_command(command, command_string = ''.b, response_size = 8)
      # Check connection status (except for connect and auth commands)
      if command != CMD_CONNECT && command != CMD_AUTH && !@connected
        raise RBZK::ZKErrorConnection, 'Instance are not connected.'
      end

      # In Python, command_string is a bytes object (b'')
      # In Ruby, we use binary strings (ASCII-8BIT encoding)
      command_string = command_string.to_s.b

      if @verbose
        puts "command_string class: #{command_string.class}"
        puts "command_string encoding: #{command_string.encoding}"
        puts "command_string bytes: #{python_format(command_string)}"
      end

      # Create command header (like Python's __create_header)
      buf = create_header(command, command_string, @session_id, @reply_id)

      if @verbose
        puts "\nSending command #{command} with session id #{@session_id} and reply id #{@reply_id}"
        puts "buf: #{python_format(buf)}"
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
            puts 'This is because create_tcp_top returns the full packet, not just the header'
            debug_binary('Command packet (buf)', buf)
            debug_binary('Full TCP packet (top)', top) # 'top' contains the full packet here
          end

          @socket.send(top, 0)
          @tcp_data_recv = @socket.recv(response_size + 8)
          @tcp_length = test_tcp_top(@tcp_data_recv)

          if @verbose
            puts "\nReceived TCP response:"
            debug_binary('TCP response', @tcp_data_recv)
          end

          if @tcp_length == 0
            raise RBZK::ZKNetworkError, "TCP packet invalid"
          end

          @header = @tcp_data_recv[8..15].unpack('v4')
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
      @data = @data_recv[8..-1] # This is the key line that matches Python's self.__data = self.__data_recv[8:]

      # Return response status (like Python's __send_command)
      if @response == CMD_ACK_OK || @response == CMD_PREPARE_DATA || @response == CMD_DATA
        {
          status: true,
          code: @response
        }
      else
        {
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
          tcp_header = @socket.read(8)
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
          cmd_header = @socket.read(8)
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
              chunk_size = [ remaining, 4096 ].min
              chunk = @socket.read(chunk_size)
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
        return data.unpack1('L<')
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
      if @verbose
        puts "\n*** DEBUG: make_commkey called ***"
        puts "key: #{key}, session_id: #{session_id}, ticks: #{ticks}"
      end

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
      # In Python: pack(b'BBBB', k[0] ^ B, k[1] ^ B, B, k[3] ^ B)
      # Note: The third byte is just B, not k[2] ^ B
      result = [ k_bytes[0] ^ b, k_bytes[1] ^ b, b, k_bytes[3] ^ b ].pack('C4')

      if @verbose
        puts "Final commkey bytes: #{result.bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
      end

      result
    end
  end
end
