# frozen_string_literal: true

Rails.application.config.after_initialize do
  Rails.application.routes.default_url_options[:host] = ENV.fetch("APP_HOST", "localhost:3000")
end
