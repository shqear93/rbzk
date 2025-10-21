# frozen_string_literal: true

module RBZK
  class ZKError < StandardError; end

  class ZKNetworkError < ZKError
    def initialize(msg = 'Network error')
      super
    end
  end

  class ZKErrorConnection < ZKError
    def initialize(msg = 'Connection error')
      super
    end
  end

  class ZKErrorResponse < ZKError
    def initialize(msg = 'Invalid response')
      super
    end
  end

  class ZKErrorExists < ZKError
    def initialize(msg = 'Data already exists')
      super
    end
  end
end
