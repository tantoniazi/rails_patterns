# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Comments", type: :request do
  let(:user) { create(:user) }
  let(:post_record) { create(:post, :published, user: user) }
  let(:headers) { auth_headers(user) }

  describe "POST /api/v1/posts/:post_id/comments" do
    it "creates a comment and increments counter cache" do
      expect {
        post "/api/v1/posts/#{post_record.id}/comments",
             params: { comment: { body: "Great post!" } },
             headers: headers,
             as: :json
      }.to change(Comment, :count).by(1)
        .and change { post_record.reload.comments_count }.from(0).to(1)

      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /api/v1/posts/:post_id/comments" do
    before { create_list(:comment, 2, post: post_record) }

    it "returns comments list" do
      get "/api/v1/posts/#{post_record.id}/comments", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"].length).to eq(2)
    end
  end
end
