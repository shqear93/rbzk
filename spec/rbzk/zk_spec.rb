# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RBZK::ZK do
  describe '#set_user' do
    let(:zk) { described_class.new('127.0.0.1', force_udp: true, omit_ping: true) }

    before do
      zk.instance_variable_set(:@connected, true)
    end

    it 'refreshes metadata before assigning a new uid when none is provided' do
      calls = []
      allow(zk).to receive(:send_command) do |command, command_string = ''.b, response_size = 8|
        calls << [ command, command_string, response_size ]
        { status: true, code: RBZK::Constants::CMD_ACK_OK }
      end

      expect(zk).to receive(:get_users) do
        zk.instance_variable_set(:@next_uid, 20)
        zk.instance_variable_set(:@next_user_id, '20')
        []
      end

      expect(zk.set_user(name: 'Test User', user_id: '900')).to be true

      first_call = calls.first
      expect(first_call[0]).to eq(RBZK::Constants::CMD_USER_WRQ)
      expect(first_call[1].bytes.first).to eq(20)
    end
  end

  describe '#enable_device' do
    let(:zk) { described_class.new('127.0.0.1', force_udp: true, omit_ping: true) }

    before do
      zk.instance_variable_set(:@connected, true)
    end

    it 'enables the device when response is OK' do
      allow(zk).to receive(:send_command).and_return({ status: true, code: RBZK::Constants::CMD_ACK_OK })
      expect(zk.enable_device).to be true
      expect(zk.instance_variable_get(:@is_enabled)).to be true
    end

    it 'raises an error when device does not respond OK' do
      allow(zk).to receive(:send_command).and_return({ status: false, code: RBZK::Constants::CMD_ACK_ERROR })
      expect { zk.enable_device }.to raise_error(RBZK::ZKErrorResponse)
    end
  end

  describe '#disable_device' do
    let(:zk) { described_class.new('127.0.0.1', force_udp: true, omit_ping: true) }

    before do
      zk.instance_variable_set(:@connected, true)
    end

    it 'disables the device when response is OK' do
      allow(zk).to receive(:send_command).and_return({ status: true, code: RBZK::Constants::CMD_ACK_OK })
      expect(zk.disable_device).to be true
      expect(zk.instance_variable_get(:@is_enabled)).to be false
    end

    it 'raises an error when device does not respond OK' do
      allow(zk).to receive(:send_command).and_return({ status: false, code: RBZK::Constants::CMD_ACK_ERROR })
      expect { zk.disable_device }.to raise_error(RBZK::ZKErrorResponse)
    end
  end
end
