# frozen_string_literal: true

module GrommunioAdminApi
  module Resources
    # One result of GET /domains/ldap/search. The ID is the opaque LDAP
    # object ID used by importUser and downsync.
    class LdapCandidate < Resource
      field :id, key: "ID"
      field :name
      field :email
      field :type
    end
  end
end
