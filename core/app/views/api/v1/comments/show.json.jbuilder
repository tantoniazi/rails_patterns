json.id comment.id
json.body comment.body
json.created_at comment.created_at
json.user do
  json.id comment.user.id
  json.name comment.user.name
end
