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

    it "blocks writes for any mode that is not sync_only" do
      conn = build_connection
      conn.instance_variable_set(:@mode, :some_future_mode)

      expect do
        conn.request(:post, "/domains/ldap/importUser")
      end.to raise_error(GrommunioAdminApi::SyncOperationNotAllowedError)

      expect(a_request(:any, /.+/)).not_to have_been_made
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
