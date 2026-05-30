# frozen_string_literal: true

module Pagination
  class PagyPaginator
    DEFAULT_PER_PAGE = 20
    MAX_PER_PAGE = 100

    def paginate(scope, page:, per_page:)
      page = [page.to_i, 1].max
      per_page = per_page.to_i.clamp(1, MAX_PER_PAGE)
      total_count = scope.count
      pagy = Pagy.new(count: total_count, page: page, limit: per_page)
      records = scope.offset(pagy.offset).limit(pagy.limit)

      Domain::Entities::PaginatedCollection.new(
        records: records,
        page: pagy.page,
        per_page: pagy.limit,
        total_count: pagy.count,
        total_pages: pagy.pages
      )
    end
  end
end
