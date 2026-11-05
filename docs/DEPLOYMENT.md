# Release and rollback

Scope is only haskell.micutu.com. The existing systemd hardening and environment file remain in place. Shared nginx/tunnel policies and other sites must not be edited for this release.

1. Run Hspec, the isolated HTTP/browser harness and dependency audits. Commit reviewed changes.
2. Run `scripts/build_release.sh`; it builds outside `dist-newstyle` and packages the executable and public assets under `releases/<commit>/`, with revision/checksums. It does not activate the release.
3. Back up PostgreSQL, the current nginx virtual host, any existing service drop-in and the active executable. Keep secrets/backups outside Git with restricted permissions. Verify the database dump with `pg_restore --list`; restore into a separate database to verify migrations and rollback compatibility.
4. Install `deploy/haskell-rate-limit.conf` in `/etc/nginx/conf.d/` and `deploy/haskell.nginx.conf` as this site's vhost. Test with `nginx -t` before reloading. It uses the existing trusted real-IP policy. The dedicated robots file disallows crawling the private product.
5. Atomically point `releases/current` at the verified candidate, install the `deploy/release.conf` systemd drop-in, then `systemctl daemon-reload` and restart `haskell-canary.service`. Run local and external authenticated GET checks and verify strict headers, assets and database state. Do not put credentials in shell arguments or logs.
6. Reload nginx only after configuration validation. Verify the external Cloudflare route separately. Record the release revision, test results and backup paths in the delivery report.

## Rollback

When a previous packaged release exists, repoint `releases/current` to it and restart the service. For this first packaged release, remove only the new `release.conf` drop-in and restart; the original unit still points at the untouched executable in `dist-newstyle`. Restore only this site's saved nginx vhost; remove the newly added rate-limit file if restoring the old vhost, then `nginx -t` and reload.

The database migration adds an endpoint revision column and history indexes. The old executable selects explicit original columns and can run against this additive schema. Rolling back the executable does not require deleting history, dropping tables or restoring a database over current data. Restore the backup into a separate database first if a database recovery is necessary.

## Operational follow-ups

- Rehearse restoring the existing scheduled backups regularly; a successful dump alone is insufficient evidence.
- Set alerts for service health, scheduler freshness, disk usage, PostgreSQL growth and backup age.
- Keep the private dashboard authenticated. A public status page needs an explicit publication policy.
- Review `RETENTION_DAYS` with the owner before enabling pruning. It is disabled by default.
- Haskell dependency floors and the freeze file pin the verified build; update them together and rerun the advisory comparison. Review the documented base-function exception when parsers change.
