json.access_token @tokens[:access_token]
json.refresh_token @tokens[:refresh_token]
json.token_type @tokens[:token_type]
json.expires_in @tokens[:expires_in]
json.user do
  json.id @user.id
  json.name @user.name
  json.email @user.email
  json.role @user.role
end
