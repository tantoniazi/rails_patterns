# frozen_string_literal: true

class CreateProcessedEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :processed_events do |t|
      t.string :event_id, null: false
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :processed_events, :event_id, unique: true
  end
end
