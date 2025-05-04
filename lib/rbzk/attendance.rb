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
    
    def to_s
      "#{@user_id} #{@timestamp} #{@status} #{@punch} #{@uid}"
    end
  end
end
