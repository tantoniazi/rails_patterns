# frozen_string_literal: true

module Repositories
  class PostRepository
    include Domain::Ports::PostRepository

    def initialize(paginator: Pagination::PagyPaginator.new)
      @paginator = paginator
    end

    def all(filters: {}, page: 1, per_page: Pagination::PagyPaginator::DEFAULT_PER_PAGE)
      scope = base_scope(filters)
      @paginator.paginate(scope, page: page, per_page: per_page)
    end

    def find(id)
      ::Post.includes(:user).find_by(id: id)
    end

    def build(user:, attributes:)
      user.posts.build(attributes)
    end

    def save(post)
      post.save
      post
    end

    def delete(id)
      ::Post.find(id).destroy!
    end

    def to_entity(post)
      return unless post

      Domain::Entities::Post.new(
        id: post.id,
        user_id: post.user_id,
        title: post.title,
        body: post.body,
        status: post.status,
        slug: post.slug,
        published_at: post.published_at,
        views_count: post.views_count
      )
    end

    private

    def base_scope(filters)
      scope = ::Post.recent.includes(:user)

      if filters[:q].present?
        scope = ::Post.ransack(filters[:q]).result(distinct: true)
        scope = scope.recent.includes(:user)
      end

      scope = scope.where(status: filters[:status]) if filters[:status].present?
      scope = scope.by_author(filters[:user_id]) if filters[:user_id].present?
      scope
    end
  end
end
