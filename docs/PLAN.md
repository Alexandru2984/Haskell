# Product and security plan

Baseline: 2026-11-05. Existing product: Haskell / Servant / Lucid / PostgreSQL API contract monitor. Preserve the existing private dashboard and HTTP Basic authentication boundary. Use the repository owner's existing Git identity for every stage; no generated contributor/coauthor attribution.

## Delivery order

1. **Repository hygiene** — ignore local environment variants and backups, retain the template. Completed in `f2d4d45`.
2. **Security and checker correctness** — bind outbound connections to validated DNS addresses; block special IP ranges, credentials and ambiguous URLs; disable proxies and redirects; enforce end-to-end deadlines and exact response-size limits; distinguish invalid JSON, unexpected HTTP statuses and contract failures; validate configuration and forms; require trusted origins for writes; add security headers and request limits. Add regression tests before calling these fixed.
3. **Operational reliability and product data** — recover scheduler ticks, bounded workers, atomic persistence, indexed history, configurable retention, pause/resume, manual checks with cooldown/concurrency controls, per-endpoint history, 24-hour/7-day/30-day metrics and latency percentiles. Isolate integration tests from production data.
4. **Responsive product experience** — navigation and layouts for phones/tablets/desktops; useful empty/error states; search/project/status filters; endpoint detail pages, uptime history and latency charts; contract playground with editable examples; safe CSV exports; keyboard accessibility, reduced motion, theme preference and opt-in refresh. No frontend build chain or third-party asset dependencies needed.
5. **Documentation, CI and indexing** — accurate setup/release/rollback instructions; reproducible build configuration, least-privilege CI, regression and browser checks; metadata and sensible indexing rules for an authenticated product. Do not expose private monitoring data for SEO.

Each coherent, verified stage gets a separate commit. Changes to the running service require a backup and a verified candidate. Do not push upstream or change other hosted projects.

## Product roadmap after this delivery

- Public marketing/demo with synthetic data and a separately authorized public status page.
- Accounts, workspaces, roles and per-project ownership before accepting public endpoint submissions.
- Incident lifecycle (open/acknowledged/resolved), maintenance windows and SLO/error budgets.
- Opt-in email/webhook notifications with secret storage, verified destinations, retries and outbound SSRF protection.
- Request bodies/custom headers with encrypted secrets and redaction, never in public exports.
- Import/export of complete monitor definitions with quotas and preview, versioned contracts and drift diffs.
- Per-monitor intervals, regional probes, certificate-expiry checks and distributed workers.
- Scheduled reports, signed status badges, API tokens with scopes, audit trail and team invitations.

These require product/access decisions and supporting infrastructure; listing them is not a claim that they are implemented.
