# frozen_string_literal: true

module GrommunioAdminApi
  module Resources
    # One domain from /system/domains.
    class Domain < Resource
      field :id, key: "ID"
      field :organization_id, key: "orgID"
      field :domainname
      field :displayname
      field :domain_status, key: "domainStatus"
      field :max_user, key: "maxUser"
      field :active_users, key: "activeUsers"
      field :inactive_users, key: "inactiveUsers"
      field :virtual_users, key: "virtualUsers"
      field :chat
      field :homeserver
    end
  end
end
