# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module GrommunioAdminApi
  # Low-level HTTP transport for the Grommunio Admin API.
  #
  # Owns the session lifecycle (form-encoded POST /login, JWT cookie, CSRF
  # token on writes, one automatic re-login and replay on 401), the mutation
  # policy (read_only / sync_only), and the HTTP status -> error mapping.
  #
  # Not thread-safe: use one client per service or job.
  class Connection
    MODES = %i[read_only sync_only].freeze
    MUTATING_METHODS = %i[post put patch delete].freeze
    SUCCESS_STATUSES = [200, 201, 202, 204].freeze
    STATUS_ERRORS = {
      400 => ValidationError,
      401 => AuthenticationError,
      403 => ForbiddenError,
      404 => NotFoundError,
      422 => ValidationError,
      503 => ServiceUnavailableError
    }.freeze

    # The only writes a sync_only client may perform, matched on the actual
    # HTTP method and normalized path — never on a symbolic operation name.
    SYNC_ONLY_OPERATIONS = [
      [:post, %r{\A/domains/ldap/importUser\z}],
      [:put, %r{\A/domains/\d+/users/\d+/downsync\z}]
    ].freeze

    attr_reader :base_url, :username, :mode, :verify_ssl, :open_timeout, :read_timeout

    # Normalizes the configured base URL: collapses duplicate slashes, strips
    # trailing slashes, and appends /api/v1 when no path is given.
    def self.normalize_base_url(raw)
      url = raw.to_s.strip
      scheme, rest = url.split("://", 2)
      unless %w[http https].include?(scheme) && rest && !rest.empty?
        raise ArgumentError, "base_url must include an http or https scheme, e.g. https://mail.example.com:8443"
      end

      host, path = rest.split("/", 2)
      segments = path.to_s.split("/").reject(&:empty?)
      segments = %w[api v1] if segments.empty?
      "#{scheme}://#{host}/#{segments.join("/")}"
    end

    def initialize(base_url:, username: nil, password: nil, mode: :read_only,
                   verify_ssl: true, open_timeout: 5, read_timeout: 60)
      raise ArgumentError, "unsupported mode: #{mode.inspect}" unless MODES.include?(mode)

      @base_url = self.class.normalize_base_url(base_url)
      @username = username
      @password = password
      @mode = mode
      @verify_ssl = verify_ssl
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @jwt = nil
      @csrf = nil
    end

    # Performs an API request and returns the parsed JSON body (nil for 204 /
    # empty bodies). Raises the mapped ApiError subclass on non-2xx responses
    # and ConnectionError on transport failures. The mutation policy runs
    # before login or any other socket access.
    def request(method, path, query: nil, form: nil)
      guard_mutation!(method, path)
      login! unless logged_in?

      response = perform(method, path, query: query, form: form)
      if response.code.to_i == 401
        # Session expired server-side: re-login once and replay the request.
        login!
        response = perform(method, path, query: query, form: form)
      end

      handle(method, path, response)
    end

    # POST /login with form-encoded credentials; stores the JWT cookie value
    # and CSRF token for subsequent requests.
    def login!
      raise AuthenticationError.new("cannot login: no credentials configured", status: nil, body: nil) if @username.nil?

      @jwt = nil
      @csrf = nil
      body = handle(:post, "/login", perform(:post, "/login", form: { user: @username, pass: @password }))
      @jwt = body["grommunioAuthJwt"]
      @csrf = body["csrf"]
      body
    end

    def logged_in?
      !@jwt.nil?
    end

    # Never exposes password, JWT, or CSRF token.
    def inspect
      "#<#{self.class.name} base_url=#{base_url.inspect} username=#{username.inspect} " \
        "mode=#{mode.inspect} logged_in=#{logged_in?}>"
    end
    alias to_s inspect

    private

    # Fail-closed: only sync_only may write, and only the allowlisted
    # operations. Any other mode blocks every write.
    def guard_mutation!(method, path)
      return unless MUTATING_METHODS.include?(method)

      operation = "#{method.to_s.upcase} #{path}"
      raise ReadOnlyModeError, "#{operation} rejected: client is in read_only mode" if mode == :read_only
      return if mode == :sync_only && sync_operation?(method, path)

      raise SyncOperationNotAllowedError,
            "#{operation} rejected: mode #{mode.inspect} permits only targeted import and downsync"
    end

    def sync_operation?(method, path)
      SYNC_ONLY_OPERATIONS.any? { |verb, pattern| verb == method && pattern.match?(path) }
    end

    def perform(method, path, query: nil, form: nil)
      uri = build_uri(path, query)
      http(uri).request(build_request(method, uri, form: form))
    rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise ConnectionError, "#{method.to_s.upcase} #{path} failed: #{e.class}"
    end

    def build_uri(path, query)
      uri = URI("#{base_url}#{path}")
      compacted = query&.compact
      uri.query = URI.encode_www_form(compacted) unless compacted.nil? || compacted.empty?
      uri
    end

    def build_request(method, uri, form: nil)
      http_request = Net::HTTP.const_get(method.capitalize).new(uri)
      http_request["Accept"] = "application/json"
      http_request["Cookie"] = "grommunioAuthJwt=#{@jwt}" if logged_in?
      http_request["X-Csrf-Token"] = @csrf if @csrf && MUTATING_METHODS.include?(method)
      if form
        http_request["Content-Type"] = "application/x-www-form-urlencoded"
        http_request.body = URI.encode_www_form(form)
      end
      http_request
    end

    def http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      http
    end

    def handle(method, path, response)
      status = response.code.to_i
      body = parse_body(method, path, status, response.body)
      return body if SUCCESS_STATUSES.include?(status)

      error_class = STATUS_ERRORS.fetch(status) { status >= 500 ? ServerError : ClientError }
      raise error_class.new(error_message(method, path, status, body), status: status, body: body)
    end

    def parse_body(method, path, status, raw)
      return nil if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      if (200..299).cover?(status)
        raise ParseError,
              "#{method.to_s.upcase} #{path}: 2xx response body is not valid JSON"
      end

      raw # error responses may be plain text; keep the raw string as body
    end

    def error_message(method, path, status, body)
      message = "#{method.to_s.upcase} #{path} -> HTTP #{status}"
      server_message = body.is_a?(Hash) ? body["message"] : nil
      server_message ? "#{message}: #{server_message}" : message
    end
  end
end
