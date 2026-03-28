source "https://rubygems.org"
ruby "3.3.0"

gem "rails", "~> 7.1"
gem "pg"
gem "puma"
gem "redis"
gem "bootsnap", require: false

# Background Jobs
gem "sidekiq"
gem "sidekiq-scheduler"

# GraphQL
gem "graphql"
gem "graphql-batch"

# Kafka
gem "karafka"

# Auth
gem "devise"
gem "pundit"

# Serialization
gem "jsonapi-serializer"

# Pagination
gem "pagy"

# Performance
gem "bullet", group: :development  # detecta N+1

group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
  gem "rubocop-rails", require: false
  gem "rubocop-rspec",  require: false
  gem "simplecov",      require: false
  gem "pry-byebug"
  gem "brakeman",       require: false
end
