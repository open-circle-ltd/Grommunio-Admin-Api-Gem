# frozen_string_literal: true

require "yaml"

V1_OPERATIONS = {
  "POST /login" => "Client#login!",
  "GET /status" => "Client#status",
  "GET /about" => "Client#about",
  "GET /system/orgs" => "Organizations#list",
  "GET /system/orgs/{ID}" => "Organizations#get",
  "GET /system/domains" => "Domains#list",
  "GET /system/domains/{domainID}" => "Domains#get",
  "GET /domains/{domainID}/users" => "Users#list",
  "GET /domains/{domainID}/users/{userID}" => "Users#get",
  "GET /domains/ldap/search" => "Ldap#search",
  "POST /domains/ldap/importUser" => "Ldap#import_user",
  "PUT /domains/{domainID}/users/{userID}/downsync" => "Users#downsync",
  "POST /domains/{domainID}/users" => "Users#create",
  "GET /domains/{domainID}/users/{userID}/delegates" => "Users#delegates",
  "PUT /domains/{domainID}/users/{userID}/delegates" => "Users#set_delegates",
  "GET /domains/{domainID}/users/{userID}/sendas" => "Users#sendas",
  "PUT /domains/{domainID}/users/{userID}/sendas" => "Users#set_sendas",
  "GET /domains/{domainID}/users/{userID}/storeAccess" => "Users#store_access",
  "POST /domains/{domainID}/users/{userID}/storeAccess" => "Users#grant_store_access",
  "PUT /domains/{domainID}/users/{userID}/storeAccess" => "Users#set_store_access",
  "DELETE /domains/{domainID}/users/{userID}/storeAccess/{username}" => "Users#revoke_store_access"
}.freeze

# The lowest mode each mutation needs. read_only permits none of them; the
# login is exempt because every mode has to be able to authenticate.
MUTATION_MODES = {
  "POST /domains/ldap/importUser" => :sync_only,
  "PUT /domains/{domainID}/users/{userID}/downsync" => :sync_only,
  "POST /domains/{domainID}/users" => :full_write,
  "PUT /domains/{domainID}/users/{userID}/delegates" => :full_write,
  "PUT /domains/{domainID}/users/{userID}/sendas" => :full_write,
  "POST /domains/{domainID}/users/{userID}/storeAccess" => :full_write,
  "PUT /domains/{domainID}/users/{userID}/storeAccess" => :full_write,
  "DELETE /domains/{domainID}/users/{userID}/storeAccess/{username}" => :full_write
}.freeze

RSpec.describe "V1 API surface" do
  let(:api_classes) do
    {
      "Client" => GrommunioAdminApi::Client,
      "Organizations" => GrommunioAdminApi::Api::Organizations,
      "Domains" => GrommunioAdminApi::Api::Domains,
      "Users" => GrommunioAdminApi::Api::Users,
      "Ldap" => GrommunioAdminApi::Api::Ldap
    }
  end

  # Substitutes every {placeholder} so the path can be run through the guard.
  def concrete(operation)
    verb, path = operation.split(" ", 2)
    [verb.downcase.to_sym, path.gsub(/\{[^}]+\}/, "12")]
  end

  def connection(mode)
    GrommunioAdminApi::Connection.new(base_url: "https://mail.example.test",
                                      username: "admin", password: "secret", mode: mode)
  end

  it "contains only operations present in the upstream OpenAPI document" do
    openapi = YAML.safe_load_file(File.expand_path("../fixtures/openapi.yaml", __dir__))
    upstream = openapi.fetch("paths").flat_map do |path, operations|
      operations.keys.grep(/\A(get|post|put|patch|delete)\z/).map { |verb| "#{verb.upcase} #{path}" }
    end

    expect(V1_OPERATIONS.keys - upstream).to be_empty
  end

  it "implements every manifest target as a public instance method" do
    V1_OPERATIONS.each_value do |target|
      class_name, method_name = target.split("#")
      expect(api_classes.fetch(class_name).public_method_defined?(method_name))
        .to be(true), "expected #{target} to exist"
    end
  end

  it "exposes exactly the declared public methods, and nothing else" do
    allowed = {
      "Client" => %i[login! status about mode organizations domains users ldap],
      "Organizations" => %i[list get all],
      "Domains" => %i[list get all],
      "Users" => %i[list get all downsync create delegates set_delegates sendas set_sendas
                    store_access grant_store_access set_store_access revoke_store_access],
      "Ldap" => %i[search import_user]
    }

    api_classes.each do |name, klass|
      own = klass.public_instance_methods - Object.public_instance_methods
      expect(own).to match_array(allowed.fetch(name)), "unexpected public methods on #{name}"
    end
  end

  it "declares a mode for every mutation in the manifest, and no others" do
    mutations = V1_OPERATIONS.keys.grep(/\A(POST|PUT|PATCH|DELETE)/) - ["POST /login"]

    expect(MUTATION_MODES.keys).to match_array(mutations)
    expect(MUTATION_MODES.values.uniq - GrommunioAdminApi::Connection::MODES).to be_empty
  end

  describe "the mutation policy holds for every declared write" do
    MUTATION_MODES.each do |operation, required_mode|
      it "rejects #{operation} in read_only mode without opening a socket" do
        verb, path = concrete(operation)

        expect { connection(:read_only).request(verb, path) }
          .to raise_error(GrommunioAdminApi::ReadOnlyModeError)
        expect(a_request(:any, /.+/)).not_to have_been_made
      end

      if required_mode == :full_write
        it "rejects #{operation} in sync_only mode without opening a socket" do
          verb, path = concrete(operation)

          expect { connection(:sync_only).request(verb, path) }
            .to raise_error(GrommunioAdminApi::SyncOperationNotAllowedError)
          expect(a_request(:any, /.+/)).not_to have_been_made
        end
      end

      it "permits #{operation} in #{required_mode} mode" do
        verb, path = concrete(operation)
        stub_login
        write = stub_request(verb, "#{ApiHelpers::BASE}#{path}").to_return(status: 200, body: "{}")

        connection(required_mode).request(verb, path)

        expect(write).to have_been_requested.once
      end
    end
  end
end
