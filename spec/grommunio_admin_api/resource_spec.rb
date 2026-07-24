# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::Resource do
  let(:payload) do
    {
      "ID" => 7,
      "name" => "example",
      "newUpstreamField" => "preserved",
      "nested" => { "inner" => [1, 2] }
    }
  end
  let(:resource) { described_class.new(payload) }

  it "preserves unmodeled upstream fields via string and symbol access" do
    expect(resource["newUpstreamField"]).to eq("preserved")
    expect(resource[:newUpstreamField]).to eq("preserved")
  end

  it "distinguishes missing fields" do
    expect(resource.key?("missing")).to be(false)
    expect(resource.key?("name")).to be(true)
    expect { resource.fetch("missing") }.to raise_error(KeyError)
  end

  it "round-trips the complete original payload" do
    expect(resource.to_h).to eq(payload)
  end

  it "deep-freezes the raw payload" do
    expect(resource.raw).to be_frozen
    expect(resource.raw["nested"]).to be_frozen
    expect(resource.raw["nested"]["inner"]).to be_frozen
  end

  it "declares typed readers over raw keys" do
    klass = Class.new(described_class) do
      field :id, key: "ID"
      field :name
    end
    typed = klass.new(payload)

    expect(typed.id).to eq(7)
    expect(typed.name).to eq("example")
  end

  it "holds no client or connection reference" do
    expect(resource.instance_variables).to contain_exactly(:@raw)
  end
end
