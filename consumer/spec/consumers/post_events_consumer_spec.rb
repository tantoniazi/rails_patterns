# frozen_string_literal: true

require "rails_helper"

RSpec.describe PostEventsConsumer do
  subject(:consumer) { described_class.new }

  let(:payload) do
    {
      "event_id" => "evt-123",
      "event" => "post.created",
      "post_id" => 42
    }
  end

  let(:message) do
    instance_double(
      Karafka::Messages::Message,
      payload: payload.to_json,
      topic: "post_events",
      partition: 0,
      offset: 100
    )
  end

  before do
    allow(consumer).to receive(:messages).and_return([message])
  end

  describe "#consume" do
    it "persists a processed event for a new message" do
      expect { consumer.consume }.to change(ProcessedEvent, :count).by(1)

      record = ProcessedEvent.last
      expect(record.event_id).to eq("evt-123")
      expect(record.topic).to eq("post_events")
      expect(record.partition).to eq(0)
      expect(record.offset).to eq(100)
    end

    context "when the event was already processed (idempotency)" do
      before do
        ProcessedEvent.create!(
          event_id: "evt-123",
          topic: "post_events",
          partition: 0,
          offset: 99,
          payload: payload,
          processed_at: 1.hour.ago
        )
      end

      it "does not process the event again" do
        expect(Infrastructure::Handlers::PostEventHandler).not_to receive(:new)

        expect { consumer.consume }.not_to change(ProcessedEvent, :count)
      end
    end
  end
end
