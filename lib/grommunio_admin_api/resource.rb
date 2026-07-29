# frozen_string_literal: true

module GrommunioAdminApi
  # Immutable value object over a complete API response body.
  #
  # - hydrated exactly once, at construction, from the full response hash
  # - attribute access is a plain frozen-hash lookup and never triggers HTTP
  # - holds no reference to any connection or client
  # - the complete raw payload stays available via #raw / #[] / #to_h, so
  #   nothing the server returned is ever lost
  #
  # Note: the passed hash is deep-frozen in place.
  class Resource
    class << self
      # Declares a typed reader over the raw hash.
      def field(name, key: name.to_s)
        define_method(name) { @raw[key] }
      end

      # Recursively freezes JSON-parsed data (hashes, arrays, scalars).
      def deep_freeze(value)
        case value
        when Hash
          value.each_value { |nested| deep_freeze(nested) }
        when Array
          value.each { |nested| deep_freeze(nested) }
        end
        value.freeze
      end
    end

    attr_reader :raw

    def initialize(raw)
      @raw = Resource.deep_freeze(raw.nil? ? {} : raw)
      freeze
    end

    # Raw access to any response field, modeled or not. Returns nil both for
    # fields the server sent as null AND for fields not present in this
    # response shape — use #key? or #fetch to distinguish the two.
    def [](key)
      @raw[key.to_s]
    end

    def key?(key)
      @raw.key?(key.to_s)
    end

    # Hash#fetch semantics over the raw payload: raises KeyError when the
    # field was not part of the response instead of silently returning nil.
    def fetch(key, ...)
      @raw.fetch(key.to_s, ...)
    end

    # The complete (frozen) response hash.
    def to_h
      @raw
    end

    # Value equality with resources of the same class. Compare against a
    # plain hash through #to_h.
    def ==(other)
      other.instance_of?(self.class) && other.raw == raw
    end
    alias eql? ==

    # Consistent with #eql? for Hash-key usage.
    def hash
      [self.class, raw].hash
    end

    # Shows the full raw payload (resources never contain credentials).
    def inspect
      "#<#{self.class.name} #{raw.inspect}>"
    end
  end
end
