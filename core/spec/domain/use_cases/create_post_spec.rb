# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::UseCases::CreatePost, type: :model do
  subject(:use_case) { described_class.new(post_repo: post_repo, event_publisher: event_publisher) }

  let(:post_repo) { instance_double(Infrastructure::Repositories::PostRepository) }
  let(:event_publisher) { instance_double(Infrastructure::Kafka::PostEventProducer, publish_created: true) }
  let(:user) { create(:user) }
  let(:attributes) { { title: "New Post Title Here", body: "Body content", status: "draft" } }

  describe "#call" do
    context "with valid attributes" do
      it "creates a post" do
        real_repo = Infrastructure::Repositories::PostRepository.new
        use_case = described_class.new(post_repo: real_repo, event_publisher: event_publisher)

        expect {
          result = use_case.call(user: user, attributes: attributes)
          expect(result).to be_success
        }.to change(Post, :count).by(1)
      end
    end

    context "with invalid attributes" do
      it "returns failure with errors" do
        real_repo = Infrastructure::Repositories::PostRepository.new
        use_case = described_class.new(post_repo: real_repo, event_publisher: event_publisher)

        result = use_case.call(user: user, attributes: { title: "", body: "" })

        expect(result).to be_failure
        expect(result.errors).to be_present
      end
    end

    context "when publishing published post" do
      it "publishes kafka event" do
        post = user.posts.build(attributes.merge(status: :published))
        allow(post_repo).to receive(:build).and_return(post)
        allow(post_repo).to receive(:save).and_return(true)

        expect(event_publisher).to receive(:publish_created).with(post)

        use_case.call(user: user, attributes: attributes.merge(status: "published"))
      end
    end
  end
end
