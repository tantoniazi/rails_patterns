# frozen_string_literal: true

module UseCases
  class DestroyPost
    def initialize(post_repo: Infrastructure::Repositories::PostRepository.new)
      @post_repo = post_repo
    end

    def call(post:)
      @post_repo.delete(post.id)
      Domain::Result.ok
    end
  end
end
