# frozen_string_literal: true

# Controlled live shared-mailbox creation. Runs only with explicit opt-in
# (GROMMUNIO_LIVE_MUTATE=1) against a non-production instance, because it
# leaves a real object behind: this gem exposes no user deletion, so the
# created mailbox has to be removed in the admin web afterwards.
#
# It answers the three things the OpenAPI document does not:
#   - is a password required for status 4 (shared mailbox)?
#   - what does the 201 body actually carry?
#   - which status code comes back for a duplicate username?
#
#   GROMMUNIO_LIVE_MUTATE=1 GROMMUNIO_LIVE_SHARED_MAILBOX=info.test@example.ch \
#     bundle exec rspec spec/live/v1_write_spec.rb
RSpec.describe "live V1 writes", :live do
  before do
    skip "GROMMUNIO_LIVE_MUTATE=1 not set" unless ENV["GROMMUNIO_LIVE_MUTATE"] == "1"
    skip_unless_live_env!("GROMMUNIO_LIVE_SHARED_MAILBOX")
  end

  let(:client) { live_client(mode: :full_write) }
  let(:username) { ENV.fetch("GROMMUNIO_LIVE_SHARED_MAILBOX") }
  let(:attributes) do
    # No password on purpose - the admin web asks for none when creating a
    # shared mailbox, and userInit declares no required field. A 400 here is
    # the finding, not a broken spec.
    { "username" => username, "status" => 4,
      "properties" => { "displayname" => "Live write spec" } }
  end

  it "creates a shared mailbox without a password and reports the duplicate status" do
    existing = client.users.list(domain_id: live_domain_id, username: username)
    skip "#{username} already exists upstream - remove it in the admin web first" unless existing.empty?

    created = client.users.create(domain_id: live_domain_id, attributes: attributes)

    expect(created).to be_a(GrommunioAdminApi::Resources::User)
    expect(created.id).to be_a(Integer)
    expect(created.username).to eq(username)
    expect(created).to be_shared_mailbox
    expect(created.domain_id).to eq(live_domain_id)

    # The consumer builds its local row from this response, so the readable
    # payload is part of the contract, not a detail.
    warn "201 body: #{created.to_h.inspect}"

    duplicate = nil
    begin
      client.users.create(domain_id: live_domain_id, attributes: attributes)
    rescue GrommunioAdminApi::ApiError => e
      duplicate = e
    end

    expect(duplicate).not_to be_nil, "a duplicate username was accepted - that changes the consumer's error handling"
    warn "duplicate username -> HTTP #{duplicate.status} (#{duplicate.class}), body: #{duplicate.body.inspect}"

    warn "REMINDER: remove #{username} from domain #{live_domain_id} in the admin web"
  end
end
