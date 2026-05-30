# frozen_string_literal: true

module UseCases
  class UpdatePost
    def initialize(
      post_repo: Infrastructure::Repositories::PostRepository.new,
      event_publisher: Infrastructure::Kafka::PostEventProducer.new
    )
      @post_repo = post_repo
      @event_publisher = event_publisher
    end

    def call(post:, attributes:)
      was_published = post.published?

      unless post.update(attributes)
        return Domain::Result.fail(post.errors.full_messages)
      end

      @event_publisher.publish_published(post) if !was_published && post.published?
      Domain::Result.ok(post)
    end
  end
end
