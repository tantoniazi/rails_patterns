# frozen_string_literal: true

module Ports
  module PostRepository
    def all(filters: {}) = raise NotImplementedError
    def find(id) = raise NotImplementedError
    def save(post) = raise NotImplementedError
    def delete(id) = raise NotImplementedError
  end
end
