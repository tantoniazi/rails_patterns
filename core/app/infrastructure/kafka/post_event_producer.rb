# frozen_string_literal: true

module Kafka
  class PostEventProducer
    TOPIC = "post_events"

    include Domain::Ports::EventPublisher

    def publish(**event_data)
      return if Rails.env.test?

      Karafka.producer.produce_sync(
        topic: TOPIC,
        payload: event_data.to_json,
        key: event_data[:post_id].to_s
      )
    rescue StandardError => e
      Rails.logger.error("[PostEventProducer] #{e.message}")
    end

    def publish_created(post)
      publish(
        event: "post.created",
        post_id: post.id,
        user_id: post.user_id,
        status: post.status,
        occurred_at: Time.current.iso8601
      )
    end

    def publish_published(post)
      publish(
        event: "post.published",
        post_id: post.id,
        user_id: post.user_id,
        slug: post.slug,
        occurred_at: Time.current.iso8601
      )

      PostPublishedJob.perform_later(post.id)
    end
  end
end
