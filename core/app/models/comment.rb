# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
  belongs_to :user

  validates :body, presence: true, length: { minimum: 2, maximum: 2000 }
end
