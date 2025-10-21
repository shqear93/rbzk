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
        calls << [command, command_string, response_size]
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
end
