# frozen_string_literal: true

module GrommunioAdminApi
  class Client
    MODES = %i[read_only sync_only].freeze

    attr_reader :mode

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
    end
  end
end
