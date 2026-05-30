# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comment, type: :model do
  describe "counter cache" do
    it "increments post comments_count on create" do
      post = create(:post)

      expect {
        create(:comment, post: post)
      }.to change { post.reload.comments_count }.from(0).to(1)
    end

    it "decrements post comments_count on destroy" do
      post = create(:post)
      comment = create(:comment, post: post)

      expect {
        comment.destroy
      }.to change { post.reload.comments_count }.from(1).to(0)
    end
  end
end
