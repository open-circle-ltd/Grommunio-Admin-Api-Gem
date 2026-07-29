# frozen_string_literal: true

module ApiHelpers
  BASE = "https://mail.example.test/api/v1"
  JWT = "jwt-token-value"
  CSRF = "csrf-token-value"

  def build_client(**)
    GrommunioAdminApi::Client.new(
      base_url: "https://mail.example.test",
      username: "admin",
      password: "secret",
      **
    )
  end

  def stub_login
    stub_request(:post, "#{BASE}/login")
      .with(body: { "user" => "admin", "pass" => "secret" })
      .to_return(status: 200, body: JSON.generate("grommunioAuthJwt" => JWT, "csrf" => CSRF))
  end

  def stub_get(path, body, query: nil)
    stub = stub_request(:get, "#{BASE}#{path}")
    stub = stub.with(query: query) if query
    stub.to_return(status: 200, body: JSON.generate(body))
  end

  # Proves a guard rejected an operation before opening a socket — no login
  # request either.
  def expect_no_http_requests
    expect(a_request(:any, /.+/)).not_to have_been_made
  end
end

RSpec.configure do |config|
  config.include ApiHelpers
end
