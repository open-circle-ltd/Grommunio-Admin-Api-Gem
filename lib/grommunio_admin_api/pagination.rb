# frozen_string_literal: true

module GrommunioAdminApi
  # Offset-based auto-pagination over the paginated list endpoints.
  #
  # Never truncates silently: pages are fetched until a page comes back
  # shorter than requested or the server-reported total is reached.
  module Pagination
    DEFAULT_PAGE_SIZE = 100

    module_function

    # Lazily enumerates all items across all pages. fetch_page is called with
    # (limit, offset) and must return a List; `first(n)` fetches only as many
    # pages as needed.
    #
    # @return [Enumerator::Lazy<Resource>]
    def each_item(page_size: DEFAULT_PAGE_SIZE, &fetch_page)
      raise ArgumentError, "page_size must be positive" unless page_size.positive?

      Enumerator.new do |yielder|
        offset = 0
        loop do
          page = fetch_page.call(page_size, offset)
          page.each { |item| yielder << item }
          offset += page.size
          break if page.size < page_size || (page.total_count && offset >= page.total_count)
        end
      end.lazy
    end
  end
end
