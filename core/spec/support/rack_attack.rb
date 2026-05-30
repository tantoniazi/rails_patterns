# frozen_string_literal: true

RSpec.configure do |config|
  config.before do |example|
    next unless example.metadata[:rack_attack]

    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  config.after do |example|
    next unless example.metadata[:rack_attack]

    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end
end
