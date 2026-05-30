# frozen_string_literal: true

namespace :kafka do
  desc "Create post_events topic"
  task create_topics: :environment do
    puts "Ensure Kafka topic exists: post_events"
  end
end
