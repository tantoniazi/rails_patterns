# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack", type: :request, rack_attack: true do
  let(:user) { create(:user, password: "secret123") }

  describe "POST /api/v1/sessions throttling" do
    it "returns 429 after 5 login attempts per minute" do
      5.times do
        post "/api/v1/sessions",
             params: { session: { email: user.email, password: "wrong" } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      post "/api/v1/sessions",
           params: { session: { email: user.email, password: "wrong" } },
           as: :json

      expect(response).to have_http_status(:too_many_requests)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("Rate limit exceeded")
      expect(json["retry_after"]).to eq(60)
      expect(response.headers["Retry-After"]).to eq("60")
    end
  end

  describe "API throttling" do
    let(:headers) { auth_headers(user) }

    before { create_list(:post, 1, :published, user: user) }

    it "returns 429 after 300 API requests per 5 minutes" do
      300.times do
        get "/api/v1/posts", headers: headers
        expect(response).to have_http_status(:ok)
      end

      get "/api/v1/posts", headers: headers

      expect(response).to have_http_status(:too_many_requests)
      json = JSON.parse(response.body)
      expect(json["error"]).to eq("Rate limit exceeded")
      expect(json["retry_after"]).to eq(300)
    end
  end
end
