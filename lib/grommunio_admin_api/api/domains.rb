# frozen_string_literal: true

module GrommunioAdminApi
  module Api
    # Read-only access to /system/domains.
    class Domains < Base
      # GET /system/domains
      #
      # Array filters are comma-encoded (OpenAPI explode: false), e.g.
      # orgID=12,13 and domainStatus=0,1.
      #
      # @return [List<Resources::Domain>]
      def list(limit: nil, offset: nil, organization_ids: nil, statuses: nil)
        query = {
          limit: limit,
          offset: offset,
          orgID: organization_ids&.join(","),
          domainStatus: statuses&.join(",")
        }
        List.new(connection.request(:get, "/system/domains", query: query), resource_class: Resources::Domain)
      end

      # GET /system/domains/{domainID}
      #
      # @return [Resources::Domain]
      def get(domain_id:)
        Resources::Domain.new(connection.request(:get, "/system/domains/#{domain_id}"))
      end

      # Lazily enumerates every domain across all pages, applying the same
      # filters as #list.
      #
      # @return [Enumerator::Lazy<Resources::Domain>]
      def all(organization_ids: nil, statuses: nil, page_size: Pagination::DEFAULT_PAGE_SIZE)
        Pagination.each_item(page_size: page_size) do |limit, offset|
          list(organization_ids: organization_ids, statuses: statuses, limit: limit, offset: offset)
        end
      end
    end
  end
end
