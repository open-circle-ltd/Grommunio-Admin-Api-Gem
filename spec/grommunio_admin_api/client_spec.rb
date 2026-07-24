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
end
