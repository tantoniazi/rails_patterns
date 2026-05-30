# frozen_string_literal: true

ActiveRecord::Schema[7.1].define(version: 2026_05_29_120000) do
  enable_extension "plpgsql"

  create_table "processed_events", force: :cascade do |t|
    t.string "event_id", null: false
    t.string "topic", null: false
    t.integer "partition", null: false
    t.bigint "offset", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_processed_events_on_event_id", unique: true
    t.index ["topic", "partition", "offset"], name: "index_processed_events_on_topic_and_partition_and_offset"
  end
end
