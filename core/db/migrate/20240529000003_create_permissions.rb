# frozen_string_literal: true

class CreatePermissions < ActiveRecord::Migration[7.1]
  def change
    create_table :permissions do |t|
      t.string :role, null: false
      t.string :resource, null: false
      t.string :action, null: false

      t.timestamps
    end

    add_index :permissions, %i[role resource action], unique: true
  end
end
