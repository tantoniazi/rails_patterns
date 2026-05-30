# frozen_string_literal: true

class PostEventsConsumer < ApplicationConsumer
  def consume
    use_case = Domain::UseCases::ProcessPostEvent.new

    messages.each do |message|
      payload = parse_payload(message.payload)
      event_id = payload.fetch("event_id")

      use_case.call(
        event_id: event_id,
        topic: message.topic,
        partition: message.partition,
        offset: message.offset,
        payload: payload
      )
    end
  end

  private

  def parse_payload(raw_payload)
    return raw_payload if raw_payload.is_a?(Hash)

    JSON.parse(raw_payload)
  end
end
