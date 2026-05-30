# frozen_string_literal: true

class ProcessedEvent < ApplicationRecord
  validates :event_id, presence: true, uniqueness: true
  validates :topic, :partition, :offset, :processed_at, presence: true
end
