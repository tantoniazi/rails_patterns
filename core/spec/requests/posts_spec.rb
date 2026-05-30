# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Posts", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }

  describe "GET /api/v1/posts" do
    before { create_list(:post, 3, :published, user: user) }

    it "returns 200 with list of posts" do
      get "/api/v1/posts", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"].length).to eq(3)
    end

    it "includes meta total count" do
      get "/api/v1/posts", headers: headers

      json = JSON.parse(response.body)
      expect(json["meta"]["total_count"]).to eq(3)
    end

    it "filters by status" do
      create(:post, :draft, user: user)
      get "/api/v1/posts", params: { status: "published" }, headers: headers

      json = JSON.parse(response.body)
      statuses = json["data"].map { |p| p["status"] }
      expect(statuses.uniq).to eq(["published"])
    end

    context "without authentication" do
      it "returns 401" do
        get "/api/v1/posts"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/posts" do
    let(:valid_params) do
      { post: { title: "My New Post Rails", body: "Post content here.", status: "draft" } }
    end

    it "creates the post" do
      expect {
        post "/api/v1/posts", params: valid_params, headers: headers, as: :json
      }.to change(Post, :count).by(1)
    end

    it "returns 201 with the post" do
      post "/api/v1/posts", params: valid_params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["title"]).to eq("My New Post Rails")
      expect(json["user"]["id"]).to eq(user.id)
    end
  end

  describe "PATCH /api/v1/posts/:id" do
    let(:existing_post) { create(:post, user: user) }

    it "updates the post" do
      patch "/api/v1/posts/#{existing_post.id}",
            params: { post: { title: "Updated Title Here" } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(existing_post.reload.title).to eq("Updated Title Here")
    end

    context "when not the owner" do
      let(:other_user) { create(:user) }

      it "returns 403" do
        patch "/api/v1/posts/#{existing_post.id}",
              params: { post: { title: "Hack Attempt Here" } },
              headers: auth_headers(other_user),
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /api/v1/posts/:id" do
    let!(:existing_post) { create(:post, user: user) }

    it "deletes the post" do
      expect {
        delete "/api/v1/posts/#{existing_post.id}", headers: headers
      }.to change(Post, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
