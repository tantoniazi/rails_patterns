# frozen_string_literal: true

module Auth
  class JwtService
    SECRET = ENV.fetch("JWT_SECRET") { Rails.application.secret_key_base }
    ACCESS_EXPIRY = 15.minutes
    REFRESH_EXPIRY = 7.days

    class << self
      def encode(user_id:, type: :access)
        expiry = type == :refresh ? REFRESH_EXPIRY : ACCESS_EXPIRY
        payload = {
          user_id: user_id,
          type: type.to_s,
          exp: expiry.from_now.to_i,
          iat: Time.current.to_i
        }
        JWT.encode(payload, SECRET, "HS256")
      end

      def decode(token)
        payload, = JWT.decode(token, SECRET, true, algorithm: "HS256")
        payload.with_indifferent_access
      rescue JWT::DecodeError, JWT::ExpiredSignature
        nil
      end

      def issue_tokens(user_id:)
        {
          access_token: encode(user_id: user_id, type: :access),
          refresh_token: encode(user_id: user_id, type: :refresh),
          token_type: "Bearer",
          expires_in: ACCESS_EXPIRY.to_i
        }
      end

      def refresh(refresh_token)
        payload = decode(refresh_token)
        return nil unless payload&.dig(:type) == "refresh"

        issue_tokens(user_id: payload[:user_id])
      end
    end
  end
end
