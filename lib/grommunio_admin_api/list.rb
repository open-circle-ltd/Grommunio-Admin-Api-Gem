# frozen_string_literal: true

module GrommunioAdminApi
  # One page of a paginated list endpoint: the wrapped "data" items plus the
  # server-reported "count" total. Keeps the complete raw payload.
  class List
    include Enumerable

    attr_reader :raw, :data

    def initialize(payload, resource_class: Resource)
      @raw = Resource.deep_freeze(payload.nil? ? {} : payload)
      @data = (@raw["data"] || []).map { |item| resource_class.new(item) }.freeze
      freeze
    end

    # The server-reported total across all pages, nil when absent.
    def total_count
      @raw["count"]
    end

    # Iterates over the wrapped resources of this page.
    def each(&)
      data.each(&)
    end

    # Number of items on this page (not the overall total).
    def size
      data.size
    end

    def empty?
      data.empty?
    end
  end
end
