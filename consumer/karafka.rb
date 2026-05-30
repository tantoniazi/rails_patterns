# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "development"
ENV["KARAFKA_ENV"] = ENV["RAILS_ENV"]

require ::File.expand_path("config/environment", __dir__)

class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": ENV.fetch("KAFKA_URL", "localhost:9092")
    }
    config.client_id = "consumer"
    config.consumer_persistence = !Rails.env.development?
    config.logger = Rails.logger
  end

  routes.draw do
    topic "post_events" do
      consumer PostEventsConsumer
    end
  end
end
