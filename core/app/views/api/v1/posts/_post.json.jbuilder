json.id post.id
json.title post.title
json.body post.body
json.status post.status
json.slug post.slug
json.published_at post.published_at
json.views_count post.views_count
json.created_at post.created_at
json.updated_at post.updated_at
json.user do
  json.id post.user.id
  json.name post.user.name
end
