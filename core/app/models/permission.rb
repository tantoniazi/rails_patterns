# frozen_string_literal: true

class Permission < ApplicationRecord
  validates :role, presence: true
  validates :resource, presence: true
  validates :action, presence: true
  validates :role, uniqueness: { scope: %i[resource action] }
end
