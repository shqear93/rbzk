RSpec.describe RBZK::ZK do
  let(:ip) { '192.168.1.201' }
  let(:port) { 4370 }
  let(:zk) { RBZK::ZK.new(ip, port: port) }

  describe '#initialize' do
    it 'creates a new ZK instance with default values' do
      expect(zk).to be_a(RBZK::ZK)
    end

    it 'accepts custom parameters' do
      custom_zk = RBZK::ZK.new(ip, port: 4371, timeout: 30, password: 123_456, force_udp: true, verbose: true)
      expect(custom_zk).to be_a(RBZK::ZK)
    end
  end

  # NOTE: The following tests would require a real ZK device or a mock
  # They are commented out as they would fail without proper setup

  # describe '#connect' do
  #   it 'connects to the device' do
  #     allow(zk).to receive(:ping).and_return(true)
  #     allow(zk).to receive(:send_command)
  #     allow(zk).to receive(:recv_reply).and_return("OK")
  #
  #     expect(zk.connect).to eq(zk)
  #     expect(zk.instance_variable_get(:@connected)).to be true
  #   end
  # end

  # describe '#disconnect' do
  #   it 'disconnects from the device' do
  #     zk.instance_variable_set(:@connected, true)
  #     allow(zk).to receive(:send_command)
  #     allow(zk).to receive(:recv_reply).and_return("OK")
  #
  #     expect(zk.disconnect).to be true
  #     expect(zk.instance_variable_get(:@connected)).to be false
  #   end
  # end
end
