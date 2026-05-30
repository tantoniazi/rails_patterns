# frozen_string_literal: true

module AuthHelpers
  def auth_headers(user)
    token = Infrastructure::Auth::JwtService.encode(user_id: user.id)
    { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end
end
