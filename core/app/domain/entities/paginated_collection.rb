# frozen_string_literal: true

module Entities
  PaginatedCollection = Data.define(:records, :page, :per_page, :total_count, :total_pages)
end
