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

  describe "#create" do
    it "posts the userInit payload as JSON and returns the created user" do
      attributes = { username: "info@asc-test.ch", status: 4,
                     properties: { displayname: "Info" } }
      created_payload = user_payload.merge("ID" => 77, "username" => "info@asc-test.ch", "status" => 4)
      post = stub_write(:post, "/domains/12/users", status: 201, json: attributes, body: created_payload)

      created = build_client(mode: :full_write).users.create(domain_id: 12, attributes: attributes)

      expect(post).to have_been_requested.once
      expect(created).to be_a(GrommunioAdminApi::Resources::User)
      expect(created).to have_attributes(id: 77, username: "info@asc-test.ch", status: 4)
      expect(created).to be_shared_mailbox
    end

    it "returns a generic resource for a 2xx that carries no user data" do
      stub_write(:post, "/domains/12/users", status: 201, json: { username: "info@asc-test.ch" },
                                             body: { "message" => "created" })

      created = build_client(mode: :full_write).users.create(domain_id: 12,
                                                             attributes: { username: "info@asc-test.ch" })

      expect(created).to be_an_instance_of(GrommunioAdminApi::Resource)
      expect(created["message"]).to eq("created")
      expect(created).not_to respond_to(:id)
    end

    it "is rejected before any socket access in sync_only mode" do
      expect do
        build_client(mode: :sync_only).users.create(domain_id: 12, attributes: { username: "x@y.ch" })
      end.to raise_error(GrommunioAdminApi::SyncOperationNotAllowedError)

      expect_no_http_requests
    end
  end

  describe "delegates and sendas" do
    %i[delegates sendas].each do |list|
      it "reads #{list} as plain addresses" do
        get = stub_get("/domains/12/users/44/#{list}", { "data" => ["a@asc-test.ch", "b@asc-test.ch"] })

        result = client.users.public_send(list, domain_id: 12, user_id: 44)

        expect(get).to have_been_requested.once
        expect(result).to eq(["a@asc-test.ch", "b@asc-test.ch"])
        expect(result).to be_frozen
      end

      it "returns an empty list when #{list} has no data key" do
        stub_get("/domains/12/users/44/#{list}", {})

        expect(client.users.public_send(list, domain_id: 12, user_id: 44)).to eq([])
      end

      it "replaces the whole #{list} list with a bare JSON array" do
        put = stub_write(:put, "/domains/12/users/44/#{list}", json: ["a@asc-test.ch"])

        result = build_client(mode: :full_write).users
                                                .public_send(:"set_#{list}", domain_id: 12, user_id: 44,
                                                                             addresses: ["a@asc-test.ch"])

        expect(put).to have_been_requested.once
        expect(result).to be_nil
      end

      it "refuses a nil #{list} list instead of clearing it upstream" do
        expect do
          build_client(mode: :full_write).users
                                         .public_send(:"set_#{list}", domain_id: 12, user_id: 44, addresses: nil)
        end.to raise_error(ArgumentError, /Array/)

        expect_no_http_requests
      end

      it "refuses a hash #{list} list instead of sending nested pairs" do
        expect do
          build_client(mode: :full_write).users
                                         .public_send(:"set_#{list}", domain_id: 12, user_id: 44,
                                                                      addresses: { "a@asc-test.ch" => true })
        end.to raise_error(ArgumentError, /Array/)

        expect_no_http_requests
      end

      it "raises when the #{list} envelope is not the documented shape" do
        stub_get("/domains/12/users/44/#{list}", { "data" => { "a@asc-test.ch" => 1 } })

        expect { client.users.public_send(list, domain_id: 12, user_id: 44) }
          .to raise_error(GrommunioAdminApi::ParseError, /data/)
      end

      it "sends an empty array when #{list} is cleared" do
        put = stub_write(:put, "/domains/12/users/44/#{list}", json: [])

        build_client(mode: :full_write).users
                                       .public_send(:"set_#{list}", domain_id: 12, user_id: 44, addresses: [])

        expect(put).to have_been_requested.once
      end
    end
  end

  describe "store access" do
    it "reads the folder member entries as resources" do
      get = stub_get("/domains/12/users/44/storeAccess",
                     { "data" => [{ "memberID" => "3", "displayName" => "Kim", "username" => "kim@asc-test.ch" }] })

      result = client.users.store_access(domain_id: 12, user_id: 44)

      expect(get).to have_been_requested.once
      expect(result.size).to eq(1)
      expect(result.first["username"]).to eq("kim@asc-test.ch")
    end

    it "grants one address additively" do
      post = stub_write(:post, "/domains/12/users/44/storeAccess", status: 201,
                                                                   json: { username: "kim@asc-test.ch" })

      build_client(mode: :full_write).users
                                     .grant_store_access(domain_id: 12, user_id: 44, address: "kim@asc-test.ch")

      expect(post).to have_been_requested.once
    end

    it "replaces the whole list through the usernames wrapper" do
      put = stub_write(:put, "/domains/12/users/44/storeAccess",
                       json: { usernames: ["kim@asc-test.ch"] })

      build_client(mode: :full_write).users
                                     .set_store_access(domain_id: 12, user_id: 44, addresses: ["kim@asc-test.ch"])

      expect(put).to have_been_requested.once
    end

    it "raises when the store access envelope is not an object" do
      stub_request(:get, "#{ApiHelpers::BASE}/domains/12/users/44/storeAccess")
        .to_return(status: 200, body: JSON.generate([{ "username" => "kim@asc-test.ch" }]))

      expect { client.users.store_access(domain_id: 12, user_id: 44) }
        .to raise_error(GrommunioAdminApi::ParseError, /data/)
    end

    it "refuses to revoke a blank address, which would target the collection path" do
      [nil, "", ".."].each do |address|
        expect do
          build_client(mode: :full_write).users.revoke_store_access(domain_id: 12, user_id: 44, address: address)
        end.to raise_error(ArgumentError, /mail address/)
      end

      expect_no_http_requests
    end

    it "revokes one address and percent-encodes it into the path" do
      delete = stub_write(:delete, "/domains/12/users/44/storeAccess/kim%2Btest%40asc-test.ch")

      build_client(mode: :full_write).users
                                     .revoke_store_access(domain_id: 12, user_id: 44, address: "kim+test@asc-test.ch")

      expect(delete).to have_been_requested.once
    end
  end
end
