# frozen_string_literal: true

# Controlled live LDAP import + targeted downsync. Runs only with explicit
# opt-in (GROMMUNIO_LIVE_SYNC=1) against a dedicated persistent LDAP test
# account. Deliberately performs no deletion: user deletion is outside V1
# and cleanup would be more dangerous than the tested operation. The flow is
# idempotent — a second run updates the existing LDAP-backed user instead of
# creating a duplicate.
#
#   GROMMUNIO_LIVE_SYNC=1 bundle exec rspec spec/live/v1_sync_spec.rb
RSpec.describe "live V1 sync", :live do
  before do
    skip "GROMMUNIO_LIVE_SYNC=1 not set" unless ENV["GROMMUNIO_LIVE_SYNC"] == "1"
    skip_unless_live_env!("GROMMUNIO_LIVE_LDAP_QUERY", "GROMMUNIO_LIVE_EXPECTED_USERNAME")
  end

  let(:client) { live_client(mode: :sync_only) }
  let(:expected_username) { ENV.fetch("GROMMUNIO_LIVE_EXPECTED_USERNAME") }

  def read_client
    live_client(mode: :read_only)
  end

  it "imports and downsyncs the dedicated test account idempotently" do
    candidates = client.ldap.search(
      query: ENV.fetch("GROMMUNIO_LIVE_LDAP_QUERY"),
      domain_id: live_domain_id,
      organization_id: live_organization_id
    )
    matching = candidates.select { |candidate| candidate.email == expected_username }
    # Abort before mutation unless exactly one candidate matches.
    expect(matching.size).to eq(1), "expected exactly one LDAP candidate for #{expected_username}, " \
                                    "got #{matching.size} — aborting before mutation"

    imported = client.ldap.import_user(
      ldap_object_id: matching.first.id,
      domain_id: live_domain_id,
      organization_id: live_organization_id
    )
    expect(imported).to be_a(GrommunioAdminApi::Resources::User)
    expect(imported.username).to eq(expected_username)
    expect(imported.domain_id).to eq(live_domain_id)
    expect(imported.ldap_id).not_to be_nil

    synced = client.users.downsync(domain_id: live_domain_id, user_id: imported.id)
    expect(synced).to be_a(GrommunioAdminApi::Resource)

    refreshed = read_client.users.get(domain_id: live_domain_id, user_id: imported.id)
    expect(refreshed.id).to eq(imported.id)
    expect(refreshed.username).to eq(expected_username)

    usernames = read_client.users.all(domain_id: live_domain_id).map(&:username).to_a
    expect(usernames.count(expected_username)).to eq(1)
  end
end
