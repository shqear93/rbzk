# frozen_string_literal: true

module RBZK
  class User
    attr_accessor :uid, :user_id, :name, :privilege, :password, :group_id, :card

    @@encoding = 'UTF-8'

    def self.encoding=(encoding)
      @@encoding = encoding
    end

    def self.encoding
      @@encoding
    end

    # Match Python's User constructor exactly
    # In Python:
    # def __init__(self, uid, name, privilege, password='', group_id='', user_id='', card=0):
    def initialize(uid = 0, name = '', privilege = 0, password = '', group_id = '', user_id = '', card = 0)
      @uid = uid
      @name = name
      @privilege = privilege
      @password = password
      @group_id = group_id
      @user_id = user_id
      @card = card
    end

    # Pack the user data into a binary string for ZK6 devices (size 29)
    def repack29
      [2, @uid, @privilege].pack('CS<C') +
        @password.encode(@@encoding, invalid: :replace, undef: :replace).ljust(5, "\x00")[0...5] +
        @name.encode(@@encoding, invalid: :replace, undef: :replace).ljust(8, "\x00")[0...8] +
        [@card, 0, @group_id.to_i, 0, @user_id.to_i].pack('L<CS<S<L<')
    end

    # Pack the user data into a binary string for ZK8 devices (size 73)
    def repack73
      [2, @uid, @privilege].pack('CS<C') +
        @password.encode(@@encoding, invalid: :replace, undef: :replace).ljust(8, "\x00")[0...8] +
        @name.encode(@@encoding, invalid: :replace, undef: :replace).ljust(24, "\x00")[0...24] +
        [@card, 1].pack('L<C') +
        @group_id.to_s.encode(@@encoding, invalid: :replace, undef: :replace).ljust(7, "\x00")[0...7] +
        "\x00" +
        @user_id.to_s.encode(@@encoding, invalid: :replace, undef: :replace).ljust(24, "\x00")[0...24]
    end

    # Check if the user is disabled
    def is_disabled?
      (@privilege & 1) != 0
    end

    # Check if the user is enabled
    def is_enabled?
      !is_disabled?
    end

    # Get the user type
    def usertype
      @privilege & 0xE
    end

    def to_s
      "#{@uid} #{@user_id} #{@name} #{@privilege} #{@password} #{@group_id} #{@card}"
    end
  end
end
