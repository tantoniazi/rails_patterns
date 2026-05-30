# frozen_string_literal: true

module UseCases
  class CreatePost
    def initialize(
      post_repo: Infrastructure::Repositories::PostRepository.new,
      event_publisher: Infrastructure::Kafka::PostEventProducer.new
    )
      @post_repo = post_repo
      @event_publisher = event_publisher
    end

    def call(user:, attributes:)
      post = @post_repo.build(user: user, attributes: attributes)

      unless post.save
        return Domain::Result.fail(post.errors.full_messages)
      end

      @event_publisher.publish_created(post) if post.published?
      Domain::Result.ok(post)
    end
  end
end
