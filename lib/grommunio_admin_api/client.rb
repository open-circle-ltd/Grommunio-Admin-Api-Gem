# frozen_string_literal: true

module GrommunioAdminApi
  # Public entry point. Exposes exactly the approved V1 operations through
  # the per-area API readers; there is no generic HTTP escape hatch.
  #
  # Not thread-safe: use one client per service or job.
  class Client
    MODES = %i[read_only sync_only].freeze

    attr_reader :mode, :organizations, :domains

    def initialize(base_url:, username: nil, password: nil, mode: :read_only, **)
      raise ArgumentError, "unsupported mode: #{mode.inspect}" unless MODES.include?(mode)

      @mode = mode
      @connection = Connection.new(
        base_url: base_url,
        username: username,
        password: password,
        mode: mode,
        **
      )
      @organizations = Api::Organizations.new(@connection)
      @domains = Api::Domains.new(@connection)
    end

    # POST /login — establishes the JWT-cookie and CSRF session.
    def login!
      @connection.login!
    end

    # GET /status — connection and service health.
    def status
      @connection.request(:get, "/status")
    end

    # GET /about — API/backend/schema version diagnostics.
    def about
      @connection.request(:get, "/about")
    end

    # Never exposes password, JWT, or CSRF token.
    def inspect
      "#<#{self.class.name} #{@connection.inspect}>"
    end
    alias to_s inspect
  end
end
