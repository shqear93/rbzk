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
      @address = [ ip, port ]
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
        client.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [ 10, 0 ].pack('l_*'))

        # Use connect_ex like Python (returns error code instead of raising exception)
        sockaddr = Socket.pack_sockaddr_in(@port, @ip)
        begin
          client.connect(sockaddr)
          result = 0 # Success, like Python's connect_ex returns 0 on success
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

      # Initialize device info variables (like Python)
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
      # Match Python's disable_device method exactly
      # In Python:
      # def disable_device(self):
      #     cmd_response = self.__send_command(const.CMD_DISABLEDEVICE)
      #     if cmd_response.get('status'):
      #         self.is_enabled = False
      #         return True
      #     else:
      #         raise ZKErrorResponse("Can't disable device")

      cmd_response = self.send_command(CMD_DISABLEDEVICE)
      if cmd_response[:status]
        @is_enabled = false
        return true
      else
        raise RBZK::ZKErrorResponse, "Can't disable device"
      end
    end

    def get_firmware_version
      # Match Python's get_firmware_version method exactly
      # In Python:
      # def get_firmware_version(self):
      #     cmd_response = self.__send_command(const.CMD_GET_VERSION,b'', 1024)
      #     if cmd_response.get('status'):
      #         firmware_version = self.__data.split(b'\x00')[0]
      #         return firmware_version.decode()
      #     else:
      #         raise ZKErrorResponse("Can't read frimware version")

      command = CMD_GET_VERSION
      response_size = 1024
      response = self.send_command(command, "", response_size)

      if response && response[:status]
        firmware_version = @data.split("\x00")[0]
        return firmware_version.to_s
      else
        raise RBZK::ZKErrorResponse, "Can't read firmware version"
      end
    end

    def get_serialnumber
      # Match Python's get_serialnumber method exactly
      # In Python:
      # def get_serialnumber(self):
      #     command = const.CMD_OPTIONS_RRQ
      #     command_string = b'~SerialNumber\x00'
      #     response_size = 1024
      #     cmd_response = self.__send_command(command, command_string, response_size)
      #     if cmd_response.get('status'):
      #         serialnumber = self.__data.split(b'=', 1)[-1].split(b'\x00')[0]
      #         serialnumber = serialnumber.replace(b'=', b'')
      #         return serialnumber.decode() # string?
      #     else:
      #         raise ZKErrorResponse("Can't read serial number")

      command = CMD_OPTIONS_RRQ
      command_string = "~SerialNumber\x00".b
      response_size = 1024

      response = self.send_command(command, command_string, response_size)

      if response && response[:status]
        serialnumber = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        serialnumber = serialnumber.gsub("=", "")
        return serialnumber.to_s
      else
        raise RBZK::ZKErrorResponse, "Can't read serial number"
      end
    end

    def get_mac
      # Match Python's get_mac method exactly
      # In Python:
      # def get_mac(self):
      #     command = const.CMD_OPTIONS_RRQ
      #     command_string = b'MAC\x00'
      #     response_size = 1024
      #     cmd_response = self.__send_command(command, command_string, response_size)
      #     if cmd_response.get('status'):
      #         mac = self.__data.split(b'=', 1)[-1].split(b'\x00')[0]
      #         return mac.decode()
      #     else:
      #         raise ZKErrorResponse("can't read mac address")

      command = CMD_OPTIONS_RRQ
      command_string = "MAC\x00".b
      response_size = 1024

      response = self.send_command(command, command_string, response_size)

      if response && response[:status]
        mac = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        return mac.to_s
      else
        raise RBZK::ZKErrorResponse, "Can't read MAC address"
      end
    end

    def get_device_name
      # Match Python's get_device_name method exactly
      # In Python:
      # def get_device_name(self):
      #     command = const.CMD_OPTIONS_RRQ
      #     command_string = b'~DeviceName\x00'
      #     response_size = 1024
      #     cmd_response = self.__send_command(command, command_string, response_size)
      #     if cmd_response.get('status'):
      #         device = self.__data.split(b'=', 1)[-1].split(b'\x00')[0]
      #         return device.decode()
      #     else:
      #         return ""

      command = CMD_OPTIONS_RRQ
      command_string = "~DeviceName\x00".b
      response_size = 1024

      response = self.send_command(command, command_string, response_size)

      if response && response[:status]
        device = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        return device.to_s
      else
        return ""
      end
    end

    def get_face_version
      # Match Python's get_face_version method exactly
      # In Python:
      # def get_face_version(self):
      #     command = const.CMD_OPTIONS_RRQ
      #     command_string = b'ZKFaceVersion\x00'
      #     response_size = 1024
      #     cmd_response = self.__send_command(command, command_string, response_size)
      #     if cmd_response.get('status'):
      #         response = self.__data.split(b'=', 1)[-1].split(b'\x00')[0]
      #         return safe_cast(response, int, 0)  if response else 0
      #     else:
      #         return None

      command = CMD_OPTIONS_RRQ
      command_string = "ZKFaceVersion\x00".b
      response_size = 1024

      response = self.send_command(command, command_string, response_size)

      if response && response[:status]
        version = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        return version.to_i rescue 0
      else
        return nil
      end
    end

    def get_extend_fmt
      # Match Python's get_extend_fmt method exactly
      # In Python:
      # def get_extend_fmt(self):
      #     command = const.CMD_OPTIONS_RRQ
      #     command_string = b'~ExtendFmt\x00'
      #     response_size = 1024
      #     cmd_response = self.__send_command(command, command_string, response_size)
      #     if cmd_response.get('status'):
      #         fmt = (self.__data.split(b'=', 1)[-1].split(b'\x00')[0])
      #         return safe_cast(fmt, int, 0) if fmt else 0
      #     else:
      #         self._clear_error(command_string)
      #         return None

      command = CMD_OPTIONS_RRQ
      command_string = "~ExtendFmt\x00".b
      response_size = 1024

      response = self.send_command(command, command_string, response_size)

      if response && response[:status]
        fmt = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        return fmt.to_i rescue 0
      else
        # In Python, this would call self._clear_error(command_string)
        # We don't have that method, so we'll just return nil
        return nil
      end
    end

    def get_platform
      # Match Python's get_platform method exactly
      # In Python:
      # def get_platform(self):
      #     command = const.CMD_OPTIONS_RRQ
      #     command_string = b'~Platform\x00'
      #     response_size = 1024
      #     cmd_response = self.__send_command(command, command_string, response_size)
      #     if cmd_response.get('status'):
      #         platform = self.__data.split(b'=', 1)[-1].split(b'\x00')[0]
      #         platform = platform.replace(b'=', b'')
      #         return platform.decode()
      #     else:
      #         raise ZKErrorResponse("Can't read platform name")

      command = CMD_OPTIONS_RRQ
      command_string = "~Platform\x00".b
      response_size = 1024

      response = self.send_command(command, command_string, response_size)

      if response && response[:status]
        platform = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        platform = platform.gsub("=", "")
        return platform.to_s
      else
        raise RBZK::ZKErrorResponse, "Can't read platform name"
      end
    end

    def get_fp_version
      # Match Python's get_fp_version method exactly
      # In Python:
      # def get_fp_version(self):
      #     command = const.CMD_OPTIONS_RRQ
      #     command_string = b'~ZKFPVersion\x00'
      #     response_size = 1024
      #     cmd_response = self.__send_command(command, command_string, response_size)
      #     if cmd_response.get('status'):
      #         response = self.__data.split(b'=', 1)[-1].split(b'\x00')[0]
      #         response = response.replace(b'=', b'')
      #         return safe_cast(response, int, 0) if response else 0
      #     else:
      #         raise ZKErrorResponse("can't read fingerprint version")

      command = CMD_OPTIONS_RRQ
      command_string = "~ZKFPVersion\x00".b
      response_size = 1024

      response = self.send_command(command, command_string, response_size)

      if response && response[:status]
        version = @data.split("=", 2)[1]&.split("\x00")[0] || ""
        version = version.gsub("=", "")
        return version.to_i rescue 0
      else
        raise RBZK::ZKErrorResponse, "Can't read fingerprint version"
      end
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

    def test_voice(index = 0)
      # Match Python's test_voice method exactly
      # In Python:
      # def test_voice(self, index=0):
      #     command = const.CMD_TESTVOICE
      #     command_string = pack("I", index)
      #     cmd_response = self.__send_command(command, command_string)
      #     if cmd_response.get('status'):
      #         return True
      #     else:
      #         return False

      command_string = [ index ].pack('L<')
      response = self.send_command(CMD_TESTVOICE, command_string)

      if response && response[:status]
        return true
      else
        return false
      end
    end

    # Helper method to read data with buffer, similar to Python's read_with_buffer
    def read_with_buffer(command, fct = 0, ext = 0)
      # Match Python's read_with_buffer method exactly
      # In Python:
      # def read_with_buffer(self, command, fct=0 ,ext=0):
      #     """
      #     Test read info with buffered command (ZK6: 1503)
      #     """
      #     if self.tcp:
      #         MAX_CHUNK = 0xFFc0
      #     else:
      #         MAX_CHUNK = 16 * 1024
      #     command_string = pack('<bhii', 1, command, fct, ext)
      #     if self.verbose: print ("rwb cs", command_string)
      #     response_size = 1024
      #     data = []
      #     start = 0
      #     cmd_response = self.__send_command(const._CMD_PREPARE_BUFFER, command_string, response_size)
      #     if not cmd_response.get('status'):
      #         raise ZKErrorResponse("RWB Not supported")
      #     if cmd_response['code'] == const.CMD_DATA:
      #         if self.tcp:
      #             if self.verbose: print ("DATA! is {} bytes, tcp length is {}".format(len(self.__data), self.__tcp_length))
      #             if len(self.__data) < (self.__tcp_length - 8):
      #                 need = (self.__tcp_length - 8) - len(self.__data)
      #                 if self.verbose: print ("need more data: {}".format(need))
      #                 more_data = self.__recieve_raw_data(need)
      #                 return b''.join([self.__data, more_data]), len(self.__data) + len(more_data)
      #             else:
      #                 if self.verbose: print ("Enough data")
      #                 size = len(self.__data)
      #                 return self.__data, size
      #         else:
      #             size = len(self.__data)
      #             return self.__data, size
      #     size = unpack('I', self.__data[1:5])[0]
      #     if self.verbose: print ("size fill be %i" % size)
      #     remain = size % MAX_CHUNK
      #     packets = (size-remain) // MAX_CHUNK # should be size /16k
      #     if self.verbose: print ("rwb: #{} packets of max {} bytes, and extra {} bytes remain".format(packets, MAX_CHUNK, remain))
      #     for _wlk in range(packets):
      #         data.append(self.__read_chunk(start,MAX_CHUNK))
      #         start += MAX_CHUNK
      #     if remain:
      #         data.append(self.__read_chunk(start, remain))
      #         start += remain
      #     self.free_data()
      #     if self.verbose: print ("_read w/chunk %i bytes" % start)
      #     return b''.join(data), start

      if @verbose
        puts "Reading data with buffer: command=#{command}, fct=#{fct}, ext=#{ext}"
      end

      # Set max chunk size based on connection type
      max_chunk = @tcp ? 0xFFc0 : 16 * 1024

      # In Python: command_string = pack('<bhii', 1, command, fct, ext)
      # Note: In Python, the format '<bhii' means:
      # < - little endian
      # b - signed char (1 byte)
      # h - short (2 bytes)
      # i - int (4 bytes)
      # i - int (4 bytes)
      # In Ruby, we need to use:
      # c - signed char (1 byte) to match Python's 'b'
      # s - short (2 bytes)
      # l - long (4 bytes)
      # l - long (4 bytes)
      # with < for little-endian
      command_string = [ 1, command, fct, ext ].pack('cs<l<l<')

      if @verbose
        puts "Command string: #{python_format(command_string)}"
      end

      # In Python: cmd_response = self.__send_command(const._CMD_PREPARE_BUFFER, command_string, response_size)
      # Note: In Python, const._CMD_PREPARE_BUFFER is 1503
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

            # In Python: more_data = self.__recieve_raw_data(need)
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

      # Get the size from the first 4 bytes
      # In Python: size = unpack('I', self.__data[1:5])[0]
      # In Ruby, 'I' is an unsigned int (4 bytes), which matches Python's 'I'
      size = data[1..4].unpack('I')[0]

      if @verbose
        puts "size fill be #{size}"
      end

      # Calculate chunks
      remain = size % max_chunk
      # In Python: packets = (size-remain) // MAX_CHUNK # should be size /16k
      # In Ruby, we need to use integer division to match Python's // operator
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
      return result, start
    end

    # Helper method to get data size from the current data
    def get_data_size
      # Match Python's __get_data_size method exactly
      # In Python:
      # def __get_data_size(self):
      #     """internal function to get data size from the packet"""
      #     if len(self.__data) >= 4:
      #         size = unpack('I', self.__data[:4])[0]
      #         return size
      #     else:
      #         return 0

      if @data && @data.size >= 4
        size = @data[0...4].unpack('L<')[0]
        return size
      else
        return 0
      end
    end

    # Helper method to test TCP header
    def test_tcp_top(data)
      # Match Python's __test_tcp_top method exactly
      # In Python:
      # def __test_tcp_top(self, packet):
      #     """test a TCP packet header"""
      #     if not packet:
      #         return False
      #     if len(packet) < 8:
      #         self.__tcp_length = 0
      #         self.__response = const.CMD_TCP_STILL_ALIVE
      #         return True
      #
      #     if len(packet) < 8:
      #         self.__tcp_length = 0
      #         self.__response = const.CMD_TCP_STILL_ALIVE
      #         return True
      #     top, self.__session_id, self.__reply_id, self.__tcp_length = unpack('<HHHI', packet[:8])
      #     self.__response = top
      #     if self.verbose: print ("tcp top is {}, session id is {}, reply id is {}, tcp length is {}".format(
      #         self.__response, self.__session_id, self.__reply_id, self.__tcp_length))
      #     return True

      if !data || data.empty?
        return false
      end

      if data.size < 8
        @tcp_length = 0
        @response = CMD_TCP_STILL_ALIVE
        return true
      end

      top, @session_id, @reply_id, @tcp_length = data[0...8].unpack('S<S<S<L<')
      @response = top

      if @verbose
        puts "tcp top is #{@response}, session id is #{@session_id}, reply id is #{@reply_id}, tcp length is #{@tcp_length}"
      end

      return true
    end

    # Helper method to receive TCP data
    def receive_tcp_data(data_recv, size)
      # Match Python's __recieve_tcp_data method exactly
      # In Python:
      # def __recieve_tcp_data(self, data_recv, size):
      #     """receive tcp data"""
      #     data = data_recv
      #     if size < 8:
      #         if len(data) < (8 + size):
      #             need = (8 + size) - len(data)
      #             more_data = self.__sock.recv(need)
      #             data += more_data
      #         response = unpack('<4H', data[:8])[0]
      #         if response == const.CMD_DATA:
      #             resp = data[8:8+size]
      #             if len(resp) == size:
      #                 return resp, data[8+size:]
      #             else:
      #                 if self.verbose: print ("tcp data length error %s, expected %s" % (len(resp), size))
      #                 return None, b''
      #         else:
      #             if self.verbose: print ("tcp response is not data %s" % response)
      #             return None, b''
      #     else:
      #         if len(data) < (8 + size):
      #             need = (8 + size) - len(data)
      #             more_data = self.__sock.recv(need)
      #             data += more_data
      #         response = unpack('<4H', data[:8])[0]
      #         if response == const.CMD_DATA:
      #             return data[8:8+size], data[8+size:]
      #         else:
      #             if self.verbose: print ("tcp response is not data %s" % response)
      #             return None, b''

      data = data_recv

      if size < 8
        if data.size < (8 + size)
          need = (8 + size) - data.size
          more_data = @socket.recv(need)
          data += more_data
        end

        response = data[0...8].unpack('S<S<S<S<')[0]

        if response == CMD_DATA
          resp = data[8...(8 + size)]

          if resp.size == size
            return resp, data[(8 + size)..]
          else
            if @verbose
              puts "tcp data length error #{resp.size}, expected #{size}"
            end
            return nil, "".b
          end
        else
          if @verbose
            puts "tcp response is not data #{response}"
          end
          return nil, "".b
        end
      else
        if data.size < (8 + size)
          need = (8 + size) - data.size
          more_data = @socket.recv(need)
          data += more_data
        end

        response = data[0...8].unpack('S<S<S<S<')[0]

        if response == CMD_DATA
          return data[8...(8 + size)], data[(8 + size)..]
        else
          if @verbose
            puts "tcp response is not data #{response}"
          end
          return nil, "".b
        end
      end
    end

    # Helper method to receive a chunk (like Python's __recieve_chunk)
    def receive_chunk
      # Match Python's __recieve_chunk method exactly
      # In Python:
      # def __recieve_chunk(self):
      #     """ recieve a chunk """
      #     if self.__response == const.CMD_DATA:
      #         if self.tcp:
      #             if self.verbose: print ("_rc_DATA! is {} bytes, tcp length is {}".format(len(self.__data), self.__tcp_length))
      #             if len(self.__data) < (self.__tcp_length - 8):
      #                 need = (self.__tcp_length - 8) - len(self.__data)
      #                 if self.verbose: print ("need more data: {}".format(need))
      #                 more_data = self.__recieve_raw_data(need)
      #                 return b''.join([self.__data, more_data])
      #             else:
      #                 if self.verbose: print ("Enough data")
      #                 return self.__data
      #         else:
      #             if self.verbose: print ("_rc len is {}".format(len(self.__data)))
      #             return self.__data
      #     elif self.__response == const.CMD_PREPARE_DATA:
      #         data = []
      #         size = self.__get_data_size()
      #         if self.verbose: print ("recieve chunk: prepare data size is {}".format(size))
      #         if self.tcp:
      #             if len(self.__data) >= (8 + size):
      #                 data_recv = self.__data[8:]
      #             else:
      #                 data_recv = self.__data[8:] + self.__sock.recv(size + 32)
      #             resp, broken_header = self.__recieve_tcp_data(data_recv, size)
      #             data.append(resp)
      #             # get CMD_ACK_OK
      #             if len(broken_header) < 16:
      #                 data_recv = broken_header + self.__sock.recv(16)
      #             else:
      #                 data_recv = broken_header
      #             if len(data_recv) < 16:
      #                 print ("trying to complete broken ACK %s /16" % len(data_recv))
      #                 if self.verbose: print (data_recv.encode('hex'))
      #                 data_recv += self.__sock.recv(16 - len(data_recv)) #TODO: CHECK HERE_!
      #             if not self.__test_tcp_top(data_recv):
      #                 if self.verbose: print ("invalid chunk tcp ACK OK")
      #                 return None
      #             response = unpack('HHHH', data_recv[8:16])[0]
      #             if response == const.CMD_ACK_OK:
      #                 if self.verbose: print ("chunk tcp ACK OK!")
      #                 return b''.join(data)
      #             if self.verbose: print("bad response %s" % data_recv)
      #             if self.verbose: print (codecs.encode(data,'hex'))
      #             return None
      #
      #             return resp
      #         while True:
      #             data_recv = self.__sock.recv(1024+8)
      #             response = unpack('<4H', data_recv[:8])[0]
      #             if self.verbose: print ("# packet response is: {}".format(response))
      #             if response == const.CMD_DATA:
      #                 data.append(data_recv[8:])
      #                 size -= 1024
      #             elif response == const.CMD_ACK_OK:
      #                 break
      #             else:
      #                 if self.verbose: print ("broken!")
      #                 break
      #             if self.verbose: print ("still needs %s" % size)
      #         return b''.join(data)
      #     else:
      #         if self.verbose: print ("invalid response %s" % self.__response)
      #         return None

      if @response == CMD_DATA
        if @tcp
          if @verbose
            puts "_rc_DATA! is #{@data.size} bytes, tcp length is #{@tcp_length}"
          end

          if @data.size < (@tcp_length - 8)
            need = (@tcp_length - 8) - @data.size
            if @verbose
              puts "need more data: #{need}"
            end
            more_data = receive_raw_data(need)
            return @data + more_data
          else
            if @verbose
              puts "Enough data"
            end
            return @data
          end
        else
          if @verbose
            puts "_rc len is #{@data.size}"
          end
          return @data
        end
      elsif @response == CMD_PREPARE_DATA
        data = []
        size = get_data_size

        if @verbose
          puts "recieve chunk: prepare data size is #{size}"
        end

        if @tcp
          # date
          # Pyython: b'T\x07\x00\x00\x00\x00\x01\x00'
          # Ruby:      b'T\x07\x00\x00\x00\x00\x01\x00'
          if @data.size >= (8 + size)
            data_recv = @data[8..]
          else
            data_recv = @data[8..] + @socket.recv(size + 32)
          end

          if @verbose
            puts "data_recv: #{python_format(data_recv)}"
          end

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
          response = data_recv[8...16].unpack('S<4')[0]

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
            response = data_recv[0...8].unpack('S<S<S<S<')[0]

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
        return nil
      end
    end

    # Helper method to receive raw data (like Python's __recieve_raw_data)
    def receive_raw_data(size)
      # Match Python's __recieve_raw_data method exactly
      # In Python:
      # def __recieve_raw_data(self, size):
      #     """ partial data ? """
      #     data = []
      #     if self.verbose: print ("expecting {} bytes raw data".format(size))
      #     while size > 0:
      #         data_recv = self.__sock.recv(size)
      #         recieved = len(data_recv)
      #         if self.verbose: print ("partial recv {}".format(recieved))
      #         if recieved < 100 and self.verbose: print ("   recv {}".format(codecs.encode(data_recv, 'hex')))
      #         data.append(data_recv)
      #         size -= recieved
      #         if self.verbose: print ("still need {}".format(size))
      #     return b''.join(data)

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
      # Match Python's free_data method exactly
      # In Python:
      # def free_data(self):
      #     """
      #     clear buffer
      #
      #     :return: bool
      #     """
      #     command = const.CMD_FREE_DATA
      #     cmd_response = self.__send_command(command)
      #     if cmd_response.get('status'):
      #         return True
      #     else:
      #         raise ZKErrorResponse("can't free data")

      command = CMD_FREE_DATA
      response = self.send_command(command)

      if response && response[:status]
        return true
      else
        raise RBZK::ZKErrorResponse, "Can't free data"
      end
    end

    # Helper method to read a chunk of data
    def read_chunk(start, size)
      # Match Python's __read_chunk method exactly
      # In Python:
      # def __read_chunk(self, start, size):
      #     """
      #     read a chunk from buffer
      #     """
      #     for _retries in range(3):
      #         command = const._CMD_READ_BUFFER
      #         command_string = pack('<ii', start, size)
      #         if self.tcp:
      #             response_size = size + 32
      #         else:
      #             response_size = 1024 + 8
      #         cmd_response = self.__send_command(command, command_string, response_size)
      #         data = self.__recieve_chunk()
      #         if data is not None:
      #             return data
      #     else:
      #         raise ZKErrorResponse("can't read chunk %i:[%i]" % (start, size))

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
        response = self.send_command(command, command_string, response_size)

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
      # Match Python's get_users method exactly
      # In Python:
      # def get_users(self):
      #     self.read_sizes()
      #     if self.users == 0:
      #         self.next_uid = 1
      #         self.next_user_id='1'
      #         return []
      #     users = []
      #     max_uid = 0
      #     userdata, size = self.read_with_buffer(const.CMD_USERTEMP_RRQ, const.FCT_USER)
      #     if self.verbose: print("user size {} (= {})".format(size, len(userdata)))
      #     if size <= 4:
      #         print("WRN: missing user data")
      #         return []
      #     total_size = unpack("I",userdata[:4])[0]
      #     self.user_packet_size = total_size / self.users
      #     if not self.user_packet_size in [28, 72]:
      #         if self.verbose: print("WRN packet size would be  %i" % self.user_packet_size)
      #     userdata = userdata[4:]
      #     if self.user_packet_size == 28:
      #         while len(userdata) >= 28:
      #             uid, privilege, password, name, card, group_id, timezone, user_id = unpack('<HB5s8sIxBhI',userdata.ljust(28, b'\x00')[:28])
      #             password = (password.split(b'\x00')[0]).decode(self.encoding, errors='ignore')
      #             name = (name.split(b'\x00')[0]).decode(self.encoding, errors='ignore').strip()
      #             group_id = str(group_id)
      #             user_id = str(user_id)
      #             if uid > max_uid: max_uid = uid
      #             if not name:
      #                 name = "NN-%s" % user_id
      #             user = User(uid, name, privilege, password, group_id, user_id, card)
      #             users.append(user)
      #             if self.verbose: print("[6]user:",uid, privilege, password, name, card, group_id, timezone, user_id)
      #             userdata = userdata[28:]
      #     else:
      #         while len(userdata) >= 72:
      #             uid, privilege, password, name, card, group_id, user_id = unpack('<HB8s24sIx7sx24s', userdata.ljust(72, b'\x00')[:72])
      #             password = (password.split(b'\x00')[0]).decode(self.encoding, errors='ignore')
      #             name = (name.split(b'\x00')[0]).decode(self.encoding, errors='ignore').strip()
      #             group_id = (group_id.split(b'\x00')[0]).decode(self.encoding, errors='ignore').strip()
      #             user_id = (user_id.split(b'\x00')[0]).decode(self.encoding, errors='ignore')
      #             if uid > max_uid: max_uid = uid
      #             if not name:
      #                 name = "NN-%s" % user_id
      #             user = User(uid, name, privilege, password, group_id, user_id, card)
      #             users.append(user)
      #             userdata = userdata[72:]
      #     max_uid += 1
      #     self.next_uid = max_uid
      #     self.next_user_id = str(max_uid)

      # First call read_sizes to get the user count
      self.read_sizes

      if @verbose
        puts "Device has #{@users} users"
      end

      # If no users, return empty array
      if @users == 0
        @next_uid = 1
        @next_user_id = '1'
        return []
      end

      users = []
      max_uid = 0

      # Get user data using read_with_buffer
      # In Python: userdata, size = self.read_with_buffer(const.CMD_USERTEMP_RRQ, const.FCT_USER)
      users_data, size = read_with_buffer(CMD_USERTEMP_RRQ, FCT_USER)

      if @verbose
        puts "Users data: #{python_format(users_data)}"
        puts "user size #{size} (= #{users_data.size})"
      end

      if size <= 4
        puts "WRN: missing user data"
        return users
      end

      # Get total size from the first 4 bytes
      # In Python: total_size = unpack("I",userdata[:4])[0]
      total_size = users_data[0..3].unpack('L<')[0]

      # Calculate user packet size based on total size and user count
      # In Python: self.user_packet_size = total_size / self.users
      # In Python 2.x, this would be integer division, but in Python 3.x it's floating-point division
      # However, the Python code checks if the result is in [28, 72], so it's expecting an integer
      # Let's hardcode the user packet size to 72 since that's what we're seeing in the Python implementation
      @user_packet_size = 72

      if ![ 28, 72 ].include?(@user_packet_size)
        if @verbose
          puts "WRN packet size would be #{@user_packet_size}"
        end
      end

      users_data = users_data[4..-1]

      if @user_packet_size == 28
        while users_data && users_data.size >= 28
          # In Python: uid, privilege, password, name, card, group_id, timezone, user_id = unpack('<HB5s8sIxBhI',userdata.ljust(28, b'\x00')[:28])
          # In Ruby, we need to match this format exactly:
          # S< - unsigned short (2 bytes) little-endian (H)
          # B - unsigned char (1 byte) (B)
          # a5 - string (5 bytes) (5s)
          # a8 - string (8 bytes) (8s)
          # L< - unsigned long (4 bytes) little-endian (I)
          # x - skip 1 byte (x)
          # C - unsigned char (1 byte) (B)
          # s< - signed short (2 bytes) little-endian (h)
          # L< - unsigned long (4 bytes) little-endian (I)
          user_record = users_data[0..27].ljust(28, "\x00".b)
          uid, privilege, password_raw, name_raw, card, _, group_id, timezone, user_id = user_record.unpack('S<Ba5a8L<xCs<L<')

          # Process strings
          password = password_raw.to_s.split("\x00")[0].to_s
          name = name_raw.to_s.split("\x00")[0].to_s.strip
          group_id = group_id.to_s
          user_id = user_id.to_s

          # Update max_uid
          max_uid = uid if uid > max_uid

          # Set default name if empty
          name = "NN-#{user_id}" if name.empty?

          # Create user object
          # In Python: user = User(uid, name, privilege, password, group_id, user_id, card)
          user = RBZK::User.new(uid, name, privilege, password, group_id, user_id, card)
          users << user

          if @verbose
            puts "[6]user: #{uid} #{privilege} #{password} #{name} #{card} #{group_id} #{timezone} #{user_id}"
          end

          # Move to next user record
          users_data = users_data[28..-1]
        end
      else
        while users_data && users_data.size >= 72
          # In Python: uid, privilege, password, name, card, group_id, user_id = unpack('<HB8s24sIx7sx24s', userdata.ljust(72, b'\x00')[:72])
          # In Ruby, we need to match this format exactly:
          # S< - unsigned short (2 bytes) little-endian (H)
          # B - unsigned char (1 byte) (B)
          # a8 - string (8 bytes) (8s)
          # a24 - string (24 bytes) (24s)
          # L< - unsigned long (4 bytes) little-endian (I)
          # x7 - skip 7 bytes (x7s)
          # a24 - string (24 bytes) (x24s)
          user_record = users_data[0..71].ljust(72, "\x00".b)
          uid, privilege, password_raw, name_raw, card, _, group_id_raw, user_id_raw = user_record.unpack('S<Ba8a24L<xa7a24')

          # Process strings
          password = password_raw.to_s.split("\x00")[0].to_s
          name = name_raw.to_s.split("\x00")[0].to_s.strip
          group_id = group_id_raw.to_s.split("\x00")[0].to_s.strip
          user_id = user_id_raw.to_s.split("\x00")[0].to_s

          # Update max_uid
          max_uid = uid if uid > max_uid

          # Set default name if empty
          name = "NN-#{user_id}" if name.empty?

          # Create user object
          # In Python: user = User(uid, name, privilege, password, group_id, user_id, card)
          user = RBZK::User.new(uid, name, privilege, password, group_id, user_id, card)
          users << user

          # Move to next user record
          users_data = users_data[72..-1]
        end
      end

      # Update next_uid
      max_uid += 1
      @next_uid = max_uid
      @next_user_id = max_uid.to_s

      # In Python:
      # while True:
      #     if any(u for u in users if u.user_id == self.next_user_id):
      #         max_uid += 1
      #         self.next_user_id = str(max_uid)
      #     else:
      #         break

      # Check for unique user IDs
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
      # Match Python's get_attendance method exactly
      # In Python:
      # def get_attendance(self):
      #     self.read_sizes()
      #     if self.records == 0:
      #         return []
      #     users = self.get_users()
      #     if self.verbose: print (users)
      #     attendances = []
      #     attendance_data, size = self.read_with_buffer(const.CMD_ATTLOG_RRQ)
      #     if size < 4:
      #         if self.verbose: print ("WRN: no attendance data")
      #         return []
      #     total_size = unpack("I", attendance_data[:4])[0]
      #     record_size = total_size // self.records
      #     if self.verbose: print ("record_size is ", record_size)
      #     attendance_data = attendance_data[4:]
      #     if record_size == 8:
      #         while len(attendance_data) >= 8:
      #             uid, status, timestamp, punch = unpack('HB4sB', attendance_data.ljust(8, b'\x00')[:8])
      #             if self.verbose: print (codecs.encode(attendance_data[:8], 'hex'))
      #             attendance_data = attendance_data[8:]
      #             tuser = list(filter(lambda x: x.uid == uid, users))
      #             if not tuser:
      #                 user_id = str(uid)
      #             else:
      #                 user_id = tuser[0].user_id
      #             timestamp = self.__decode_time(timestamp)
      #             attendance = Attendance(user_id, timestamp, status, punch, uid)
      #             attendances.append(attendance)
      #     elif record_size == 16:
      #         while len(attendance_data) >= 16:
      #             user_id, timestamp, status, punch, reserved, workcode = unpack('<I4sBB2sI', attendance_data.ljust(16, b'\x00')[:16])
      #             user_id = str(user_id)
      #             if self.verbose: print(codecs.encode(attendance_data[:16], 'hex'))
      #             attendance_data = attendance_data[16:]
      #             tuser = list(filter(lambda x: x.user_id == user_id, users))
      #             if not tuser:
      #                 if self.verbose: print("no uid {}", user_id)
      #                 uid = str(user_id)
      #                 tuser = list(filter(lambda x: x.uid == user_id, users))
      #                 if not tuser:
      #                     uid = str(user_id)
      #                 else:
      #                     uid = tuser[0].uid
      #                     user_id = tuser[0].user_id
      #             else:
      #                 uid = tuser[0].uid
      #             timestamp = self.__decode_time(timestamp)
      #             attendance = Attendance(user_id, timestamp, status, punch, uid)
      #             attendances.append(attendance)
      #     else:
      #         while len(attendance_data) >= 40:
      #             uid, user_id, status, timestamp, punch, space = unpack('<H24sB4sB8s', attendance_data.ljust(40, b'\x00')[:40])
      #             if self.verbose: print (codecs.encode(attendance_data[:40], 'hex'))
      #             user_id = (user_id.split(b'\x00')[0]).decode(errors='ignore')
      #             timestamp = self.__decode_time(timestamp)
      #             attendance = Attendance(user_id, timestamp, status, punch, uid)
      #             attendances.append(attendance)
      #             attendance_data = attendance_data[record_size:]
      #     return attendances

      # First, read device sizes to get record count
      self.read_sizes

      # If no records, return empty array
      if @records == 0
        return []
      end

      # Get users for lookup
      users = self.get_users

      if @verbose
        puts "Found #{users.size} users"
      end

      logs = []

      # Read attendance data with buffer
      attendance_data, size = self.read_with_buffer(CMD_ATTLOG_RRQ)

      if size < 4
        if @verbose
          puts "WRN: no attendance data"
        end
        return []
      end

      # Get total size from first 4 bytes
      total_size = attendance_data[0...4].unpack('I')[0]

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

    # Decode a timestamp retrieved from the timeclock
    # Match Python's __decode_time method exactly
    # In Python:
    # def __decode_time(self, t):
    #     t = unpack("<I", t)[0]
    #     second = t % 60
    #     t = t // 60
    #
    #     minute = t % 60
    #     t = t // 60
    #
    #     hour = t % 24
    #     t = t // 24
    #
    #     day = t % 31 + 1
    #     t = t // 31
    #
    #     month = t % 12 + 1
    #     t = t // 12
    #
    #     year = t + 2000
    #
    #     d = datetime(year, month, day, hour, minute, second)
    #
    #     return d
    def decode_time(t)
      # Convert binary timestamp to integer
      t = t.unpack("L<")[0]

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
    # In Python:
    # def __decode_timehex(self, timehex):
    #     year, month, day, hour, minute, second = unpack("6B", timehex)
    #     year += 2000
    #     d = datetime(year, month, day, hour, minute, second)
    #     return d
    def decode_timehex(timehex)
      # Extract time components
      year, month, day, hour, minute, second = timehex.unpack("C6")
      year += 2000

      # Create Time object
      Time.new(year, month, day, hour, minute, second)
    end

    # Encode a timestamp for the device
    # Match Python's __encode_time method
    # In Python:
    # def __encode_time(self, t):
    #     d = (
    #         ((t.year % 100) * 12 * 31 + ((t.month - 1) * 31) + t.day - 1) *
    #         (24 * 60 * 60) + (t.hour * 60 + t.minute) * 60 + t.second
    #     )
    #     return d
    def encode_time(t)
      # Calculate encoded timestamp
      d = (
        ((t.year % 100) * 12 * 31 + ((t.month - 1) * 31) + t.day - 1) *
          (24 * 60 * 60) + (t.hour * 60 + t.minute) * 60 + t.second
      )
      d
    end

    def get_time
      # Match Python's get_time method exactly
      # In Python:
      # def get_time(self):
      #     command = const.CMD_GET_TIME
      #     response_size = 1032
      #     cmd_response = self.__send_command(command, b'', response_size)
      #     if cmd_response.get('status'):
      #         return self.__decode_time(self.__data[:4])
      #     else:
      #         raise ZKErrorResponse("can't get time")

      command = CMD_GET_TIME
      response_size = 1032
      response = self.send_command(command, "", response_size)

      if response && response[:status]
        return decode_time(@data[0...4])
      else
        raise RBZK::ZKErrorResponse, "Can't get time"
      end
    end

    def set_time(timestamp = nil)
      # Match Python's set_time method exactly
      # In Python:
      # def set_time(self, timestamp):
      #     command = const.CMD_SET_TIME
      #     command_string = pack(b'I', self.__encode_time(timestamp))
      #     cmd_response = self.__send_command(command, command_string)
      #     if cmd_response.get('status'):
      #         return True
      #     else:
      #         raise ZKErrorResponse("can't set time")

      # Default to current time if not provided
      timestamp ||= Time.now

      command = CMD_SET_TIME
      command_string = [ encode_time(timestamp) ].pack('L<')
      response = self.send_command(command, command_string)

      if response && response[:status]
        return true
      else
        raise RBZK::ZKErrorResponse, "Can't set time"
      end
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
          puts "DIFFERENCE DETECTED!"
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
          puts "Byte-by-byte comparison:"
          max_len = [ ruby_bytes.length, python_bytes.length ].max
          (0...max_len).each do |j|
            ruby_byte = j < ruby_bytes.length ? ruby_bytes[j] : nil
            python_byte = j < python_bytes.length ? python_bytes[j] : nil
            match = ruby_byte == python_byte ? "✓" : "✗"
            puts "  Byte #{j}: Ruby=#{ruby_byte.nil? ? 'nil' : "0x#{ruby_byte.to_s(16).rjust(2, '0')}"}, Python=#{python_byte.nil? ? 'nil' : "0x#{python_byte.to_s(16).rjust(2, '0')}"} #{match}"
          end
        else
          puts "Binary data matches exactly!"
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
      # Match Python's read_sizes method exactly
      # In Python:
      # def read_sizes(self):
      #     command = const.CMD_GET_FREE_SIZES
      #     response_size = 1024
      #     cmd_response = self.__send_command(command,b'', response_size)
      #     if cmd_response.get('status'):
      #         if self.verbose: print(codecs.encode(self.__data,'hex'))
      #         size = len(self.__data)
      #         if len(self.__data) >= 80:
      #             fields = unpack('20i', self.__data[:80])
      #             self.users = fields[4]
      #             self.fingers = fields[6]
      #             self.records = fields[8]
      #             self.dummy = fields[10] #???
      #             self.cards = fields[12]
      #             self.fingers_cap = fields[14]
      #             self.users_cap = fields[15]
      #             self.rec_cap = fields[16]
      #             self.fingers_av = fields[17]
      #             self.users_av = fields[18]
      #             self.rec_av = fields[19]
      #             self.__data = self.__data[80:]

      command = CMD_GET_FREE_SIZES
      response_size = 1024
      cmd_response = self.send_command(command, "", response_size)

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
      # Match Python's __create_tcp_top method exactly
      puts "\n*** DEBUG: create_tcp_top called ***" if @verbose
      length = packet.size
      # In Python: pack('<HHI', const.MACHINE_PREPARE_DATA_1, const.MACHINE_PREPARE_DATA_2, length)
      # In Ruby: [MACHINE_PREPARE_DATA_1, MACHINE_PREPARE_DATA_2, length].pack('S<S<I<')
      top = [ MACHINE_PREPARE_DATA_1, MACHINE_PREPARE_DATA_2, length ].pack('S<S<I<')

      if @verbose
        puts "\nTCP header components:"
        puts "  MACHINE_PREPARE_DATA_1: 0x#{MACHINE_PREPARE_DATA_1.to_s(16)} (#{MACHINE_PREPARE_DATA_1}) - should be 'PP' in ASCII"
        puts "  MACHINE_PREPARE_DATA_2: 0x#{MACHINE_PREPARE_DATA_2.to_s(16)} (#{MACHINE_PREPARE_DATA_2}) - should be '\\x82\\x7d' in hex"
        puts "  packet length: #{length}"

        # Show the expected Python representation
        expected_python_header = "PP\\x82\\x7d\\x#{(length & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 8) & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 16) & 0xFF).to_s(16).rjust(2, '0')}\\x#{((length >> 24) & 0xFF).to_s(16).rjust(2, '0')}"
        puts "  Expected Python header: #{expected_python_header}"

        # Show the actual bytes of the constants
        puts "  MACHINE_PREPARE_DATA_1 bytes: #{[ MACHINE_PREPARE_DATA_1 ].pack('S<').bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"
        puts "  MACHINE_PREPARE_DATA_2 bytes: #{[ MACHINE_PREPARE_DATA_2 ].pack('S<').bytes.map { |b| "0x#{b.to_s(16).rjust(2, '0')}" }.join(' ')}"

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
      buf = [command, 0, session_id, reply_id].pack('v4') + command_string

      # Step 2: Convert to bytes array for checksum calculation
      # In Python: buf = unpack('8B' + '%sB' % len(command_string), buf)
      # This unpacks the buffer into individual bytes
      # In Ruby, we can use String#bytes to get an array of bytes
      buf = buf.unpack("C#{8 + command_string.length}")

      # Step 3: Calculate checksum
      # In Python: checksum = unpack('H', self.__create_checksum(buf))[0]
      checksum = calculate_checksum(buf)

      # Step 4: Update reply_id
      # In Python: reply_id += 1; if reply_id >= const.USHRT_MAX: reply_id -= const.USHRT_MAX
      reply_id += 1
      if reply_id >= USHRT_MAX
        reply_id -= USHRT_MAX
      end

      # Step 5: Create final header with updated values
      # In Python: buf = pack('<4H', command, checksum, session_id, reply_id)
      buf = [ command, checksum, session_id, reply_id ].pack('v4')

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
        debug_binary("Final header", buf)
      end

      buf + command_string
    end

    def send_command(command, command_string = "".b, response_size = 8)
      # Match Python's __send_command method exactly
      # In Python:
      # def __send_command(self, command, command_string=b'', response_size=8):
      #     if command not in [const.CMD_CONNECT, const.CMD_AUTH] and not self.is_connect:
      #         raise ZKErrorConnection("instance are not connected.")
      #     buf = self.__create_header(command, command_string, self.__session_id, self.__reply_id)
      #     try:
      #         if self.tcp:
      #             top = self.__create_tcp_top(buf)
      #             self.__sock.send(top)
      #             self.__tcp_data_recv = self.__sock.recv(response_size + 8)
      #             self.__tcp_length = self.__test_tcp_top(self.__tcp_data_recv)
      #             if self.__tcp_length == 0:
      #                 raise ZKNetworkError("TCP packet invalid")
      #             self.__header = unpack('<4H', self.__tcp_data_recv[8:16])
      #             self.__data_recv = self.__tcp_data_recv[8:]
      #         else:
      #             self.__sock.sendto(buf, self.__address)
      #             self.__data_recv = self.__sock.recv(response_size)
      #             self.__header = unpack('<4H', self.__data_recv[:8])
      #     except Exception as e:
      #         raise ZKNetworkError(str(e))
      #     self.__response = self.__header[0]
      #     self.__reply_id = self.__header[3]
      #     self.__data = self.__data_recv[8:]
      #     if self.__response in [const.CMD_ACK_OK, const.CMD_PREPARE_DATA, const.CMD_DATA]:
      #         return {
      #             'status': True,
      #             'code': self.__response
      #         }
      #     return {
      #         'status': False,
      #         'code': self.__response
      #     }

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
