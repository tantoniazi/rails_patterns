json.data @summaries do |summary|
  json.status summary.status
  json.posts_count summary.posts_count
  json.total_views summary.total_views
  json.latest_post_at summary.latest_post_at
end
