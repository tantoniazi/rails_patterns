# frozen_string_literal: true

FactoryBot.define do
  factory :processed_event do
    sequence(:event_id) { |n| "evt-#{n}" }
    topic { "post_events" }
    partition { 0 }
    offset { 1 }
    payload { { "event" => "post.created", "post_id" => 1 } }
    processed_at { Time.current }
  end
end
