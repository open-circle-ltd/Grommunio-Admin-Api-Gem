# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::Api::Ldap do
  describe "read_only safety" do
    let(:client) { build_client(mode: :read_only) }

    it "rejects import_user before any socket access, including login" do
      expect do
        client.ldap.import_user(ldap_object_id: "id", domain_id: 12, organization_id: 12)
      end.to raise_error(GrommunioAdminApi::ReadOnlyModeError)

      expect_no_http_requests
    end

    it "rejects users.downsync before any socket access, including login" do
      expect do
        client.users.downsync(domain_id: 12, user_id: 44)
      end.to raise_error(GrommunioAdminApi::ReadOnlyModeError)

      expect_no_http_requests
    end
  end

  describe "sync_only allowlist" do
    let(:connection) do
      GrommunioAdminApi::Connection.new(
        base_url: "https://mail.example.test", username: "admin", password: "secret", mode: :sync_only
      )
    end

    it "permits exactly the targeted import and downsync operations" do
      stub_login
      import = stub_request(:post, "#{ApiHelpers::BASE}/domains/ldap/importUser")
               .to_return(status: 201, body: '{"ID":44}')
      downsync = stub_request(:put, "#{ApiHelpers::BASE}/domains/12/users/44/downsync")
                 .to_return(status: 200, body: '{"ID":44}')

      connection.request(:post, "/domains/ldap/importUser")
      connection.request(:put, "/domains/12/users/44/downsync")

      expect(import).to have_been_requested.once
      expect(downsync).to have_been_requested.once
    end

    [
      [:post, "/system/domains"],
      [:patch, "/domains/12/users/44"],
      [:post, "/domains/12/ldap/downsync"],
      [:post, "/system/orgs/12/ldap/downsync"],
      [:delete, "/domains/12/users/44"]
    ].each do |method, path|
      it "rejects #{method.to_s.upcase} #{path} before HTTP" do
        expect do
          connection.request(method, path)
        end.to raise_error(GrommunioAdminApi::SyncOperationNotAllowedError)

        expect_no_http_requests
      end
    end
  end

  describe "#search" do
    before { stub_login }

    let(:client) { build_client }

    it "searches with exact query encoding" do
      search = stub_get("/domains/ldap/search",
                        { "data" => [{ "ID" => "ldap-1", "name" => "Test User",
                                       "email" => "test.user@asc-test.ch", "type" => "user" }] },
                        query: { "query" => "test.user", "domain" => "12", "organization" => "12",
                                 "showAll" => "false", "limit" => "20" })

      result = client.ldap.search(query: "test.user", domain_id: 12, organization_id: 12,
                                  show_all: false, limit: 20)

      expect(search).to have_been_requested.once
      candidate = result.first
      expect(candidate).to have_attributes(
        id: "ldap-1", name: "Test User", email: "test.user@asc-test.ch", type: "user"
      )
      expect(candidate.raw).to eq(
        "ID" => "ldap-1", "name" => "Test User", "email" => "test.user@asc-test.ch", "type" => "user"
      )
    end

    it "requires at least three non-whitespace characters without any HTTP request" do
      expect { client.ldap.search(query: " a b ") }.to raise_error(ArgumentError, /three/)
      expect_no_http_requests
    end
  end

  describe "#import_user" do
    let(:client) { build_client(mode: :sync_only) }
    let(:user_body) { { "ID" => 44, "username" => "test.user@asc-test.ch", "domainID" => 12 } }

    it "imports with exact query keys and JWT plus CSRF" do
      stub_login
      import = stub_request(:post, "#{ApiHelpers::BASE}/domains/ldap/importUser")
               .with(
                 query: { "ID" => "opaque-upstream-id", "domain" => "12", "organization" => "12",
                          "lang" => "de_DE", "force" => "false" },
                 headers: { "Cookie" => "grommunioAuthJwt=#{ApiHelpers::JWT}", "X-Csrf-Token" => ApiHelpers::CSRF }
               )
               .to_return(status: 201, body: JSON.generate(user_body))

      user = client.ldap.import_user(ldap_object_id: "opaque-upstream-id", domain_id: 12,
                                     organization_id: 12, language: "de_DE", force: false)

      expect(import).to have_been_requested.once
      expect(user).to be_a(GrommunioAdminApi::Resources::User)
      expect(user.username).to eq("test.user@asc-test.ch")
    end

    it "returns a generic resource for a message-only response without losing data" do
      stub_login
      stub_request(:post, "#{ApiHelpers::BASE}/domains/ldap/importUser")
        .with(query: { "ID" => "opaque-upstream-id" })
        .to_return(status: 200, body: JSON.generate("message" => "contact import queued"))

      result = client.ldap.import_user(ldap_object_id: "opaque-upstream-id")

      expect(result).to be_an_instance_of(GrommunioAdminApi::Resource)
      expect(result["message"]).to eq("contact import queued")
    end
  end

  describe "Users#downsync" do
    let(:client) { build_client(mode: :sync_only) }

    it "downsyncs with the exact endpoint and optional ID/lang parameters" do
      stub_login
      downsync = stub_request(:put, "#{ApiHelpers::BASE}/domains/12/users/44/downsync")
                 .with(query: { "ID" => "opaque-upstream-id", "lang" => "de_DE" })
                 .to_return(status: 200, body: '{"ID":44,"username":"test.user@asc-test.ch"}')

      user = client.users.downsync(domain_id: 12, user_id: 44,
                                   ldap_object_id: "opaque-upstream-id", language: "de_DE")

      expect(downsync).to have_been_requested.once
      expect(user).to be_a(GrommunioAdminApi::Resources::User)
    end

    it "omits optional parameters and wraps a message-only response generically" do
      stub_login
      downsync = stub_request(:put, "#{ApiHelpers::BASE}/domains/12/users/44/downsync")
                 .with(query: {})
                 .to_return(status: 200, body: '{"message":"synchronized"}')

      result = client.users.downsync(domain_id: 12, user_id: 44)

      expect(downsync).to have_been_requested.once
      expect(result).to be_an_instance_of(GrommunioAdminApi::Resource)
    end
  end
end
