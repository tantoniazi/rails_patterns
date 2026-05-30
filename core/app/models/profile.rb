# frozen_string_literal: true

class Profile < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true
end
