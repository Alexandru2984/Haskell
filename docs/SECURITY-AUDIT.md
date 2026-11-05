# Security audit

Reviewed 2026-11-05. Scope: tracked application, selected secret patterns in Git history, local runtime configuration without disclosing secrets, systemd unit and this application's nginx virtual host. Passive inspection and isolated local regression tests; no intrusive scanning of other services. This is a scoped review, not certification or a claim of finding every vulnerability.

## Baseline findings

| Severity | Finding | Evidence / impact | Delivery status |
|---|---|---|---|
| High | DNS validation/connect race | `isSafeUrl` resolves separately from `http-client`; a second DNS answer can change the destination. Existing comment claiming rebinding protection is incorrect. | Implemented; verified in regression tests |
| High | CSRF on all mutations | Basic credentials are browser-managed; create/update/delete accept cross-origin forms without checking origin or tokens. | Implemented; verified in regression tests |
| High | Unbounded outbound work | No complete operation deadline; response read cap can over-read a chunk and never checks truncation. DNS/slow-stream/check load can consume resources. | Implemented; verified in regression tests |
| Medium | Special-address gaps | IPv6 link-local test covers only part of /10; documentation/special IPv4 and transition IPv6 ranges accepted. | Implemented; verified in regression tests |
| Medium | False passing checks | Invalid JSON becomes `Null`; 3xx may pass and failing HTTP responses can have no error details. | Implemented; verified in regression tests |
| Medium | Unvalidated monitor definitions | Server accepts arbitrary methods, empty/oversized fields, invalid contract definitions and unsafe target URLs at write time. | Implemented; verified in regression tests |
| Medium | Insecure configuration failure modes | Empty Basic credentials and silently defaulted malformed settings; config `Show` contains secrets. | Implemented; verified in regression tests |
| Medium | Scheduler stops on DB errors | Endpoint fetch exception escapes the scheduler thread; all endpoints create waiting async threads; persistence/status updates are separate writes. | Implemented; verified in regression tests |
| Medium | Unbounded history/query cost | No retention policy or history indexes; dashboard/health aggregate lifetime history. | Implemented; verified in regression tests |
| Medium | Weak browser policy | Inline event handlers/styles and permissive proxy CSP; application itself sends no security headers/no-store. | Implemented; verified in regression tests |
| Low | Environment backup not ignored | Untracked `.env.bak-*` could be accidentally staged. No secret `.env` filenames found in reviewed Git history. | Fixed: `f2d4d45` |
| Low | Build/deploy drift | README service name differs from `haskell-canary`; build toolchain absent on this VPS; legacy scripts hardcode a removed home path and build into running executable location. | Implemented; verified in regression tests |

## Dependency advisories confirmed

The original build plan matches published advisories for Warp 3.4.14 (HSEC-2026-0013), aeson 2.2.5.0 and text-iso8601 0.1.1.1 (HSEC-2026-0007), and scientific 0.3.8.1 (HSEC-2026-0011). The candidate uses patched versions: Warp 3.4.20, aeson 2.2.5.1, text-iso8601 0.1.1.2 and scientific 0.3.10.0. Dependency floors prevent resolving the affected direct dependencies again.

An automated comparison against 39 published Haskell advisories at database commit `9fa5787e33f5bb3d73f2a0db22b59fd10921d25f` found no unreviewed applicable matches in the candidate. The base `Numeric.readFloat` advisory remains a documented function-specific exception; application code does not use it. The old process package advisory is Windows-specific and does not apply to this Linux deployment. This scan covers published metadata, not unknown vulnerabilities or all possible transitive call paths.

Twenty historical commits (82 unique blobs) were checked for private-key markers, GitHub/AWS token formats and non-placeholder PostgreSQL URL passwords; no matches were found. This is not proof that every conceivable secret format was absent.

## Existing controls verified

- Application binds to 127.0.0.1:3060; Basic authentication is enabled and unauthenticated local requests receive 401.
- SQL values use parameterized queries; HTML text is escaped by Lucid.
- nginx denies dotfiles and restricts direct origin traffic; TLS/security headers exist at the proxy.
- systemd uses an unprivileged user, no capabilities, filesystem protection and a 384 MB memory limit.
- PostgreSQL backups have an existing systemd service/timer. A pre-release dump was restored successfully to an isolated database; the additive migration preserved all 35,312 check rows in that snapshot.

## Remaining operational review

- Cloudflare uses a catch-all route to local nginx; external HTTPS requests were confirmed to pass through Cloudflare and reach the authenticated app. The relevant nginx vhost remains subject to its existing origin restriction.
- Application and nginx policies must work both through the active tunnel route and the direct local upstream.
- Preserve `.env` and backups with 0600 permissions. Never put credential values in audit output or commits.
- Basic authentication is a single-owner access model. Keep authentication required until account isolation and public-data policy are implemented.
- Do not log outbound request exception text containing URLs, credentials or response bodies.

## References

- [OWASP SSRF Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)
- [OWASP CSRF Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)
- [http-client Request and connection settings](https://hackage-content.haskell.org/package/http-client-0.7.19/docs/Network-HTTP-Client.html)

## Application hardening verification

35 Hspec examples passed, including local HTTP fixtures for invalid JSON, redirect refusal, HTTP errors, exact/oversized bodies, total deadlines, HEAD checks, strict contract definitions, origin spoofing, configuration bounds, special IP ranges and existing validator property tests. HTTP/browser and production verification are recorded in the delivery report after those stages.

## Product/browser verification

The final candidate passed 35 Hspec examples, 50 isolated HTTP assertions and 37 browser assertions. Browser checks cover 320/375/768/1440 px, both themes, keyboard search, the playground, page overflow, browser errors and automated WCAG 2 AA checks on six views. Contrast and ARIA findings were corrected and the suite rerun successfully. Automated Chromium emulation does not establish compatibility with every physical device, Safari/Firefox, or complete manual accessibility compliance.

PostgreSQL retention is opt-in (`RETENTION_DAYS=0` by default). Migrations add a revision column and indexes; they do not delete existing rows. Runtime verification and the remaining publication/access decisions are recorded in the delivery report.
