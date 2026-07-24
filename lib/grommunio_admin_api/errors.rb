# frozen_string_literal: true

module GrommunioAdminApi
  # Base class for every error raised by this gem.
  class Error < StandardError; end

  # HTTP error response. Keeps the status code and the parsed response body
  # (or the raw string when the body was not JSON). Messages never contain
  # credentials, tokens, or request/response bodies.
  class ApiError < Error
    attr_reader :status, :body

    def initialize(message, status:, body:)
      super(message)
      @status = status
      @body = body
    end

    # The server's own error description ("message" field of the JSON error
    # body), nil when the response had none.
    def server_message
      body["message"] if body.is_a?(Hash)
    end
  end

  # 400 and 422
  class ValidationError < ApiError; end
  # 401
  class AuthenticationError < ApiError; end
  # 403
  class ForbiddenError < ApiError; end
  # 404
  class NotFoundError < ApiError; end
  # Any other 4xx
  class ClientError < ApiError; end
  # 500 and any other 5xx
  class ServerError < ApiError; end
  # 503
  class ServiceUnavailableError < ServerError; end

  # Transport-level failure (DNS, refused, reset, TLS, timeout). The original
  # exception is preserved as #cause.
  class ConnectionError < Error; end

  # 2xx response whose body could not be parsed as JSON.
  class ParseError < Error; end

  # Raised before any socket access when a mutation is attempted in
  # read_only mode.
  class ReadOnlyModeError < Error; end

  # Raised before any socket access when a sync_only client attempts a write
  # outside the targeted import/downsync allowlist.
  class SyncOperationNotAllowedError < Error; end
end
