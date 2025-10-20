# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Binary Compatibility' do
  include BinaryCompatibilityHelpers

  describe 'read chunks' do
    context 'with session_id=18581' do
      let(:command) { 1504 }
      let(:reply_id) { 3 }
      let(:session_id) { 18_581 }
      let(:expected_output) { "\xe0\x05\x00\x00\x95\x48\x03\x00\x00\x00\x00\x00\x54\x07\x00\x00".b }
      let(:command_string) { "\x00\x00\x00\x00\x54\x07\x00\x00".b }

      it "matches Python's binary output" do
        verify_binary_compatibility(
          command,
          session_id,
          reply_id,
          command_string,
          expected_output,
          'session_id=18581'
        )
      end
    end
  end

  describe 'connect command' do
    context 'with session_id=0' do
      let(:command) { 1000 }
      let(:reply_id) { 65_534 }
      let(:session_id) { 0 }
      let(:expected_output) { "\xe8\x03\x00\x00\x00\x00\xfe\xff".b }
      let(:command_string) { ''.b }

      it "matches Python's binary output" do
        verify_binary_compatibility(
          command,
          session_id,
          reply_id,
          command_string,
          expected_output,
          'session_id=0'
        )
      end
    end

    # Add more test cases here easily with the same pattern
    # context "with session_id=12345" do
    #   let(:session_id) { 12345 }
    #   let(:expected_output) { "expected_binary".b }
    #
    #   it "matches Python's binary output" do
    #     verify_binary_compatibility(
    #       command,
    #       session_id,
    #       reply_id,
    #       command_string,
    #       expected_output,
    #       'session_id=12345'
    #     )
    #   end
    # end
  end
end
