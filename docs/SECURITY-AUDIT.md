# Security audit

Reviewed 2026-11-05. Scope: tracked application, Git history filenames, local runtime configuration without disclosing secrets, systemd unit and this application's nginx virtual host. Passive inspection and isolated local regression tests; no intrusive scanning of other services. This is a scoped review, not certification or a claim of finding every vulnerability.

## Baseline findings

| Severity | Finding | Evidence / impact | Delivery status |
|---|---|---|---|
| High | DNS validation/connect race | `isSafeUrl` resolves separately from `http-client`; a second DNS answer can change the destination. Existing comment claiming rebinding protection is incorrect. | Pending |
| High | CSRF on all mutations | Basic credentials are browser-managed; create/update/delete accept cross-origin forms without checking origin or tokens. | Pending |
| High | Unbounded outbound work | No complete operation deadline; response read cap can over-read a chunk and never checks truncation. DNS/slow-stream/check load can consume resources. | Pending |
| Medium | Special-address gaps | IPv6 link-local test covers only part of /10; documentation/special IPv4 and transition IPv6 ranges accepted. | Pending |
| Medium | False passing checks | Invalid JSON becomes `Null`; 3xx may pass and failing HTTP responses can have no error details. | Pending |
| Medium | Unvalidated monitor definitions | Server accepts arbitrary methods, empty/oversized fields, invalid contract definitions and unsafe target URLs at write time. | Pending |
| Medium | Insecure configuration failure modes | Empty Basic credentials and silently defaulted malformed settings; config `Show` contains secrets. | Pending |
| Medium | Scheduler stops on DB errors | Endpoint fetch exception escapes the scheduler thread; all endpoints create waiting async threads; persistence/status updates are separate writes. | Pending |
| Medium | Unbounded history/query cost | No retention policy or history indexes; dashboard/health aggregate lifetime history. | Pending |
| Medium | Weak browser policy | Inline event handlers/styles and permissive proxy CSP; application itself sends no security headers/no-store. | Pending |
| Low | Environment backup not ignored | Untracked `.env.bak-*` could be accidentally staged. No secret `.env` filenames found in reviewed Git history. | Fixed: `f2d4d45` |
| Low | Build/deploy drift | README service name differs from `haskell-canary`; build toolchain absent on this VPS; legacy scripts hardcode a removed home path and build into running executable location. | Pending |

## Existing controls verified

- Application binds to 127.0.0.1:3060; Basic authentication is enabled and unauthenticated local requests receive 401.
- SQL values use parameterized queries; HTML text is escaped by Lucid.
- nginx denies dotfiles and restricts direct origin traffic; TLS/security headers exist at the proxy.
- systemd uses an unprivileged user, no capabilities, filesystem protection and a 384 MB memory limit.
- PostgreSQL backups have an existing systemd service/timer. Restore viability still needs a separate verified restore exercise.

## Remaining operational review

- Cloudflare ingress is not an explicit matching hostname entry in the inspected tunnel file. Confirm wildcard/DNS route ownership separately; do not infer protection from the domain alone.
- Application and nginx policies must work both through the active tunnel route and the direct local upstream.
- Preserve `.env` and backups with 0600 permissions. Never put credential values in audit output or commits.
- Basic authentication is a single-owner access model. Keep authentication required until account isolation and public-data policy are implemented.
- Do not log outbound request exception text containing URLs, credentials or response bodies.

## References

- [OWASP SSRF Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)
- [OWASP CSRF Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)
- [http-client Request and connection settings](https://hackage-content.haskell.org/package/http-client-0.7.19/docs/Network-HTTP-Client.html)
