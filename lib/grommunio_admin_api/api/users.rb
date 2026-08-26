# frozen_string_literal: true

module GrommunioAdminApi
  module Api
    # Domain-scoped user inventory and mailbox permissions under
    # /domains/{domainID}/users.
    class Users < Base
      # GET /domains/{domainID}/users
      #
      # @param properties [String, nil] comma-separated list of user
      #   properties to include in the response (e.g. "displayname,smtpaddress")
      # @return [List<Resources::User>]
      def list(domain_id:, level: nil, limit: nil, offset: nil, username: nil, properties: nil)
        query = { level: level, limit: limit, offset: offset, username: username, properties: properties }
        body = connection.request(:get, "/domains/#{domain_id}/users", query: query)
        List.new(body, resource_class: Resources::User)
      end

      # GET /domains/{domainID}/users/{userID}
      #
      # @return [Resources::User]
      def get(domain_id:, user_id:, level: nil)
        body = connection.request(:get, "/domains/#{domain_id}/users/#{user_id}", query: { level: level })
        Resources::User.new(body)
      end

      # Lazily enumerates every user of one domain across all pages, applying
      # the same filters as #list.
      #
      # @return [Enumerator::Lazy<Resources::User>]
      def all(domain_id:, level: nil, username: nil, properties: nil, page_size: Pagination::DEFAULT_PAGE_SIZE)
        Pagination.each_item(page_size: page_size) do |limit, offset|
          list(domain_id: domain_id, level: level, username: username, properties: properties,
               limit: limit, offset: offset)
        end
      end

      # PUT /domains/{domainID}/users/{userID}/downsync — refresh one
      # existing Grommunio user from LDAP.
      #
      # @return [Resources::User] when the server returns user data,
      #   [Resource] for a message-only response
      def downsync(domain_id:, user_id:, ldap_object_id: nil, language: nil)
        body = connection.request(:put, "/domains/#{domain_id}/users/#{user_id}/downsync",
                                  query: { ID: ldap_object_id, lang: language })
        Resources.wrap_user_or_generic(body)
      end

      # POST /domains/{domainID}/users — creates one user directly upstream,
      # without LDAP. status 4 makes it a shared mailbox, 5 a contact.
      #
      # @param attributes [Hash] userInit payload. Passed through verbatim
      #   rather than enumerated as keywords: the schema declares no required
      #   field and its "properties" bag is open, so any enumeration here would
      #   go stale against the server.
      # @return [Resources::User] the created object, including its upstream ID,
      #   or [Resource] for a 2xx that carries no user data - the caller then
      #   has no upstream ID and has to resolve the object another way
      def create(domain_id:, attributes:)
        body = connection.request(:post, "/domains/#{domain_id}/users", json: attributes)
        Resources.wrap_user_or_generic(body)
      end

      # GET /domains/{domainID}/users/{userID}/delegates — addresses allowed to
      # send mail on behalf of this mailbox.
      #
      # Returns plain addresses, not resources: the payload items are strings,
      # and List would hydrate each one into a Resource whose field access
      # silently misbehaves.
      #
      # @return [Array<String>]
      def delegates(domain_id:, user_id:)
        address_list("/domains/#{domain_id}/users/#{user_id}/delegates")
      end

      # PUT /domains/{domainID}/users/{userID}/delegates
      #
      # REPLACES THE WHOLE LIST. Verified against a live instance: PUT ["a"]
      # followed by PUT ["b"] leaves only "b", and PUT [] clears the list.
      # Whatever the mailbox owner set in webmail or an administrator set in the
      # admin web is gone unless the caller read the list first and merged.
      # Upstream offers no additive verb here - #grant_store_access is the only
      # one of the three lists that has one.
      #
      # @param addresses [Array<String>] the complete new list, not an addition
      # @return [nil] the API answers 200 without a body
      def set_delegates(domain_id:, user_id:, addresses:)
        connection.request(:put, "/domains/#{domain_id}/users/#{user_id}/delegates", json: address_array(addresses))
      end

      # GET /domains/{domainID}/users/{userID}/sendas — addresses allowed to
      # send mail as this mailbox. Plain addresses, see #delegates.
      #
      # @return [Array<String>]
      def sendas(domain_id:, user_id:)
        address_list("/domains/#{domain_id}/users/#{user_id}/sendas")
      end

      # PUT /domains/{domainID}/users/{userID}/sendas
      #
      # REPLACES THE WHOLE LIST, exactly like #set_delegates - verified live:
      # PUT ["a", "b"] then PUT ["a"] drops "b", and PUT [] clears the list.
      # Send-as is impersonation, so a silently dropped entry is a permission
      # the caller did not mean to revoke.
      #
      # @param addresses [Array<String>] the complete new list, not an addition
      # @return [nil] the API answers 200 without a body
      def set_sendas(domain_id:, user_id:, addresses:)
        connection.request(:put, "/domains/#{domain_id}/users/#{user_id}/sendas", json: address_array(addresses))
      end

      # GET /domains/{domainID}/users/{userID}/storeAccess — additional store
      # owners, i.e. read-write access to every object of this mailbox.
      #
      # Unlike the other two lists this one returns objects
      # ("memberID", "displayName", "username"), so it stays a List.
      #
      # @return [List<Resource>]
      def store_access(domain_id:, user_id:)
        path = "/domains/#{domain_id}/users/#{user_id}/storeAccess"
        body = connection.request(:get, path)
        raise ParseError, "GET #{path}: expected a {\"data\" => [...]} object" unless body.is_a?(Hash)

        List.new(body)
      end

      # POST /domains/{domainID}/users/{userID}/storeAccess — grants one
      # address without touching the existing entries.
      #
      # @return [nil] the API answers 201 without a body
      def grant_store_access(domain_id:, user_id:, address:)
        connection.request(:post, "/domains/#{domain_id}/users/#{user_id}/storeAccess",
                           json: { username: address })
      end

      # PUT /domains/{domainID}/users/{userID}/storeAccess
      #
      # REPLACES THE WHOLE LIST. Verified live: with "a" already granted,
      # PUT ["b"] answers "2 users updated" and leaves only "b"; PUT [] clears
      # the list. Unlike the other two lists this one has additive verbs -
      # prefer #grant_store_access / #revoke_store_access unless the caller
      # genuinely owns every entry.
      #
      # @param addresses [Array<String>] the complete new list, not an addition
      # @return [nil] the API answers 200 without a body
      def set_store_access(domain_id:, user_id:, addresses:)
        connection.request(:put, "/domains/#{domain_id}/users/#{user_id}/storeAccess",
                           json: { usernames: address_array(addresses) })
      end

      # DELETE /domains/{domainID}/users/{userID}/storeAccess/{username} —
      # revokes one address without touching the existing entries.
      #
      # @return [nil] the API answers 200 without a body
      def revoke_store_access(domain_id:, user_id:, address:)
        raise ArgumentError, "address must be a mail address" unless address.to_s.include?("@")

        segment = URI.encode_uri_component(address)
        connection.request(:delete, "/domains/#{domain_id}/users/#{user_id}/storeAccess/#{segment}")
      end

      private

      def address_array(addresses)
        raise ArgumentError, "addresses must be an Array of mail addresses" unless addresses.is_a?(Array)

        addresses
      end

      # Both address endpoints are documented as {"data" => [address, ...]}. A
      # different shape is a contract violation, and answering with an empty
      # list instead would make the documented read-modify-write silently drop
      # entries.
      def address_list(path)
        body = connection.request(:get, path)
        data = body.is_a?(Hash) ? body["data"] : nil
        raise ParseError, "GET #{path}: expected {\"data\" => [address, ...]}" unless data.nil? || data.is_a?(Array)

        Resource.deep_freeze(data || [])
      end
    end
  end
end
