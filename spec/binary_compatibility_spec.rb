# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe "Binary Compatibility" do
  include BinaryCompatibilityHelpers

  # Common values used in all tests
  let(:command) { 1504 }
  let(:reply_id) { 3 }
  let(:command_string) { "\x00\x00\x00\x00\x54\x07\x00\x00".b }

  describe "header creation" do
    context "with session_id=13838 (special case)" do
      let(:session_id) { 13838 }
      let(:expected_output) { "\xe0\x05\x00\x00\x0d\x34\x03\x00\x00\x00\x00\x00\x54\x07\x00\x00".b }

      it "matches Python's binary output" do
        verify_binary_compatibility(
          command,
          session_id,
          reply_id,
          command_string,
          expected_output,
          'session_id=13838'
        )
      end
    end

    context "with session_id=18020" do
      let(:session_id) { 18020 }
      let(:expected_output) { "\xe0\x05\x00\x00\x64\x46\x03\x00\x00\x00\x00\x00\x54\x07\x00\x00".b }

      it "matches Python's binary output" do
        verify_binary_compatibility(
          command,
          session_id,
          reply_id,
          command_string,
          expected_output,
          'session_id=18020'
        )
      end
    end

    context "with session_id=18581" do
      let(:session_id) { 18581 }
      let(:expected_output) { "\xe0\x05\x00\x00\x95\x48\x03\x00\x00\x00\x00\x00\x54\x07\x00\x00".b }

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
