# frozen_string_literal: true

module GrommunioAdminApi
  # Placeholder shell; the full HTTP implementation lands with the connection task.
  class Connection
    def initialize(base_url:, username: nil, password: nil, mode: :read_only, **options)
      @base_url = base_url
      @username = username
      @password = password
      @mode = mode
      @options = options
    end
  end
end
