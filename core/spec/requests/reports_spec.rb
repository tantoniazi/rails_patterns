# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Reports", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user) }

  before do
    create_list(:post, 2, :published, user: admin)
    create(:post, :draft, user: admin)
    PostsSummary.refresh!
  end

  describe "GET /api/v1/reports/posts_summary" do
    it "returns summary for admin" do
      get "/api/v1/reports/posts_summary", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"].length).to be >= 1
    end

    it "returns forbidden for member" do
      get "/api/v1/reports/posts_summary", headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
