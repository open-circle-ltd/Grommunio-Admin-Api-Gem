# frozen_string_literal: true

module GrommunioAdminApi
  # Per-area API classes; each owns exactly one upstream area.
  module Api
    # Shared constructor for the per-area API classes; each owns one
    # upstream area and delegates HTTP to the connection.
    class Base
      def initialize(connection)
        @connection = connection
      end

      private

      attr_reader :connection
    end
  end
end
