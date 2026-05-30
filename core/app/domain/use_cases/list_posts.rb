# frozen_string_literal: true

module UseCases
  class ListPosts
    def initialize(post_repo: Infrastructure::Repositories::PostRepository.new)
      @post_repo = post_repo
    end

    def call(filters: {}, page: 1, per_page: Infrastructure::Pagination::PagyPaginator::DEFAULT_PER_PAGE)
      collection = @post_repo.all(filters: filters, page: page, per_page: per_page)
      Domain::Result.ok(collection)
    end
  end
end
