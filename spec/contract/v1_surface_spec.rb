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
  "PUT /domains/{domainID}/users/{userID}/downsync" => "Users#downsync"
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

  it "exposes no public mutation methods outside import_user and downsync" do
    allowed = {
      "Client" => %i[login! status about mode organizations domains users ldap],
      "Organizations" => %i[list get all],
      "Domains" => %i[list get all],
      "Users" => %i[list get all downsync],
      "Ldap" => %i[search import_user]
    }

    api_classes.each do |name, klass|
      own = klass.public_instance_methods - Object.public_instance_methods
      expect(own).to match_array(allowed.fetch(name)), "unexpected public methods on #{name}"
    end
  end
end
