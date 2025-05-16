RSpec.describe RBZK::User do
  describe '#initialize' do
    it 'creates a new User instance with default values' do
      user = RBZK::User.new
      expect(user).to be_a(RBZK::User)
      expect(user.uid).to eq(0)
      expect(user.name).to eq("")
      expect(user.privilege).to eq(0)
      expect(user.password).to eq("")
      expect(user.group_id).to eq("")
      expect(user.user_id).to eq("")
      expect(user.card).to eq(0)
    end

    it 'creates a new User instance with custom values' do
      user = RBZK::User.new(1, "John Doe", 14, "password", "1", "123", 12345)
      expect(user).to be_a(RBZK::User)
      expect(user.uid).to eq(1)
      expect(user.name).to eq("John Doe")
      expect(user.privilege).to eq(14)
      expect(user.password).to eq("password")
      expect(user.group_id).to eq("1")
      expect(user.user_id).to eq("123")
      expect(user.card).to eq(12345)
    end
  end

  describe '#to_s' do
    it 'returns a string representation of the user' do
      user = RBZK::User.new(1, "John Doe", 14, "password", "1", "123", 12345)
      expect(user.to_s).to eq("1 123 John Doe 14 password 1 12345")
    end
  end

  describe '.encoding' do
    it 'gets and sets the encoding' do
      RBZK::User.encoding = "ASCII"
      expect(RBZK::User.encoding).to eq("ASCII")

      # Reset to default for other tests
      RBZK::User.encoding = "UTF-8"
    end
  end
end
