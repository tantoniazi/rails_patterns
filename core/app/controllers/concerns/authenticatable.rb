# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
  end

  private

  def authenticate_user!
    token = bearer_token
    return render_unauthorized unless token

    payload = Infrastructure::Auth::JwtService.decode(token)
    return render_unauthorized unless payload&.dig(:type) == "access"

    @current_user = User.active.find_by(id: payload[:user_id])
    render_unauthorized unless @current_user
  end

  def current_user
    @current_user
  end

  def bearer_token
    header = request.headers["Authorization"]
    return unless header&.start_with?("Bearer ")

    header.split(" ", 2).last
  end

  def render_unauthorized
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
