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

    def initialize(uid = 0, user_id = "", name = "", privilege = 0, password = "", group_id = 0, card = 0)
      @uid = uid
      @user_id = user_id
      @name = name
      @privilege = privilege
      @password = password
      @group_id = group_id
      @card = card
    end

    def to_s
      "#{@uid} #{@user_id} #{@name} #{@privilege} #{@password} #{@group_id} #{@card}"
    end
  end
end
