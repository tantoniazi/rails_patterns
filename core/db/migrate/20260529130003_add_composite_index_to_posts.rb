# frozen_string_literal: true

class AddCompositeIndexToPosts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :posts, %i[status published_at],
              order: { published_at: :desc },
              name: "index_posts_on_status_and_published_at",
              algorithm: :concurrently
  end
end
