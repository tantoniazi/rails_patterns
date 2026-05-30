# frozen_string_literal: true

module Entities
  Post = Data.define(:id, :user_id, :title, :body, :status, :slug, :published_at, :views_count) do
    def published?
      status.to_s == "published"
    end
  end
end
