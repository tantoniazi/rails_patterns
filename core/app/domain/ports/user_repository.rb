# frozen_string_literal: true

module Ports
  module UserRepository
    def find(id) = raise NotImplementedError
    def find_by_email(email) = raise NotImplementedError
    def save(user) = raise NotImplementedError
  end
end
