require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Interview
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Settings specific to this application
    config.x.rate_api_base_url = "http://host.docker.internal:8080"
    # In production code, this would be set by an environment variable, or some other secure way
    # that prevents it being exposed on github.
    config.x.rate_api_token = "04aa6f42aa03f220c2ae9a276cd68c62"

    config.x.rate_api_deadline = 30.seconds
    
    config.x.rate_api_max_requests = 10

    config.x.pricing_cache_duration = 5.minutes
    config.x.pricing_refresh_candidate_age = config.x.pricing_cache_duration / 2
    config.x.pricing_reference_list_max_age = 30.minutes

  end
end
