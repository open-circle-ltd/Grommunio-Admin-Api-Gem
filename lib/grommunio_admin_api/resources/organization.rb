# frozen_string_literal: true

module GrommunioAdminApi
  module Resources
    class Organization < Resource
      field :id, key: "ID"
      field :name
      field :description
      field :domain_count, key: "domainCount"
      field :domains
    end
  end
end
