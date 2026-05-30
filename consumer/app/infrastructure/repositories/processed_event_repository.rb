# frozen_string_literal: true

module Repositories
  class ProcessedEventRepository < Ports::ProcessedEventRepository
    def processed?(event_id)
      ProcessedEvent.exists?(event_id: event_id)
    end

    def record!(event_id:, topic:, partition:, offset:, payload:)
      ProcessedEvent.create!(
        event_id: event_id,
        topic: topic,
        partition: partition,
        offset: offset,
        payload: payload,
        processed_at: Time.current
      )
    end
  end
end
