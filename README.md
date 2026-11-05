# Haskell Pulse

A private API monitoring workspace built with Haskell, Servant, Lucid and PostgreSQL.
Track availability, response latency and JSON contract drift without a frontend build chain.

Deployment: https://haskell.micutu.com (authentication required).

## Product features

- Responsive overview, monitor list, detail pages, failed-check feed and contract playground.
- 24-hour, 7-day and 30-day availability, average latency and P95 statistics.
- Recent-check response-time charts, availability timeline and expandable validation errors.
- Create/edit/delete monitors, pause/resume, and run an immediate check.
- Project/status filters, instant search and `/` keyboard shortcut; Escape clears search.
- Light/dark themes, keyboard navigation, reduced-motion support, local timestamps and opt-in refresh.
- Contract playground with health, collection and breaking-change examples. Inputs are not stored and cause no network requests.
- Safe CSV history downloads (up to 1,000 checks in the selected period).
- Nested JSON types, required/optional fields, arrays, extra-field policy, enums, nullable values, numeric bounds and string-length bounds.
- Bounded scheduler workers, atomic result persistence and configuration revisions that discard obsolete in-flight results.
- Indexed history, optional retention and a race-safe endpoint quota.

Availability is the percentage of successful **checks**, not a duration-based SLA. Charts show up to 60 recent checks; detail tables show 100. An incident row represents a failed check; incident grouping/acknowledgement is on the [roadmap](docs/PLAN.md).

## Setup

Requirements: GHC **9.4.7**, Cabal **3.16.1.0**, PostgreSQL, `libpq-dev`, `libgmp-dev`, a C toolchain and a linker. The committed freeze file pins the verified dependencies. On systems without GNU gold, configure the GHC hsc2hs wrapper to use the installed bfd linker instead.

```sh
cp .env.example .env
chmod 600 .env
# Set DATABASE_URL, APP_USERNAME and a unique APP_PASSWORD (16+ characters).
# For local browsing, set APP_ORIGIN to the exact local URL, without a trailing slash.
cabal update
cabal build all --enable-tests --builddir=dist-review -j4
cabal test all --builddir=dist-review --test-show-details=direct
cabal run exe:api-contract-monitor --builddir=dist-review
```

Environment variables can be supplied by systemd or a local `.env`; a file is not required. Malformed configuration fails at startup. Production requires authentication and refuses private targets. To run isolated local fixtures, explicitly set `APP_ENV=development` and then opt into `ALLOW_PRIVATE_TARGETS=true`.

`RETENTION_DAYS=0` preserves all history. Setting 1..365 opts into automatic pruning; take a backup and choose the policy deliberately. Existing history is not purged by default. `MAX_ENDPOINTS` defaults to 200. The server does not insert a sample monitor at startup.

## Security model

This is a **single-owner private application**. Basic authentication protects pages, JSON APIs, metrics and assets. It has no public registration, workspace isolation or scoped API tokens. Do not make arbitrary public submissions available before adding account ownership and quotas per tenant.

- Writes require a trusted Origin or exact-origin Referer; cross-site Fetch Metadata is refused. `APP_ORIGIN` must match the URL used in the browser. Non-browser mutation clients must send this header too.
- Only GET and HEAD monitor methods are supported. HEAD checks 2xx HTTP availability; GET also requires valid JSON matching the contract.
- URLs reject credentials, fragments and ambiguous syntax. All DNS answers are checked against private/special address ranges. Connections are pinned to a validated IPv4 address while preserving hostname/SNI/certificate verification. IPv6-only targets are refused.
- Redirects and outbound environment proxies are disabled. Checks have a total deadline, a byte limit, header limits and bounded concurrency. Network exceptions are stored as generic messages without leaking URL credentials.
- Request bodies are limited to 128 KiB; contracts to 32 KiB; manual checks have a 5-second global cooldown. nginx adds per-client request/write limits.
- HTML is escaped, SQL values are parameterized and CSV cells are quoted/formula-protected. Browser policies disallow inline/external scripts, frames and unsafe form targets. Private responses use `no-store` and `noindex`.

See the [scoped security audit](docs/SECURITY-AUDIT.md), [published-advisory exception](docs/security-exceptions.json) and [delivery plan](docs/PLAN.md). These controls do not establish that the app has no remaining vulnerabilities.

## Validation and CI

Hspec covers checker behaviour, contract validation, URL safety, origin checks and configuration bounds. The integration harness creates temporary app processes and requires a database with `_test` or `_review` in its name; it refuses port 3060. It tests CRUD, SSRF inputs, forged writes, exports, cooldowns and an in-flight pause/resume race.

```sh
npm ci --ignore-scripts
npx playwright install chromium
TEST_DATABASE_URL='postgresql://USER:PASSWORD@127.0.0.1:5432/monitor_test' \
RUN_BROWSER_TESTS=1 python3 scripts/test_instance.py \
  "$(cabal list-bin exe:api-contract-monitor --builddir=dist-review)"
```

Browser checks cover 320/375/768/1440 px layouts, keyboard search, contract examples, both themes and automated WCAG 2 AA accessibility checks. This is browser emulation, not testing on physical mobile devices or a full manual accessibility audit. Screenshots and server output go to ignored `artifacts/`.

CI uses a separate PostgreSQL service, pinned action commits, read-only repository permissions, dependency audits, Hspec, HTTP and browser checks. It never deploys production. Dependabot checks browser tooling and actions weekly. For a manual Haskell advisory check:

```sh
git clone --depth 1 https://github.com/haskell/security-advisories.git /tmp/haskell-advisories
python3 scripts/audit_dependencies.py dist-review/cache/plan.json /tmp/haskell-advisories
```

Private application pages deliberately have noindex metadata and a disallow-all robots policy. A public marketing/demo and indexable status page require a separately approved public-data model; private monitoring data is not an SEO acquisition surface.

## Routes

| Method | Path | Purpose |
|---|---|---|
| GET | `/`, `/endpoints`, `/incidents` | Overview, monitors, failed checks |
| GET | `/endpoints/new`, `/endpoints/:id/edit` | Monitor forms |
| GET | `/endpoints/:id?hours=24` | Detail/history; also accepts 168 or 720 |
| POST | `/endpoints/create`, `/endpoints/:id/update` | Create/update |
| POST | `/endpoints/:id/delete`, `/endpoints/:id/toggle` | Delete or pause/resume |
| POST | `/endpoints/:id/check` | Immediate check |
| GET | `/endpoints/:id/export.csv?hours=24` | CSV download |
| GET | `/playground` | Interactive contract examples |
| POST | `/api/validate` | Validate `{contract, response}` JSON |
| GET | `/api/endpoints` | Private monitor definitions |
| GET | `/health`, `/metrics` | Database health / Prometheus metrics |

Windowed Prometheus values use explicit `_24h` names and gauges; P95 is exposed separately. Consumers of the old lifetime-style metric names must migrate. `/health` reports database-backed status and check count for the last 24 hours.

## Deployment

The production service is **`haskell-canary.service`**, behind the site's nginx virtual host and Cloudflare. The app binds to 127.0.0.1:3060. [Deployment and rollback](docs/DEPLOYMENT.md) document release directories, backups and the service drop-in. `scripts/build_release.sh` builds a separate candidate; it does not restart production. `scripts/choose_port.sh` only reports a free development port and never rewrites `.env`.

Git pushes are a separate operator action. Environment files, backups, local builds, releases and test artifacts are ignored.
