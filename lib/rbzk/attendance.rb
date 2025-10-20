# frozen_string_literal: true

module RBZK
  class Attendance
    attr_accessor :user_id, :timestamp, :status, :punch, :uid

    def initialize(user_id, timestamp, status, punch, uid)
      @user_id = user_id
      @timestamp = timestamp
      @status = status
      @punch = punch
      @uid = uid
    end

    # Helper predicate for check-in (punch==0)
    def check_in?
      @punch == 0
    end

    # Helper predicate for check-out (punch==1)
    def check_out?
      @punch == 1
    end

    # Human readable punch name (0=Check In, 1=Check Out)
    def punch_name
      case @punch
      when 0 then 'Check In'
      when 1 then 'Check Out'
      else "Punch (#{@punch})"
      end
    end

    def to_s
      "#{@user_id} #{@timestamp} #{@status} #{@punch} #{@uid}"
    end
  end
end
