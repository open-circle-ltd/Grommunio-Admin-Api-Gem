# frozen_string_literal: true

module GrommunioAdminApi
  # Offset-based auto-pagination over the paginated list endpoints.
  #
  # Never truncates silently: when the server reports a total, pages are
  # fetched until that total is reached — a page shorter than requested only
  # ends the run when no total is available, because servers may clamp the
  # requested limit. An empty page always ends the run so a total that
  # overstates the available data cannot spin forever.
  module Pagination
    # Matches the server-side default limit of the admin-api list endpoints,
    # so a clamped page cannot be mistaken for the last page.
    DEFAULT_PAGE_SIZE = 50

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
          break if last_page?(page, offset, page_size)
        end
      end.lazy
    end

    def last_page?(page, offset, page_size)
      return true if page.empty?

      page.total_count ? offset >= page.total_count : page.size < page_size
    end
    private_class_method :last_page?
  end
end
