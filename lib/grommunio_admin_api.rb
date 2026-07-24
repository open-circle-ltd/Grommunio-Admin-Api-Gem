# frozen_string_literal: true

require_relative "grommunio_admin_api/version"
require_relative "grommunio_admin_api/connection"
require_relative "grommunio_admin_api/client"

module GrommunioAdminApi
  class Error < StandardError; end
end
