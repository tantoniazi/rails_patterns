# frozen_string_literal: true

module Handlers
  class PostEventHandler
    SUPPORTED_EVENTS = %w[post.created post.updated post.deleted].freeze

    def initialize(payload)
      @payload = payload
    end

    def call
      event = @payload["event"]

      unless SUPPORTED_EVENTS.include?(event)
        Rails.logger.warn("Unknown post event: #{event.inspect}")
        return
      end

      Rails.logger.info(
        "Handled #{event} for post_id=#{@payload['post_id']} event_id=#{@payload['event_id']}"
      )
    end
  end
end
