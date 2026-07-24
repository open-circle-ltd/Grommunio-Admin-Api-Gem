# frozen_string_literal: true

module GrommunioAdminApi
  # Typed value objects over the V1 response shapes.
  module Resources
    # A user-shaped payload becomes a typed User; anything else (e.g. a
    # message-only success from import/downsync) stays a generic Resource
    # without losing data.
    def self.wrap_user_or_generic(body)
      body.is_a?(Hash) && body.key?("ID") ? User.new(body) : Resource.new(body)
    end

    # One user, shared mailbox, or contact from /domains/{domainID}/users.
    class User < Resource
      # Documented upstream status values. A status-0 object is an account
      # candidate — it does not guarantee a mailbox store exists.
      STATUS_NORMAL = 0
      STATUS_SUSPENDED = 1
      STATUS_DELETED = 3
      STATUS_SHARED_MAILBOX = 4
      STATUS_CONTACT = 5
      KNOWN_STATUSES = [
        STATUS_NORMAL, STATUS_SUSPENDED, STATUS_DELETED, STATUS_SHARED_MAILBOX, STATUS_CONTACT
      ].freeze

      field :id, key: "ID"
      field :username
      field :domain_id, key: "domainID"
      field :organization_id, key: "orgID"
      field :status
      field :ldap_id, key: "ldapID"
      field :aliases
      field :altnames
      field :properties
      field :roles
      field :maildir
      field :lang
      field :homeserver

      def normal?
        status == STATUS_NORMAL
      end

      def suspended?
        status == STATUS_SUSPENDED
      end

      def deleted?
        status == STATUS_DELETED
      end

      def shared_mailbox?
        status == STATUS_SHARED_MAILBOX
      end

      def contact?
        status == STATUS_CONTACT
      end

      # Future or undocumented upstream status values stay representable.
      def unknown_status?
        !KNOWN_STATUSES.include?(status)
      end
    end
  end
end
