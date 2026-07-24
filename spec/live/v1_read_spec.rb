# frozen_string_literal: true

# Read-only verification against a real Grommunio instance. Opt-in via the
# GROMMUNIO_* environment variables (see .env.example); always read_only.
#
#   bundle exec rspec spec/live/v1_read_spec.rb
RSpec.describe "live V1 reads", :live do
  before { skip_unless_live_env! }

  let(:client) { live_client(mode: :read_only) }

  it "verifies the complete V1 read surface" do
    expect(client.login!).to include("csrf")
    expect(client.status).to be_a(Hash)
    expect(client.about).to include("API")

    organization = client.organizations.get(organization_id: live_organization_id)
    expect(organization.id).to eq(live_organization_id)

    domain = client.domains.get(domain_id: live_domain_id)
    expect(domain.id).to eq(live_domain_id)
    expect(domain.organization_id).to eq(live_organization_id)

    users = client.users.list(domain_id: live_domain_id, limit: 2)
    expect(users.size).to be <= 2
    users.each { |user| expect(user.id).to be_a(Integer) }
  end
end
