# frozen_string_literal: true

require "rails_helper"

RSpec.describe Domain::UseCases::ProcessPostEvent do
  subject(:use_case) { described_class.new(repository: repository) }

  let(:repository) { instance_double(Domain::Ports::ProcessedEventRepository) }
  let(:payload) do
    {
      "event_id" => "evt-456",
      "event" => "post.updated",
      "post_id" => 7
    }
  end
  let(:handler) { instance_double(Infrastructure::Handlers::PostEventHandler, call: true) }

  before do
    allow(repository).to receive(:processed?).and_return(false)
    allow(repository).to receive(:record!)
    allow(Infrastructure::Handlers::PostEventHandler).to receive(:new).with(payload).and_return(handler)
  end

  describe "#call" do
    it "handles and records a new event" do
      result = use_case.call(
        event_id: "evt-456",
        topic: "post_events",
        partition: 1,
        offset: 200,
        payload: payload
      )

      expect(handler).to have_received(:call)
      expect(repository).to have_received(:record!).with(
        event_id: "evt-456",
        topic: "post_events",
        partition: 1,
        offset: 200,
        payload: payload
      )
      expect(result).to eq(:processed)
    end

    context "when the event was already processed" do
      before do
        allow(repository).to receive(:processed?).with("evt-456").and_return(true)
      end

      it "skips handler and repository write" do
        result = use_case.call(
          event_id: "evt-456",
          topic: "post_events",
          partition: 1,
          offset: 200,
          payload: payload
        )

        expect(Infrastructure::Handlers::PostEventHandler).not_to have_received(:new)
        expect(repository).not_to have_received(:record!)
        expect(result).to eq(:already_processed)
      end
    end
  end
end
