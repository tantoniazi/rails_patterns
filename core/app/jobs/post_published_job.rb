# frozen_string_literal: true

class PostPublishedJob < ApplicationJob
  queue_as :default

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return unless post&.published?

    Rails.logger.info("[PostPublishedJob] Post #{post.id} published by user #{post.user_id}")
  end
end
