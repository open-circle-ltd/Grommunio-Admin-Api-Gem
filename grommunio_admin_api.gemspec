# frozen_string_literal: true

require_relative "lib/grommunio_admin_api/version"

Gem::Specification.new do |spec|
  spec.name = "grommunio_admin_api"
  spec.version = GrommunioAdminApi::VERSION
  spec.authors = ["Christian"]
  spec.email = ["christian.siegrist@open-circle.ch"]

  spec.summary = "Minimal client for the Grommunio Admin API"
  spec.description = "Read-only inventory, LDAP candidate search, targeted LDAP user import, " \
                     "and targeted user downsync against the Grommunio Admin API."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship the library plus licence and readme only. An allowlist keeps specs,
  # tooling, and local configuration such as .env.example out of the package
  # even when new files are added at the repository root.
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      f.start_with?("lib/") || %w[README.md LICENSE.txt].include?(f)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
