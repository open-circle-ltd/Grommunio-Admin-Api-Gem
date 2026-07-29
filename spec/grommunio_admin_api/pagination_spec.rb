# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::Pagination do
  def list(ids, count: nil)
    payload = { "data" => ids.map { |id| { "ID" => id } } }
    payload["count"] = count if count
    GrommunioAdminApi::List.new(payload, resource_class: GrommunioAdminApi::Resource)
  end

  it "fetches only the first page for first(1)" do
    calls = []
    items = described_class.each_item(page_size: 2) do |limit, offset|
      calls << [limit, offset]
      list([1, 2], count: 4)
    end

    expect(items.first(1).map { |r| r["ID"] }).to eq([1])
    expect(calls).to eq([[2, 0]])
  end

  it "requests the second page with the expected offset" do
    calls = []
    items = described_class.each_item(page_size: 2) do |limit, offset|
      calls << [limit, offset]
      offset.zero? ? list([1, 2], count: 3) : list([3], count: 3)
    end

    expect(items.map { |r| r["ID"] }.to_a).to eq([1, 2, 3])
    expect(calls).to eq([[2, 0], [2, 2]])
  end

  it "stops when fetched items reach total_count" do
    calls = 0
    items = described_class.each_item(page_size: 2) do |_limit, offset|
      calls += 1
      offset.zero? ? list([1, 2], count: 4) : list([3, 4], count: 4)
    end

    expect(items.to_a.size).to eq(4)
    expect(calls).to eq(2)
  end

  it "stops on a short page when count is absent" do
    calls = 0
    items = described_class.each_item(page_size: 2) do |_limit, offset|
      calls += 1
      offset.zero? ? list([1, 2]) : list([3])
    end

    expect(items.to_a.size).to eq(3)
    expect(calls).to eq(2)
  end

  it "does not truncate silently" do
    items = described_class.each_item(page_size: 2) do |_limit, offset|
      case offset
      when 0 then list([1, 2], count: 5)
      when 2 then list([3, 4], count: 5)
      else list([5], count: 5)
      end
    end

    expect(items.to_a.size).to eq(5)
  end

  it "keeps paging when the server clamps the page size below the requested limit" do
    calls = []
    items = described_class.each_item(page_size: 4) do |limit, offset|
      calls << [limit, offset]
      # Server caps every page at 2 items but reports the real total.
      list([1, 2, 3, 4, 5].drop(offset).take(2), count: 5)
    end

    expect(items.map { |r| r["ID"] }.to_a).to eq([1, 2, 3, 4, 5])
    expect(calls).to eq([[4, 0], [4, 2], [4, 4]])
  end

  it "stops on an empty page even when the reported total is higher" do
    calls = 0
    items = described_class.each_item(page_size: 2) do |_limit, offset|
      calls += 1
      offset.zero? ? list([1, 2], count: 10) : list([], count: 10)
    end

    expect(items.to_a.size).to eq(2)
    expect(calls).to eq(2)
  end

  it "rejects a non-positive page size" do
    expect { described_class.each_item(page_size: 0) { |_l, _o| list([]) } }.to raise_error(ArgumentError)
  end
end
