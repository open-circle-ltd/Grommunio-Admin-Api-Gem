# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::List do
  let(:klass) do
    Class.new(GrommunioAdminApi::Resource) { field :id, key: "ID" }
  end
  let(:payload) { { "count" => 3, "data" => [{ "ID" => 1 }, { "ID" => 2 }] } }
  let(:list) { described_class.new(payload, resource_class: klass) }

  it "exposes the server-reported total count" do
    expect(list.total_count).to eq(3)
  end

  it "wraps each data element in the resource class" do
    expect(list.map(&:id)).to eq([1, 2])
    expect(list.size).to eq(2)
  end

  it "keeps the complete raw payload" do
    expect(list.raw).to eq(payload)
  end

  it "is enumerable" do
    expect(list.first.id).to eq(1)
    expect(list).not_to be_empty
  end

  it "handles a missing count" do
    bare = described_class.new({ "data" => [{ "ID" => 1 }] }, resource_class: klass)
    expect(bare.total_count).to be_nil
  end
end
