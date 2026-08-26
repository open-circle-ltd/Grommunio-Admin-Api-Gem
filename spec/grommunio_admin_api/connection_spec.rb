# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::Connection do
  subject(:connection) { build_connection }

  let(:base) { "https://mail.example.test/api/v1" }
  let(:jwt) { "jwt-token-value" }
  let(:csrf) { "csrf-token-value" }

  def build_connection(**options)
    described_class.new(
      base_url: "https://mail.example.test",
      username: "admin",
      password: "secret",
      **options
    )
  end

  def stub_login
    stub_request(:post, "#{base}/login")
      .with(
        body: { "user" => "admin", "pass" => "secret" },
        headers: { "Content-Type" => "application/x-www-form-urlencoded" }
      )
      .to_return(
        status: 200,
        body: JSON.generate("grommunioAuthJwt" => jwt, "csrf" => csrf),
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "mode validation" do
    it "defaults to read_only" do
      expect(connection.mode).to eq(:read_only)
    end

    it "rejects an unsupported mode" do
      expect { build_connection(mode: :unrestricted) }.to raise_error(ArgumentError, /mode/)
    end

    it "rejects a string mode instead of treating it as an unknown mode" do
      expect { build_connection(mode: "read_only") }.to raise_error(ArgumentError, /mode/)
    end

    it "accepts full_write" do
      expect(build_connection(mode: :full_write).mode).to eq(:full_write)
    end

    it "fails closed for an unknown mode that slipped past the constructor" do
      conn = build_connection
      conn.instance_variable_set(:@mode, :some_future_mode)

      expect do
        conn.request(:post, "/domains/ldap/importUser")
      end.to raise_error(GrommunioAdminApi::SyncOperationNotAllowedError)

      expect(a_request(:any, /.+/)).not_to have_been_made
    end
  end

  describe "mutation policy per mode" do
    let(:create_path) { "/domains/12/users" }

    it "rejects a write in read_only mode before any socket access" do
      expect { connection.request(:post, create_path, json: { username: "x@y.ch" }) }
        .to raise_error(GrommunioAdminApi::ReadOnlyModeError, %r{POST /domains/12/users})

      expect(a_request(:any, /.+/)).not_to have_been_made
    end

    it "rejects a non-allowlisted write in sync_only mode before any socket access" do
      expect { build_connection(mode: :sync_only).request(:post, create_path, json: {}) }
        .to raise_error(GrommunioAdminApi::SyncOperationNotAllowedError)

      expect(a_request(:any, /.+/)).not_to have_been_made
    end

    it "permits any write in full_write mode, including the sync operations" do
      stub_login
      create = stub_request(:post, "#{base}#{create_path}").to_return(status: 201, body: JSON.generate("ID" => 1))
      import = stub_request(:post, "#{base}/domains/ldap/importUser").to_return(status: 200, body: "{}")
      conn = build_connection(mode: :full_write)

      conn.request(:post, create_path, json: { username: "x@y.ch" })
      conn.request(:post, "/domains/ldap/importUser")

      expect(create).to have_been_requested.once
      expect(import).to have_been_requested.once
    end
  end

  describe "verb normalization" do
    it "guards an uppercase or string verb like the symbol form" do
      [:POST, "post", :Post, "DELETE"].each do |verb|
        expect { connection.request(verb, "/domains/12/users", json: { username: "x@y.ch" }) }
          .to raise_error(GrommunioAdminApi::ReadOnlyModeError)
      end

      expect(a_request(:any, /.+/)).not_to have_been_made
    end

    it "sends the CSRF token for an uppercase verb" do
      stub_login
      write = stub_request(:post, "#{base}/domains/12/users")
              .with(headers: { "X-Csrf-Token" => csrf })
              .to_return(status: 201, body: JSON.generate("ID" => 1))

      build_connection(mode: :full_write).request(:POST, "/domains/12/users", json: { username: "x@y.ch" })

      expect(write).to have_been_requested.once
    end
  end

  describe "CSRF token on login" do
    def stub_login_without_csrf
      stub_request(:post, "#{base}/login")
        .to_return(status: 200, body: JSON.generate("grommunioAuthJwt" => jwt))
    end

    it "rejects a csrf-less login for a writing mode" do
      stub_login_without_csrf

      expect { build_connection(mode: :full_write).login! }
        .to raise_error(GrommunioAdminApi::AuthenticationError, /CSRF/)
    end

    it "accepts a csrf-less login in read_only mode, where no write can need it" do
      stub_login_without_csrf

      expect(build_connection.login!).to be(true)
    end
  end

  describe "JSON request bodies" do
    before { stub_login }

    it "encodes a hash body as JSON and sends the CSRF token" do
      write = stub_request(:post, "#{base}/domains/12/users")
              .with(body: JSON.generate("username" => "info@asc-test.ch", "status" => 4),
                    headers: { "Content-Type" => "application/json", "X-Csrf-Token" => csrf })
              .to_return(status: 201, body: JSON.generate("ID" => 77))

      body = build_connection(mode: :full_write)
             .request(:post, "/domains/12/users", json: { username: "info@asc-test.ch", status: 4 })

      expect(write).to have_been_requested.once
      expect(body).to eq("ID" => 77)
    end

    it "encodes a bare array body, as the delegates and sendas endpoints expect" do
      write = stub_request(:put, "#{base}/domains/12/users/44/delegates")
              .with(body: JSON.generate(["a@asc-test.ch"]),
                    headers: { "Content-Type" => "application/json" })
              .to_return(status: 200, body: "")

      result = build_connection(mode: :full_write)
               .request(:put, "/domains/12/users/44/delegates", json: ["a@asc-test.ch"])

      expect(write).to have_been_requested.once
      expect(result).to be_nil
    end

    it "keeps form encoding for the login, which carries no JSON payload" do
      login = stub_request(:post, "#{base}/login")
              .with(headers: { "Content-Type" => "application/x-www-form-urlencoded" })
              .to_return(status: 200, body: JSON.generate("grommunioAuthJwt" => jwt, "csrf" => csrf))

      build_connection(mode: :full_write).login!

      expect(login).to have_been_requested.once
    end
  end

  describe "base URL normalization" do
    it "requires an http or https scheme" do
      expect { described_class.new(base_url: "mail.example.test") }.to raise_error(ArgumentError, /scheme/)
    end

    it "appends /api/v1 when missing" do
      expect(connection.base_url).to eq("https://mail.example.test/api/v1")
    end

    it "removes duplicate and trailing slashes" do
      conn = described_class.new(base_url: "https://mail.example.test//api/v1/")
      expect(conn.base_url).to eq("https://mail.example.test/api/v1")
    end

    it "keeps an explicitly configured path instead of appending /api/v1" do
      conn = described_class.new(base_url: "https://mail.example.test/admin/api/v1")
      expect(conn.base_url).to eq("https://mail.example.test/admin/api/v1")
    end

    it "preserves the case of a configured path" do
      conn = described_class.new(base_url: "https://mail.example.test/Admin/APIv1")
      expect(conn.base_url).to eq("https://mail.example.test/Admin/APIv1")
    end

    it "accepts an uppercase scheme" do
      conn = described_class.new(base_url: "HTTPS://mail.example.test")
      expect(conn.base_url).to eq("https://mail.example.test/api/v1")
    end

    it "requires a host" do
      expect { described_class.new(base_url: "https:///api/v1") }.to raise_error(ArgumentError, /host/)
    end

    it "rejects a scheme without any host at all" do
      expect { described_class.new(base_url: "https://") }.to raise_error(ArgumentError, /host/)
    end

    it "rejects a nil base_url" do
      expect { described_class.new(base_url: nil) }.to raise_error(ArgumentError, /scheme/)
    end
  end

  describe "TLS and timeout configuration" do
    it "verifies peer certificates by default" do
      http = connection.send(:http, URI("https://mail.example.test/api/v1"))

      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
    end

    it "disables verification when verify_ssl is false" do
      http = build_connection(verify_ssl: false).send(:http, URI("https://mail.example.test/api/v1"))

      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_NONE)
    end

    it "applies the configured timeouts" do
      http = build_connection(open_timeout: 3, read_timeout: 30)
             .send(:http, URI("https://mail.example.test/api/v1"))

      expect(http.open_timeout).to eq(3)
      expect(http.read_timeout).to eq(30)
    end

    it "defaults the timeouts" do
      expect(connection).to have_attributes(open_timeout: 5, read_timeout: 60)
    end
  end

  describe "authentication" do
    it "logs in with form encoded credentials, even in read_only mode" do
      login = stub_login

      expect(connection.login!).to be(true)
      expect(connection.mode).to eq(:read_only)
      expect(login).to have_been_requested.once
    end

    it "does not return the session token" do
      stub_login

      expect(connection.login!).not_to be_a(Hash)
    end

    it "raises AuthenticationError without credentials and opens no socket" do
      conn = described_class.new(base_url: "https://mail.example.test")

      expect { conn.login! }.to raise_error(GrommunioAdminApi::AuthenticationError, /credentials/)
      expect_no_http_requests
    end

    it "permits reads in sync_only mode" do
      stub_login
      status = stub_request(:get, "#{base}/status").to_return(status: 200, body: '{"status":"ok"}')

      expect(build_connection(mode: :sync_only).request(:get, "/status")).to eq("status" => "ok")
      expect(status).to have_been_requested.once
    end

    it "sends the JWT cookie on authenticated reads" do
      stub_login
      status = stub_request(:get, "#{base}/status")
               .with(headers: { "Cookie" => "grommunioAuthJwt=#{jwt}" })
               .to_return(status: 200, body: '{"status":"ok"}')

      expect(connection.request(:get, "/status")).to eq("status" => "ok")
      expect(status).to have_been_requested.once
    end

    it "sends JWT and CSRF on permitted sync writes" do
      stub_login
      import = stub_request(:post, "#{base}/domains/ldap/importUser")
               .with(headers: { "Cookie" => "grommunioAuthJwt=#{jwt}", "X-Csrf-Token" => csrf })
               .to_return(status: 200, body: '{"ID":1}')

      conn = build_connection(mode: :sync_only)
      expect(conn.request(:post, "/domains/ldap/importUser")).to eq("ID" => 1)
      expect(import).to have_been_requested.once
    end

    it "re-authenticates and replays exactly once after a 401" do
      login = stub_login
      status = stub_request(:get, "#{base}/status")
               .to_return({ status: 401, body: "{}" }, { status: 200, body: '{"status":"ok"}' })

      expect(connection.request(:get, "/status")).to eq("status" => "ok")
      expect(login).to have_been_requested.twice
      expect(status).to have_been_requested.twice
    end

    it "replays the idempotent sync writes after a 401" do
      login = stub_login
      import = stub_request(:post, "#{base}/domains/ldap/importUser")
               .to_return({ status: 401, body: "{}" }, { status: 200, body: '{"ID":44}' })

      build_connection(mode: :sync_only).request(:post, "/domains/ldap/importUser")

      expect(login).to have_been_requested.twice
      expect(import).to have_been_requested.twice
    end

    it "never replays a create, which may already have been applied upstream" do
      stub_login
      create = stub_request(:post, "#{base}/domains/12/users").to_return(status: 401, body: "{}")

      expect do
        build_connection(mode: :full_write).request(:post, "/domains/12/users", json: { username: "x@y.ch" })
      end.to raise_error(GrommunioAdminApi::AuthenticationError)

      expect(create).to have_been_requested.once
    end

    it "never replays a store access grant" do
      stub_login
      grant = stub_request(:post, "#{base}/domains/12/users/44/storeAccess").to_return(status: 401, body: "{}")

      expect do
        build_connection(mode: :full_write).request(:post, "/domains/12/users/44/storeAccess",
                                                    json: { username: "kim@y.ch" })
      end.to raise_error(GrommunioAdminApi::AuthenticationError)

      expect(grant).to have_been_requested.once
    end

    it "raises AuthenticationError after the replay also returns 401" do
      stub_login
      stub_request(:get, "#{base}/status").to_return(status: 401, body: "{}")

      expect { connection.request(:get, "/status") }.to raise_error(GrommunioAdminApi::AuthenticationError)
    end

    it "raises AuthenticationError when the login response has no body" do
      stub_request(:post, "#{base}/login").to_return(status: 204, body: "")

      expect { connection.login! }
        .to raise_error(GrommunioAdminApi::AuthenticationError, /session token/)
    end

    it "raises AuthenticationError when the login response omits the session token" do
      login = stub_request(:post, "#{base}/login")
              .to_return(status: 200, body: JSON.generate("csrf" => csrf))
      status = stub_request(:get, "#{base}/status").to_return(status: 200, body: "{}")

      expect { connection.request(:get, "/status") }
        .to raise_error(GrommunioAdminApi::AuthenticationError, /session token/)

      expect(login).to have_been_requested.once
      expect(status).not_to have_been_requested
    end

    it "never exposes password, JWT, or CSRF through inspect, to_s, or errors" do
      stub_login
      stub_request(:get, "#{base}/status").to_return(status: 401, body: "{}")

      error = nil
      begin
        connection.request(:get, "/status")
      rescue GrommunioAdminApi::AuthenticationError => e
        error = e
      end

      [connection.inspect, connection.to_s, error.message, error.inspect].each do |text|
        expect(text).not_to include("secret")
        expect(text).not_to include(jwt)
        expect(text).not_to include(csrf)
      end
    end
  end

  describe "error mapping" do
    before { stub_login }

    {
      400 => GrommunioAdminApi::ValidationError,
      401 => GrommunioAdminApi::AuthenticationError,
      403 => GrommunioAdminApi::ForbiddenError,
      404 => GrommunioAdminApi::NotFoundError,
      422 => GrommunioAdminApi::ValidationError,
      500 => GrommunioAdminApi::ServerError,
      503 => GrommunioAdminApi::ServiceUnavailableError
    }.each do |status, error_class|
      it "maps HTTP #{status} to #{error_class.name.split("::").last}" do
        stub_request(:get, "#{base}/status")
          .to_return(status: status, body: JSON.generate("message" => "upstream says no"))

        expect { connection.request(:get, "/status") }.to raise_error(error_class) do |error|
          expect(error).to have_attributes(
            status: status,
            body: { "message" => "upstream says no" },
            server_message: "upstream says no"
          )
        end
      end
    end

    it "maps SocketError to ConnectionError" do
      stub_request(:get, "#{base}/status").to_raise(SocketError)
      expect { connection.request(:get, "/status") }.to raise_error(GrommunioAdminApi::ConnectionError)
    end

    it "maps Net::OpenTimeout to ConnectionError" do
      stub_request(:get, "#{base}/status").to_raise(Net::OpenTimeout)
      expect { connection.request(:get, "/status") }.to raise_error(GrommunioAdminApi::ConnectionError)
    end

    it "maps Net::ReadTimeout to ConnectionError" do
      stub_request(:get, "#{base}/status").to_raise(Net::ReadTimeout)
      expect { connection.request(:get, "/status") }.to raise_error(GrommunioAdminApi::ConnectionError)
    end

    it "maps an unusable request path to ArgumentError" do
      expect { connection.request(:get, "/domains/a b|c/users") }
        .to raise_error(ArgumentError, /invalid request path/)
    end

    it "maps invalid JSON on 2xx to ParseError" do
      stub_request(:get, "#{base}/status").to_return(status: 200, body: "<html>not json</html>")
      expect { connection.request(:get, "/status") }.to raise_error(GrommunioAdminApi::ParseError)
    end

    it "returns nil for 204" do
      stub_request(:get, "#{base}/status").to_return(status: 204, body: "")
      expect(connection.request(:get, "/status")).to be_nil
    end
  end
end
