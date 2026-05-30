# frozen_string_literal: true

module UseCases
  class ProcessPostEvent
    def initialize(repository: ::Infrastructure::Repositories::ProcessedEventRepository.new)
      @repository = repository
    end

    def call(event_id:, topic:, partition:, offset:, payload:)
      return :already_processed if @repository.processed?(event_id)

      ActiveRecord::Base.transaction do
        ::Infrastructure::Handlers::PostEventHandler.new(payload).call
        @repository.record!(
          event_id: event_id,
          topic: topic,
          partition: partition,
          offset: offset,
          payload: payload
        )
      end

      :processed
    end
  end
end
