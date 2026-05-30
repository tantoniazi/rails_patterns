# frozen_string_literal: true

module Ports
  module PostRepository
    def all(filters: {}, page: 1, per_page: 20) = raise NotImplementedError
    def find(id) = raise NotImplementedError
    def save(post) = raise NotImplementedError
    def delete(id) = raise NotImplementedError
  end
end
