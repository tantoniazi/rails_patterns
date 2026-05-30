# frozen_string_literal: true

class PostsSummary < ApplicationRecord
  self.table_name = "posts_summaries"
  self.primary_key = "id"

  def readonly?
    true
  end

  def self.refresh!
    connection.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY posts_summaries")
  rescue ActiveRecord::StatementInvalid
    connection.execute("REFRESH MATERIALIZED VIEW posts_summaries")
  end
end
