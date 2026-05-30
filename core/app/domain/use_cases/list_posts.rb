# frozen_string_literal: true

module UseCases
  class ListPosts
    def initialize(post_repo: Infrastructure::Repositories::PostRepository.new)
      @post_repo = post_repo
    end

    def call(filters: {})
      posts = @post_repo.all(filters: filters)
      Domain::Result.ok(posts)
    end
  end
end
