# frozen_string_literal: true

module RBZK
  class User
    attr_accessor :uid, :user_id, :name, :privilege, :password, :group_id, :card

    @@encoding = "UTF-8"

    def self.encoding=(encoding)
      @@encoding = encoding
    end

    def self.encoding
      @@encoding
    end

    # Match Python's User constructor exactly
    # In Python:
    # def __init__(self, uid, name, privilege, password='', group_id='', user_id='', card=0):
    def initialize(uid = 0, name = "", privilege = 0, password = "", group_id = "", user_id = "", card = 0)
      @uid = uid
      @name = name
      @privilege = privilege
      @password = password
      @group_id = group_id
      @user_id = user_id
      @card = card
    end

    def to_s
      "#{@uid} #{@user_id} #{@name} #{@privilege} #{@password} #{@group_id} #{@card}"
    end
  end
end
