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

  describe "value equality" do
    it "equals another resource of the same class with the same payload" do
      twin = described_class.new(payload.dup)

      expect(resource).to eq(twin)
      expect(resource.eql?(twin)).to be(true)
      expect(resource.hash).to eq(twin.hash)
    end

    it "does not equal a plain hash or a different resource class" do
      other_class = Class.new(described_class).new(payload.dup)

      expect(resource).not_to eq(payload)
      expect(resource).not_to eq(other_class)
    end

    it "deduplicates equal resources in a Set" do
      expect(Set[resource, described_class.new(payload.dup)].size).to eq(1)
    end
  end
end
