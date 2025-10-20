# frozen_string_literal: true

module RBZK
  class Finger
    attr_accessor :uid, :fid, :valid, :template, :size

    def initialize(uid, fid, valid, template = '')
      @uid = uid
      @fid = fid
      @valid = valid
      @template = template
      @size = template.length
    end

    # Pack the finger data into a binary string (full data)
    def repack
      [@size + 6, @uid, @fid, @valid].pack('S<S<CC') + @template
    end

    # Pack only the template data into a binary string
    def repack_only
      [@size].pack('S<') + @template
    end

    def to_s
      "#{@uid} #{@fid} #{@valid} #{@template.length}"
    end
  end
end
