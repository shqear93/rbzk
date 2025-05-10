# frozen_string_literal: true

module RBZK
  class Finger
    attr_accessor :uid, :fid, :valid, :template

    def initialize(uid, fid, valid, template = "")
      @uid = uid
      @fid = fid
      @valid = valid
      @template = template
    end

    def to_s
      "#{@uid} #{@fid} #{@valid} #{@template.length}"
    end
  end
end
