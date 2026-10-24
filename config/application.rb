require_relative "boot"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module ZkAttendance
  class Application < Rails::Application
    config.load_defaults 7.1

    # app/lib holds plain Ruby (ZkClient); autoload it like the rest of app/.
    config.autoload_paths << Rails.root.join("app/lib")
    config.eager_load_paths << Rails.root.join("app/lib")

    # Internal LAN tool: don't block by Host header.
    config.hosts.clear

    config.secret_key_base = ENV.fetch("SECRET_KEY_BASE", "dev-secret-change-me-please")

    # Sign-in state is kept in an encrypted cookie session.
    config.session_store :cookie_store, key: "_zk_attendance_session"
    config.api_only = false
  end
end
