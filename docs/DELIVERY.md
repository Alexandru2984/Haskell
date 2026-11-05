# Delivery — 2026-11-05

Haskell Pulse is running at https://haskell.micutu.com with the existing private authentication boundary and credentials.

## Implemented

- DNS-pinned outbound requests, special-IP filtering, read-only methods, redirect/proxy refusal, response/header limits, total deadlines, strict monitor/contract/configuration validation and origin checks for all writes.
- Patched Warp/aeson/scientific/text-iso8601 dependency versions, with a committed freeze file and published-advisory check.
- Shared bounded worker slots, recovering scheduler ticks, atomic persistence, in-flight configuration revisions, endpoint quotas, history indexes and opt-in retention.
- Responsive dashboard, 24h/7d/30d statistics, average/P95 latency, detail/history pages, check timeline and chart, manual checks, pause/resume, search/project/status filters, CSV export, JSON contract playground, examples, formatting, clipboard copy, themes, local timestamps, keyboard navigation and opt-in refresh.
- Isolated integration/browser checks, pinned least-privilege CI actions, Dependabot configuration, release packaging and rollback instructions.

## Verification

- Hspec: **35 examples, 0 failures**.
- HTTP integration: **50 assertions passed**, including CRUD, forged origins, invalid targets/definitions, body limits, manual cooldown and pause/resume during an in-flight check.
- Browser: **37 assertions passed**, including all six views at 320/375/768/1440 px, playground interaction, keyboard search, light/dark themes, no page overflow/errors and automated WCAG 2 AA checks. Found contrast/ARIA issues were corrected and the suite rerun.
- npm audit: zero known advisories for the six installed browser-tooling packages at verification time.
- Haskell advisory comparison: 179 unique packages, 39 published advisories at database revision `9fa5787e33f5bb3d73f2a0db22b59fd10921d25f`; no unreviewed applicable matches. The function-specific base exception is documented.
- Production: authenticated 200 responses for overview, monitors, incidents, playground, CSS, JS, health and metrics, both directly and through Cloudflare. Live playground validation passed; forged-origin validation requests returned 403. Anonymous requests still return 401.
- Production Chromium checks at 1440 and 375 px passed navigation, layout, same-origin script loading and playground interaction with no JavaScript/CSP console errors.
- nginx syntax validation passed before reload. The service is active with no automatic restarts after activation and approximately 18 MB memory use at verification time.

## Release and recovery

- Executable/assets revision: `c698721cde04`, packaged under `releases/c698721cde04` with checked SHA256 sums; `releases/current` selects it.
- Service: `haskell-canary.service`; only the release WorkingDirectory/ExecStart drop-in was added. Existing unprivileged execution, filesystem protections and memory limit remain in place.
- This site's nginx vhost now has request/write rate limits, 128 KiB bodies, consistent strict headers, no-store/no-transform and a dedicated robots response. Cloudflare's HTML injection was observed and eliminated by no-transform without relaxing CSP. See [Cloudflare's documented behaviour](https://developers.cloudflare.com/web-analytics/faq/).
- Backup directory: `/srv/backups/haskell-monitor/pulse-20261105`, restricted to root. Contains the database dump, previous executable, original vhost/unit and environment backup. No credentials were printed or committed.
- The pre-release dump was restored into a separate database; migrations preserved **1 monitor and 35,312 checks** in that snapshot. The old explicit-column query remains compatible with the additive schema. Production continued recording checks; no production history was deleted.
- The original executable remains untouched at its previous `dist-newstyle` path for rollback. [Recovery instructions](DEPLOYMENT.md) do not require overwriting current database contents.
- The temporary review/restore databases and unused preview credentials are removed after verification. Test screenshots/logs remain in ignored local `artifacts/`.

## Remaining boundaries and follow-ups

- The existing legacy sample monitor checks an authenticated URL and reports HTTP 401. Its definition and history were preserved; configure a suitable public API target or add authenticated-target support with encrypted secrets as a separate feature.
- Accounts, roles, public demos/status publication, notifications, regional probes and richer incident management remain on the [product roadmap](PLAN.md). The current app is a private single-owner product, not a multi-tenant service.
- IPv6-only targets are intentionally refused by the pinned IPv4 transport. HEAD checks availability only; GET checks both HTTP and JSON contracts.
- Existing consumers of legacy Prometheus metric names need to migrate to the documented windowed gauges.
- Cloudflare's managed robots feature prepends its own allow/content-signal rules externally. The origin emits disallow-all, while authentication and noindex headers remain effective; exclude this private hostname from managed robots in the Cloudflare zone if a single unambiguous crawler policy is desired.
- CI configuration and all commands were verified locally; a GitHub-hosted run requires pushing the commits. No upstream push was performed.
- Browser tests use Chromium emulation, not physical devices or a full manual accessibility/security certification. No claim is made that all possible vulnerabilities have been found.

All delivery commits use the repository owner's existing author/committer identity and contain no coauthor/contributor attribution.
