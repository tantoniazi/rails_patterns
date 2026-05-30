# frozen_string_literal: true

class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    }
    config.client_id = "core_producer"
  end
end

KarafkaApp.routes.draw do
  # Producer-only app — no consumer routes
end
