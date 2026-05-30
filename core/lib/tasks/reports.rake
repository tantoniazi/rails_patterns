# frozen_string_literal: true

namespace :reports do
  desc "Refresh posts_summaries materialized view"
  task refresh_posts_summary: :environment do
    PostsSummary.refresh!
    puts "posts_summaries refreshed at #{Time.current.iso8601}"
  end
end
