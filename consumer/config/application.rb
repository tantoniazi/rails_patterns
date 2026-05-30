# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module Domain
end

module Infrastructure
end

module Consumer
  class Application < Rails::Application
    config.load_defaults 7.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true
    config.time_zone = "UTC"

    config.before_initialize do
      %w[app/domain app/infrastructure].each do |relative_path|
        path = Rails.root.join(relative_path).to_s
        config.autoload_paths.delete(path)
        config.eager_load_paths.delete(path)
      end
    end

    initializer "consumer.register_namespaces", before: :set_autoload_paths do
      Rails.autoloaders.main.push_dir(Rails.root.join("app/domain"), namespace: Domain)
      Rails.autoloaders.main.push_dir(Rails.root.join("app/infrastructure"), namespace: Infrastructure)
    end
  end
end
