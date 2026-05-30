json.id @user.id
json.name @user.name
json.email @user.email
json.role @user.role
json.active @user.active
json.profile do
  json.bio @user.profile&.bio
  json.avatar_url @user.profile&.avatar_url
end
