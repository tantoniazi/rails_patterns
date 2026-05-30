# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::UseCases::ListPosts do
  let(:user) { create(:user) }
  let(:post_repo) { Infrastructure::Repositories::PostRepository.new }

  describe "#call" do
    before do
      create_list(:post, 5, :published, user: user, title: "Rails Patterns Guide")
      create(:post, :draft, user: user, title: "Draft Post About Ruby")
    end

    it "returns paginated published posts by default scope" do
      result = described_class.new(post_repo: post_repo).call(page: 1, per_page: 2)

      expect(result).to be_success
      collection = result.value
      expect(collection.records.size).to eq(2)
      expect(collection.page).to eq(1)
      expect(collection.per_page).to eq(2)
      expect(collection.total_count).to eq(6)
      expect(collection.total_pages).to eq(3)
    end

    it "filters by legacy status param" do
      result = described_class.new(post_repo: post_repo).call(filters: { status: "draft" })

      expect(result.value.records.map(&:status).uniq).to eq(["draft"])
      expect(result.value.total_count).to eq(1)
    end

    it "filters with ransack q params" do
      result = described_class.new(post_repo: post_repo).call(
        filters: { q: { title_cont: "Patterns" } }
      )

      expect(result.value.total_count).to eq(5)
      expect(result.value.records.map(&:title)).to all(include("Patterns"))
    end

    it "filters by ransack status_eq" do
      result = described_class.new(post_repo: post_repo).call(
        filters: { q: { status_eq: "published" } }
      )

      expect(result.value.total_count).to eq(5)
      expect(result.value.records.map(&:status).uniq).to eq(["published"])
    end
  end
end
