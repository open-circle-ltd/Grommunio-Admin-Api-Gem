# frozen_string_literal: true

module GrommunioAdminApi
  module Api
    # Read-only access to /system/orgs.
    class Organizations < Base
      # GET /system/orgs
      #
      # @return [List<Resources::Organization>]
      def list(limit: nil, offset: nil)
        body = connection.request(:get, "/system/orgs", query: { limit: limit, offset: offset })
        List.new(body, resource_class: Resources::Organization)
      end

      # GET /system/orgs/{ID}
      #
      # @return [Resources::Organization]
      def get(organization_id:)
        Resources::Organization.new(connection.request(:get, "/system/orgs/#{organization_id}"))
      end

      # Lazily enumerates every organization across all pages.
      #
      # @return [Enumerator::Lazy<Resources::Organization>]
      def all(page_size: Pagination::DEFAULT_PAGE_SIZE)
        Pagination.each_item(page_size: page_size) { |limit, offset| list(limit: limit, offset: offset) }
      end
    end
  end
end
