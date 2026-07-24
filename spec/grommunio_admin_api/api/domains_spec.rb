# frozen_string_literal: true

RSpec.describe GrommunioAdminApi::Api::Domains do
  before { stub_login }

  let(:client) { build_client }
  let(:domain_payload) do
    {
      "ID" => 12,
      "orgID" => 12,
      "domainname" => "asc-test.ch",
      "displayname" => "ASC Test",
      "domainStatus" => 0,
      "maxUser" => 25,
      "activeUsers" => 7,
      "inactiveUsers" => 1,
      "virtualUsers" => 2,
      "chat" => false,
      "homeserver" => nil,
      "newField" => "kept"
    }
  end

  it "lists domains with comma-encoded array filters" do
    list = stub_get("/system/domains", { "count" => 1, "data" => [domain_payload] },
                    query: { "limit" => "50", "offset" => "0", "orgID" => "12,13", "domainStatus" => "0,1" })

    result = client.domains.list(limit: 50, offset: 0, organization_ids: [12, 13], statuses: [0, 1])

    expect(list).to have_been_requested.once
    expect(result.first.domainname).to eq("asc-test.ch")
  end

  it "gets one domain with all declared fields and raw preservation" do
    stub_get("/system/domains/12", domain_payload)

    domain = client.domains.get(domain_id: 12)

    expect(domain).to have_attributes(
      id: 12, organization_id: 12, domainname: "asc-test.ch", displayname: "ASC Test",
      domain_status: 0, max_user: 25, active_users: 7, inactive_users: 1,
      virtual_users: 2, chat: false, homeserver: nil
    )
    expect(domain["newField"]).to eq("kept")
  end

  it "paginates lazily through all domains" do
    stub_get("/system/domains", { "count" => 3, "data" => [{ "ID" => 1 }, { "ID" => 2 }] },
             query: { "limit" => "2", "offset" => "0" })
    stub_get("/system/domains", { "count" => 3, "data" => [{ "ID" => 3 }] },
             query: { "limit" => "2", "offset" => "2" })

    expect(client.domains.all(page_size: 2).map(&:id).to_a).to eq([1, 2, 3])
  end
end
