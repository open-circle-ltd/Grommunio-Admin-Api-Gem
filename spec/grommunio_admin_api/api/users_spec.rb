# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::Api::Users do
  before { stub_login }

  let(:client) { build_client }
  let(:user_payload) do
    {
      "ID" => 44,
      "username" => "user@asc-test.ch",
      "domainID" => 12,
      "orgID" => 12,
      "status" => 0,
      "ldapID" => "opaque-ldap-id",
      "aliases" => ["alias@asc-test.ch"],
      "altnames" => [],
      "properties" => { "displayname" => "Test User" },
      "roles" => [],
      "maildir" => "/var/lib/gromox/user/1/2",
      "lang" => "de_DE",
      "homeserver" => nil,
      "privArchive" => true,
      "forward" => nil
    }
  end

  describe "#list" do
    it "lists users with exact query encoding" do
      list = stub_get("/domains/12/users", { "count" => 1, "data" => [user_payload] },
                      query: { "level" => "2", "limit" => "50", "offset" => "0", "username" => "user@asc-test.ch" })

      result = client.users.list(domain_id: 12, level: 2, limit: 50, offset: 0, username: "user@asc-test.ch")

      expect(list).to have_been_requested.once
      expect(result.first.username).to eq("user@asc-test.ch")
    end

    it "forwards the properties filter" do
      list = stub_get("/domains/12/users", { "count" => 1, "data" => [user_payload] },
                      query: { "properties" => "displayname,smtpaddress" })

      client.users.list(domain_id: 12, properties: "displayname,smtpaddress")

      expect(list).to have_been_requested.once
    end
  end

  describe "#get" do
    it "gets one user with all declared fields and raw preservation" do
      stub_get("/domains/12/users/44", user_payload, query: { "level" => "2" })

      user = client.users.get(domain_id: 12, user_id: 44, level: 2)

      expect(user).to have_attributes(
        id: 44, username: "user@asc-test.ch", domain_id: 12, organization_id: 12,
        status: 0, ldap_id: "opaque-ldap-id", aliases: ["alias@asc-test.ch"], altnames: [],
        properties: { "displayname" => "Test User" }, roles: [],
        maildir: "/var/lib/gromox/user/1/2", lang: "de_DE", homeserver: nil
      )
      expect(user["privArchive"]).to be(true)
      expect(user.key?("forward")).to be(true)
    end
  end

  describe "#all" do
    it "paginates lazily through all users of a domain" do
      stub_get("/domains/12/users", { "count" => 3, "data" => [{ "ID" => 1 }, { "ID" => 2 }] },
               query: { "limit" => "2", "offset" => "0" })
      stub_get("/domains/12/users", { "count" => 3, "data" => [{ "ID" => 3 }] },
               query: { "limit" => "2", "offset" => "2" })

      expect(client.users.all(domain_id: 12, page_size: 2).map(&:id).to_a).to eq([1, 2, 3])
    end

    it "forwards the list filters to every page request" do
      query = { "level" => "2", "username" => "user@asc-test.ch", "properties" => "displayname,smtpaddress" }
      page1 = stub_get("/domains/12/users", { "count" => 3, "data" => [{ "ID" => 1 }, { "ID" => 2 }] },
                       query: query.merge("limit" => "2", "offset" => "0"))
      page2 = stub_get("/domains/12/users", { "count" => 3, "data" => [{ "ID" => 3 }] },
                       query: query.merge("limit" => "2", "offset" => "2"))

      users = client.users.all(domain_id: 12, level: 2, username: "user@asc-test.ch",
                               properties: "displayname,smtpaddress", page_size: 2).to_a

      expect(users.map(&:id)).to eq([1, 2, 3])
      expect(page1).to have_been_requested.once
      expect(page2).to have_been_requested.once
    end
  end

  describe "status predicates" do
    def user_with_status(status)
      GrommunioAdminApi::Resources::User.new(user_payload.merge("status" => status))
    end

    it "maps the documented status values" do
      expect(user_with_status(0)).to have_attributes(normal?: true, suspended?: false, unknown_status?: false)
      expect(user_with_status(1)).to have_attributes(suspended?: true, normal?: false)
      expect(user_with_status(3)).to have_attributes(deleted?: true, normal?: false)
      expect(user_with_status(4)).to have_attributes(shared_mailbox?: true, normal?: false)
    end

    it "maps contact and preserves unknown upstream statuses" do
      expect(user_with_status(5)).to have_attributes(contact?: true, normal?: false)
      expect(user_with_status(2)).to have_attributes(
        unknown_status?: true, status: 2,
        normal?: false, suspended?: false, deleted?: false, shared_mailbox?: false, contact?: false
      )
    end
  end

  describe "no lazy loading" do
    it "reads every declared field without any further HTTP request" do
      stub_get("/domains/12/users", { "count" => 1, "data" => [user_payload] })

      user = client.users.list(domain_id: 12).first
      WebMock.reset!

      expect(user).to have_attributes(
        id: 44, username: "user@asc-test.ch", domain_id: 12, organization_id: 12, status: 0,
        ldap_id: "opaque-ldap-id", aliases: ["alias@asc-test.ch"], altnames: [],
        properties: { "displayname" => "Test User" }, roles: [],
        maildir: "/var/lib/gromox/user/1/2", lang: "de_DE", homeserver: nil
      )
      expect_no_http_requests
    end
  end
end
