# frozen_string_literal: true

class CreateAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.decimal :balance, precision: 12, scale: 2, null: false, default: 0
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end
  end
end
