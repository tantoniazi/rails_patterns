# frozen_string_literal: true

module Ports
  class ProcessedEventRepository
    def processed?(event_id)
      raise NotImplementedError
    end

    def record!(event_id:, topic:, partition:, offset:, payload:)
      raise NotImplementedError
    end
  end
end
