# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::Api::Organizations do
  before { stub_login }

  let(:client) { build_client }

  it "lists organizations with exact query encoding" do
    list = stub_get("/system/orgs", { "count" => 1, "data" => [{ "ID" => 12, "name" => "ASC" }] },
                    query: { "limit" => "50", "offset" => "0" })

    result = client.organizations.list(limit: 50, offset: 0)

    expect(list).to have_been_requested.once
    expect(result.total_count).to eq(1)
    expect(result.first.id).to eq(12)
    expect(result.first.name).to eq("ASC")
  end

  it "gets one organization and preserves unmodeled fields" do
    stub_get("/system/orgs/12", { "ID" => 12, "name" => "ASC", "domainCount" => 2, "futureField" => "kept" })

    org = client.organizations.get(organization_id: 12)

    expect(org.id).to eq(12)
    expect(org.domain_count).to eq(2)
    expect(org["futureField"]).to eq("kept")
  end

  it "paginates lazily through all organizations" do
    page1 = stub_get("/system/orgs", { "count" => 3, "data" => [{ "ID" => 1 }, { "ID" => 2 }] },
                     query: { "limit" => "2", "offset" => "0" })
    page2 = stub_get("/system/orgs", { "count" => 3, "data" => [{ "ID" => 3 }] },
                     query: { "limit" => "2", "offset" => "2" })

    orgs = client.organizations.all(page_size: 2).to_a

    expect(orgs.map(&:id)).to eq([1, 2, 3])
    expect(page1).to have_been_requested.once
    expect(page2).to have_been_requested.once
  end
end
