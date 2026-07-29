# frozen_string_literal: true

module GrommunioAdminApi
  module Api
    # Domain-scoped user inventory under /domains/{domainID}/users.
    class Users < Base
      # GET /domains/{domainID}/users
      #
      # @return [List<Resources::User>]
      def list(domain_id:, level: nil, limit: nil, offset: nil, username: nil)
        query = { level: level, limit: limit, offset: offset, username: username }
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
      def all(domain_id:, level: nil, username: nil, page_size: Pagination::DEFAULT_PAGE_SIZE)
        Pagination.each_item(page_size: page_size) do |limit, offset|
          list(domain_id: domain_id, level: level, username: username, limit: limit, offset: offset)
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
    end
  end
end
