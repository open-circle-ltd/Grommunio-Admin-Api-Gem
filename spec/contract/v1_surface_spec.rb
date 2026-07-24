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
  it "contains only operations present in the upstream OpenAPI document" do
    openapi = YAML.safe_load_file(File.expand_path("../fixtures/openapi.yaml", __dir__))
    upstream = openapi.fetch("paths").flat_map do |path, operations|
      operations.keys.grep(/\A(get|post|put|patch|delete)\z/).map { |verb| "#{verb.upcase} #{path}" }
    end

    expect(V1_OPERATIONS.keys - upstream).to be_empty
  end
end
