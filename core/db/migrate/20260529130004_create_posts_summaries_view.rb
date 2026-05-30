# frozen_string_literal: true

class CreatePostsSummariesView < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      CREATE MATERIALIZED VIEW posts_summaries AS
      SELECT
        row_number() OVER (ORDER BY status) AS id,
        status,
        COUNT(*)::bigint AS posts_count,
        COALESCE(SUM(views_count), 0)::bigint AS total_views,
        MAX(created_at) AS latest_post_at
      FROM posts
      GROUP BY status
      WITH DATA
    SQL

    execute "CREATE UNIQUE INDEX index_posts_summaries_on_status ON posts_summaries (status)"
  end

  def down
    execute "DROP MATERIALIZED VIEW IF EXISTS posts_summaries"
  end
end
