require 'rbzk'

RSpec.describe RBZK::Attendance do
  let(:timestamp) { Time.new(2020, 1, 1, 8, 0, 0) }

  it 'correctly identifies check in and check out by punch field' do
    a_in = RBZK::Attendance.new('1', timestamp, 0, 0, 1)
    a_out = RBZK::Attendance.new('1', timestamp, 0, 1, 1)

    expect(a_in.check_in?).to be true
    expect(a_in.check_out?).to be false
    expect(a_in.punch_name).to eq('Check In')

    expect(a_out.check_in?).to be false
    expect(a_out.check_out?).to be true
    expect(a_out.punch_name).to eq('Check Out')
  end

  it 'returns human readable names for other statuses' do
    expect(RBZK::Attendance.new('1', timestamp, 2, 0, 1).status).to eq(2)
    expect(RBZK::Attendance.new('1', timestamp, 3, 0, 1).status).to eq(3)
    expect(RBZK::Attendance.new('1', timestamp, 4, 0, 1).status).to eq(4)
    expect(RBZK::Attendance.new('1', timestamp, 5, 0, 1).status).to eq(5)
    expect(RBZK::Attendance.new('1', timestamp, 99, 0, 1).status).to eq(99)
  end
end
