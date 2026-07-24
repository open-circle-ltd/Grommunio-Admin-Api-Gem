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
  end

  describe "authentication" do
    it "logs in with form encoded credentials" do
      login = stub_login

      connection.login!

      expect(login).to have_been_requested.once
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

        connection.request(:get, "/status")
        raise "expected #{error_class} to be raised"
      rescue error_class => e
        expect(e.status).to eq(status)
        expect(e.body).to eq("message" => "upstream says no")
        expect(e.server_message).to eq("upstream says no")
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
      stub_request(:get, "#{base}/status").to_timeout
      expect { connection.request(:get, "/status") }.to raise_error(GrommunioAdminApi::ConnectionError)
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
