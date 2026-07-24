# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::Client do
  it "defaults to read_only mode" do
    client = described_class.new(base_url: "https://mail.example.test", username: "admin", password: "secret")

    expect(client.mode).to eq(:read_only)
  end

  it "rejects an unsupported mode" do
    expect do
      described_class.new(base_url: "https://mail.example.test", mode: :unrestricted)
    end.to raise_error(ArgumentError, /mode/)
  end

  describe "diagnostics" do
    it "logs in via POST /login only" do
      login = stub_login

      build_client.login!

      expect(login).to have_been_requested.once
    end

    it "reads service health via GET /status" do
      stub_login
      status = stub_get("/status", { "status" => "ok" })

      expect(build_client.status).to eq("status" => "ok")
      expect(status).to have_been_requested.once
    end

    it "reads version diagnostics via GET /about" do
      stub_login
      about = stub_get("/about", { "API" => 1, "backend" => "1.0" })

      expect(build_client.about).to eq("API" => 1, "backend" => "1.0")
      expect(about).to have_been_requested.once
    end
  end
end
