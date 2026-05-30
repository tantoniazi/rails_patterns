# frozen_string_literal: true

module Ports
  module AccountRepository
    def find(id)
      raise NotImplementedError
    end

    def find_by_user_id(user_id)
      raise NotImplementedError
    end

    def save(account)
      raise NotImplementedError
    end
  end
end
