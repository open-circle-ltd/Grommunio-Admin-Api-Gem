# GrommunioAdminApi

Minimal Ruby client for the [Grommunio Admin API](https://docs.grommunio.com/), built for MSAS Cockpit: connection diagnostics, read-only organization/domain/user inventory, LDAP candidate search, targeted LDAP user import, targeted user downsync, direct user creation, and the three per-mailbox permission lists. No Rails dependency, no runtime dependencies — Ruby stdlib only.

## Installation

The gem is not published to rubygems.org. Add it from a path or Git source:

```ruby
# Gemfile
gem "grommunio_admin_api", path: "../grom-gem"
# or
gem "grommunio_admin_api", git: "<repository-url>"
```

Requires Ruby >= 3.2.

## Usage

```ruby
client = GrommunioAdminApi::Client.new(
  base_url: "https://mail.example.com:8443", # /api/v1 appended when no path is given
  username: "admin",
  password: "secret"
  # mode: :read_only is the default
  # verify_ssl: true, open_timeout: 5, read_timeout: 60 are the defaults
)

client.status                                  # service health
client.about                                   # API/backend version diagnostics

client.organizations.list(limit: 50)           # List<Organization>
client.organizations.get(organization_id: 12)  # Organization
client.domains.list(organization_ids: [12])    # List<Domain>
client.domains.all(organization_ids: [12])     # lazy pagination over all pages
client.users.list(domain_id: 12, level: 2)     # List<User>
client.users.get(domain_id: 12, user_id: 44)   # User
client.users.all(domain_id: 12, level: 2)      # every user of one domain
```

### Safety modes

Three modes, and no generic `get`/`request` escape hatch.

- `mode: :read_only` (default) — every mutation is rejected with
  `ReadOnlyModeError` before any socket access, except the login itself.
- `mode: :sync_only` — permits only the two targeted sync writes below;
  any other write raises `SyncOperationNotAllowedError` before HTTP.
- `mode: :full_write` — permits every mutation this gem exposes a method for.
  It carries **no** operation allowlist, so the per-area API classes are the
  only curated surface, and this gem deliberately exposes no user deletion.
  Note that `Connection#request` is public, so that curation is a convention,
  not an enforced boundary.

An unknown mode is rejected by the constructor, and the guard fails closed for
one that reaches it anyway.

```ruby
sync_client = GrommunioAdminApi::Client.new(base_url: ..., username: ..., password: ..., mode: :sync_only)

candidates = sync_client.ldap.search(query: "test.user", domain_id: 12, organization_id: 12)
user = sync_client.ldap.import_user(
  ldap_object_id: candidates.first.id,
  domain_id: 12,
  organization_id: 12,
  language: "de_DE"
)
sync_client.users.downsync(domain_id: 12, user_id: user.id)
```

```ruby
write_client = GrommunioAdminApi::Client.new(base_url: ..., username: ..., password: ..., mode: :full_write)

# A shared mailbox is status 4. userInit declares no required field and its
# "properties" bag is open, so the payload is passed through verbatim.
mailbox = write_client.users.create(
  domain_id: 12,
  attributes: { "username" => "info@example.com", "status" => 4,
                "properties" => { "displayname" => "Info" } }
)

# Like #import_user and #downsync, this returns a typed User for a user-shaped
# response and a plain Resource for a 2xx that carries no user data - so check
# before relying on the upstream ID.
raise "no upstream ID" unless mailbox.is_a?(GrommunioAdminApi::Resources::User)

write_client.users.delegates(domain_id: 12, user_id: mailbox.id)      # => ["kim@example.com"]
write_client.users.grant_store_access(domain_id: 12, user_id: mailbox.id, address: "kim@example.com")
```

### The three permission lists are not exclusively yours

Delegates, send-as and additional store owners can also be changed by the
mailbox owner in webmail and by an administrator in the admin web. Upstream
offers only `PUT` for delegates and send-as, which replaces the whole list —
so `set_delegates` / `set_sendas` silently drop entries somebody else added
unless you read the list first and merge. Store access additionally offers
additive verbs (`grant_store_access`, `revoke_store_access`); prefer those.

`delegates` and `sendas` return plain `Array<String>` rather than a `List`,
because the payload items are strings: hydrating them into `Resource` objects
would produce values whose field access silently misbehaves. `store_access`
returns objects (`memberID`, `displayName`, `username`) and stays a `List`.

### Authentication lifecycle

Login (`POST /login`, form-encoded) happens lazily before the first request
and can be forced with `client.login!`. The JWT cookie is sent on every
authenticated request, the CSRF token on writes. After a 401 the client
re-logs-in and replays the request exactly once; a second 401 raises
`AuthenticationError`, as does a login response that carries no session
token. Passwords and tokens never appear in `inspect`, `to_s`, or error
messages — `login!` returns `true` rather than the response body, so the
token cannot be logged by accident.

### Operation index

| Client method | HTTP operation |
|---|---|
| `client.login!` | `POST /login` |
| `client.status` | `GET /status` |
| `client.about` | `GET /about` |
| `client.organizations.list` | `GET /system/orgs` |
| `client.organizations.get` | `GET /system/orgs/{ID}` |
| `client.domains.list` | `GET /system/domains` |
| `client.domains.get` | `GET /system/domains/{domainID}` |
| `client.users.list` | `GET /domains/{domainID}/users` |
| `client.users.get` | `GET /domains/{domainID}/users/{userID}` |
| `client.ldap.search` | `GET /domains/ldap/search` |
| `client.ldap.import_user` | `POST /domains/ldap/importUser` |
| `client.users.downsync` | `PUT /domains/{domainID}/users/{userID}/downsync` |
| `client.users.create` | `POST /domains/{domainID}/users` |
| `client.users.delegates` | `GET /domains/{domainID}/users/{userID}/delegates` |
| `client.users.set_delegates` | `PUT /domains/{domainID}/users/{userID}/delegates` |
| `client.users.sendas` | `GET /domains/{domainID}/users/{userID}/sendas` |
| `client.users.set_sendas` | `PUT /domains/{domainID}/users/{userID}/sendas` |
| `client.users.store_access` | `GET /domains/{domainID}/users/{userID}/storeAccess` |
| `client.users.grant_store_access` | `POST /domains/{domainID}/users/{userID}/storeAccess` |
| `client.users.set_store_access` | `PUT /domains/{domainID}/users/{userID}/storeAccess` |
| `client.users.revoke_store_access` | `DELETE /domains/{domainID}/users/{userID}/storeAccess/{username}` |

### Errors

All errors inherit from `GrommunioAdminApi::Error`:

- `ApiError` (has `status`, `body`, `server_message`) with subclasses
  `ValidationError` (400/422), `AuthenticationError` (401),
  `ForbiddenError` (403), `NotFoundError` (404), `ClientError` (any other
  non-2xx below 500, including 3xx — redirects are never followed),
  `ServerError` (5xx), `ServiceUnavailableError` (503, subclass of ServerError)
- `ConnectionError` — DNS, refused, reset, TLS, timeout
- `ParseError` — 2xx response body that is not valid JSON
- `ReadOnlyModeError`, `SyncOperationNotAllowedError` — mutation policy,
  raised before any socket access

Caller mistakes raise plain `ArgumentError` instead: an unsupported `mode`,
a `base_url` without scheme or host, an unusable request path, or an LDAP
query shorter than three non-whitespace characters.

### Pagination

`list` returns one `List` page (`Enumerable`, `#total_count`, `#raw`).
`all` accepts the same filters as the matching `list` and returns a lazy
enumerator that fetches pages of `page_size`
(default 50, matching the server-side default limit) on demand —
`all.first(5)` fetches one page. When the server reports a total, iteration
continues until that total is reached; a short page ends the run only when
no total is available, so a server that clamps the requested limit cannot
cause silent truncation. An empty page always ends the run.

### Immutable resources and raw access

Resources are frozen value objects hydrated once from the complete response
— attribute access never triggers HTTP and no field the server returned is
ever lost:

```ruby
user.status          # declared, typed reader
user["privArchive"]  # any raw upstream field, modeled or not
user.key?("forward") # distinguish "null" from "not in this response shape"
user.to_h            # the complete frozen payload
```

`User#status` stays the numeric upstream value; predicates `normal?`,
`suspended?`, `deleted?`, `shared_mailbox?`, `contact?`, and
`unknown_status?` cover the documented values (0/1/3/4/5) and keep future
values representable.

### Thread safety

The client is not thread-safe. Use one client per service object or job.

## Live tests

The default suite (`bundle exec rake`) is fully offline. Live verification
against a real Grommunio instance is opt-in via environment variables (see
`.env.example` — never commit real values):

```bash
# read-only verification
bundle exec rspec spec/live/v1_read_spec.rb

# controlled LDAP import + downsync for a dedicated persistent test account
GROMMUNIO_LIVE_SYNC=1 bundle exec rspec spec/live/v1_sync_spec.rb

# controlled shared-mailbox creation; leaves a real object behind, because
# this gem exposes no deletion - remove it in the admin web afterwards
GROMMUNIO_LIVE_MUTATE=1 GROMMUNIO_LIVE_SHARED_MAILBOX=info.test@example.test \
  bundle exec rspec spec/live/v1_write_spec.rb
```

Without the environment variables the live examples are skipped with a
clear reason.

## Development

```bash
bin/setup            # install dependencies
bundle exec rake     # offline suite: RSpec + RuboCop
```

## License

MIT — see [LICENSE.txt](LICENSE.txt).
