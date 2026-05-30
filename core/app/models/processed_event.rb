# frozen_string_literal: true

class ProcessedEvent < ApplicationRecord
  validates :event_id, presence: true, uniqueness: true
end
