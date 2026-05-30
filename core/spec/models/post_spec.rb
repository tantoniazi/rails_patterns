# frozen_string_literal: true

require "rails_helper"

RSpec.describe Post, type: :model do
  subject(:post) { build(:post) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_least(5).is_at_most(200) }
    it { is_expected.to validate_presence_of(:body) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "status enum" do
    it { is_expected.to define_enum_for(:status).with_values(draft: 0, published: 1, archived: 2) }
  end

  describe "scopes" do
    describe ".published" do
      it "returns only published posts" do
        published = create(:post, :published)
        draft = create(:post, :draft)

        expect(Post.published).to include(published)
        expect(Post.published).not_to include(draft)
      end
    end
  end

  describe "callbacks" do
    it "generates slug from title" do
      post = build(:post, title: "My First Post", slug: nil)
      post.valid?
      expect(post.slug).to eq("my-first-post")
    end
  end
end
