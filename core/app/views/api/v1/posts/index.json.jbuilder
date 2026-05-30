json.data @posts do |post|
  json.partial! "api/v1/posts/post", post: post
end
json.meta do
  json.page @pagination.page
  json.per_page @pagination.per_page
  json.total_count @pagination.total_count
  json.total_pages @pagination.total_pages
end
