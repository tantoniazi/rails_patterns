json.data @posts do |post|
  json.partial! "api/v1/posts/post", post: post
end
json.meta do
  json.total_count @posts.size
end
