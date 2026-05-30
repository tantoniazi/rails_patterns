# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:user) { create(:user, password: "secret123") }

  describe "POST /api/v1/sessions" do
    context "with valid credentials" do
      it "returns JWT tokens" do
        post "/api/v1/sessions",
             params: { session: { email: user.email, password: "secret123" } },
             as: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["access_token"]).to be_present
        expect(json["refresh_token"]).to be_present
        expect(json["user"]["email"]).to eq(user.email)
      end
    end

    context "with invalid credentials" do
      it "returns unauthorized" do
        post "/api/v1/sessions",
             params: { session: { email: user.email, password: "wrong" } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/sessions/refresh" do
    it "issues new tokens from refresh token" do
      tokens = Infrastructure::Auth::JwtService.issue_tokens(user_id: user.id)

      post "/api/v1/sessions/refresh",
           params: { refresh_token: tokens[:refresh_token] },
           as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["access_token"]).to be_present
      expect(json["refresh_token"]).to be_present
    end

    it "rejects invalid refresh token" do
      post "/api/v1/sessions/refresh",
           params: { refresh_token: "invalid" },
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/sessions" do
    it "returns no content" do
      delete "/api/v1/sessions", headers: auth_headers(user)

      expect(response).to have_http_status(:no_content)
    end
  end
end
