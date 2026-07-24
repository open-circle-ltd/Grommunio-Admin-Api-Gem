# frozen_string_literal: true

# Helpers for the opt-in live specs under spec/live/. Without the
# GROMMUNIO_* environment variables every live example is skipped, so the
# default suite (bundle exec rake) stays fully offline.
module LiveHelpers
  REQUIRED_READ_ENV = %w[
    GROMMUNIO_URL GROMMUNIO_USERNAME GROMMUNIO_PASSWORD
    GROMMUNIO_LIVE_DOMAIN_ID GROMMUNIO_LIVE_ORGANIZATION_ID
  ].freeze

  def skip_unless_live_env!(*extra)
    missing = (REQUIRED_READ_ENV + extra).reject { |name| ENV.fetch(name, nil) }
    skip "live environment not configured (missing: #{missing.join(", ")})" unless missing.empty?

    WebMock.allow_net_connect!
  end

  def live_client(mode:)
    GrommunioAdminApi::Client.new(
      base_url: ENV.fetch("GROMMUNIO_URL"),
      username: ENV.fetch("GROMMUNIO_USERNAME"),
      password: ENV.fetch("GROMMUNIO_PASSWORD"),
      verify_ssl: ENV.fetch("GROMMUNIO_VERIFY_SSL", "true") != "false",
      mode: mode
    )
  end

  def live_domain_id
    Integer(ENV.fetch("GROMMUNIO_LIVE_DOMAIN_ID"))
  end

  def live_organization_id
    Integer(ENV.fetch("GROMMUNIO_LIVE_ORGANIZATION_ID"))
  end
end

RSpec.configure do |config|
  config.include LiveHelpers, :live
  config.after(:each, :live) { WebMock.disable_net_connect! }
end
