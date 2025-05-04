# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'date'

module RBZK
  class ZK
    include Constants
    
    def initialize(ip, port: 4370, timeout: 60, password: 0, force_udp: false, omit_ping: false, verbose: false, encoding: 'UTF-8')
      User.encoding = encoding
      @address = [ip, port]
      @socket = UDPSocket.new
      @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [timeout, 0].pack('l_*'))
      
      @ip = ip
      @port = port
      @timeout = timeout
      @password = password
      @force_udp = force_udp
      @omit_ping = omit_ping
      @verbose = verbose
      @encoding = encoding
      
      @reply_id = -1 + 65536
      @data_recv = nil
      @session_id = 0
      @tcp = nil
      @connected = false
      @next_uid = 1
      @users = {}
      @attendances = []
      @fingers = {}
      @tcp_header_size = 8
    end
    
    def connect
      return self if @connected
      
      unless @omit_ping
        ping_ok = ping
        unless ping_ok
          raise ZKNetworkError, "Can't reach device at #{@ip}:#{@port}"
        end
      end
      
      self.send_command(CMD_CONNECT)
      self.recv_reply
      
      @connected = true
      
      if @password && @password != 0
        self.send_command(CMD_AUTH, [@password].pack('L<'))
        self.recv_reply
      end
      
      self
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
      
      self.send_command(CMD_PREPARE_DATA, [FCT_USER].pack('C'))
      self.recv_reply
      
      data_size = self.recv_long
      users_data = self.recv_chunk(data_size)
      
      if users_data && !users_data.empty?
        offset = 0
        while offset < data_size
          if data_size - offset >= 28
            user_info = users_data[offset..offset+28]
            uid, user_id_raw, name_raw, privilege, password_raw, group_id, card = user_info.unpack('S<A9A24CCA14S<')
            
            user_id = user_id_raw.strip
            name = name_raw.strip
            password = password_raw.strip
            
            users << User.new(uid, user_id, name, privilege, password, group_id, card)
          end
          
          offset += 28
        end
      end
      
      users
    end
    
    def get_attendance_logs
      logs = []
      
      self.send_command(CMD_PREPARE_DATA, [FCT_ATTLOG].pack('C'))
      self.recv_reply
      
      data_size = self.recv_long
      logs_data = self.recv_chunk(data_size)
      
      if logs_data && !logs_data.empty?
        offset = 0
        while offset < data_size
          if data_size - offset >= 16
            log_info = logs_data[offset..offset+16]
            user_id, timestamp, status, punch, uid = log_info.unpack('S<L<CCS<')
            
            time = Time.at(timestamp)
            logs << Attendance.new(user_id, time, status, punch, uid)
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
      
      data = [time.year, time.month, time.day, time.hour, time.min, time.sec].pack('S<6')
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
    
    private
    
    def ping
      begin
        Timeout.timeout(5) do
          s = TCPSocket.new(@ip, @port)
          s.close
          return true
        end
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        return false
      end
    end
    
    def create_header(command, session_id, reply_id, command_string = '')
      buf = []
      
      buf << command
      buf << 0
      buf << session_id
      buf << reply_id
      
      if command_string && !command_string.empty?
        buf << command_string.bytesize
        buf << 0
        buf << 0
        buf << 0
      else
        buf << 0
        buf << 0
        buf << 0
        buf << 0
      end
      
      buf.pack('S<8')
    end
    
    def send_command(command, command_string = '')
      buf = create_header(command, @session_id, @reply_id, command_string)
      buf += command_string if command_string && !command_string.empty?
      
      if @verbose
        puts "Sending command #{command} with session id #{@session_id} and reply id #{@reply_id}"
      end
      
      if @tcp
        @tcp.write(buf)
      else
        @socket.send(buf, 0, @ip, @port)
      end
      
      @reply_id = (@reply_id + 1) % USHRT_MAX
      @reply_id = USHRT_MAX if @reply_id == 0
    end
    
    def recv_reply
      if @tcp
        reply = @tcp.read(@tcp_header_size)
        return nil unless reply && reply.size >= @tcp_header_size
        
        command, checksum, session_id, reply_id, reply_size = reply.unpack('S<5')
        
        if reply_size > 0
          data = @tcp.read(reply_size)
          reply += data
        end
      else
        begin
          reply, addr = @socket.recvfrom(1024)
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK
          raise ZKErrorResponse, "Timeout waiting for response"
        end
      end
      
      if reply && reply.size >= 8
        command, checksum, session_id, reply_id, reply_size = reply.unpack('S<5')
        
        if @verbose
          puts "Received reply for command #{command} with session id #{session_id} and reply id #{reply_id}"
        end
        
        if command == CMD_ACK_OK
          @session_id = session_id
          return reply
        elsif command == CMD_ACK_ERROR
          raise ZKErrorResponse, "Error response from device: #{command}"
        elsif command == CMD_ACK_DATA
          if reply_size > 0
            @data_recv = reply[8..-1]
            @session_id = session_id
            return reply
          else
            raise ZKErrorResponse, "Received data packet with no data"
          end
        else
          raise ZKErrorResponse, "Invalid response from device: #{command}"
        end
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
      if @data_recv && @data_recv.size >= size
        data = @data_recv[0...size]
        @data_recv = @data_recv[size..-1]
        return data
      end
      
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
      
      k_bytes = [k].pack('L<').unpack('C4')
      k_bytes = [
        k_bytes[0] ^ 'Z'.ord,
        k_bytes[1] ^ 'K'.ord,
        k_bytes[2] ^ 'S'.ord,
        k_bytes[3] ^ 'O'.ord
      ]
      
      k_shorts = [k_bytes.pack('C4')].pack('C4').unpack('S<2')
      k_shorts = [k_shorts[1], k_shorts[0]]
      
      b = 0xff & ticks
      k_bytes = k_shorts.pack('S<2').unpack('C4')
      
      [k_bytes[0] ^ b, k_bytes[1] ^ ticks, k_bytes[2] ^ b, k_bytes[3] ^ ticks].pack('C4')
    end
  end
end
