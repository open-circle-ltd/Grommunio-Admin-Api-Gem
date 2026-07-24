# frozen_string_literal: true

module GrommunioAdminApi
  module Api
    # LDAP candidate search and targeted single-user import.
    class Ldap < Base
      MIN_QUERY_LENGTH = 3

      # GET /domains/ldap/search
      #
      # @return [List<Resources::LdapCandidate>]
      def search(query:, domain_id: nil, organization_id: nil, show_all: nil, limit: nil)
        if query.to_s.gsub(/\s/, "").length < MIN_QUERY_LENGTH
          raise ArgumentError, "query must contain at least three non-whitespace characters"
        end

        params = { query: query, domain: domain_id, organization: organization_id,
                   showAll: show_all, limit: limit }
        body = connection.request(:get, "/domains/ldap/search", query: params)
        List.new(body, resource_class: Resources::LdapCandidate)
      end

      # POST /domains/ldap/importUser — first targeted import of one LDAP user.
      #
      # @return [Resources::User] when the server returns user data,
      #   [Resource] for a message-only response
      def import_user(ldap_object_id:, domain_id: nil, organization_id: nil, language: nil, force: nil)
        params = { ID: ldap_object_id, domain: domain_id, organization: organization_id,
                   lang: language, force: force }
        body = connection.request(:post, "/domains/ldap/importUser", query: params)
        Resources.wrap_user_or_generic(body)
      end
    end
  end
end
