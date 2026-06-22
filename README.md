# Haskell Type-Safe API Contract Monitor

A web application that periodically checks API endpoints and validates their
JSON responses against user-defined contracts. It records uptime, latency and
contract drift, and surfaces failures as incidents.

Live: https://haskell.micutu.com

## Features
- JSON contract validation (types, required/optional fields, strict-extra mode,
  arrays, nested objects, strict integer checks)
- Background scheduler that checks all enabled endpoints on an interval,
  concurrently (bounded), and persists every result
- Uptime % and average latency on the dashboard
- Incident feed built from failed checks
- Add / edit / delete endpoints from the web UI
- SSRF mitigation: DNS resolution + IP-range validation (loopback, private,
  CGNAT, link-local/metadata, IPv6 ULA & mapped v4), no redirect following,
  response-size cap and per-request timeout
- Optional HTTP Basic auth over the whole app
- `/health` (JSON) and `/metrics` (Prometheus) endpoints
- PostgreSQL backed, connection-pooled

## Stack
- Haskell (GHC 9.4.7)
- Servant + Lucid (web layer)
- Aeson (JSON), postgresql-simple + resource-pool (DB)
- http-client (checks), warp (server)

## Routes
| Method | Path                        | Purpose                       |
|--------|-----------------------------|-------------------------------|
| GET    | `/`                         | Dashboard                     |
| GET    | `/endpoints`                | List endpoints                |
| GET    | `/endpoints/new`            | Add-endpoint form             |
| POST   | `/endpoints/create`         | Create endpoint               |
| GET    | `/endpoints/:id/edit`       | Edit-endpoint form            |
| POST   | `/endpoints/:id/update`     | Update endpoint               |
| POST   | `/endpoints/:id/delete`     | Delete endpoint               |
| GET    | `/incidents`                | Recent failed checks          |
| GET    | `/health`                   | Health JSON                   |
| GET    | `/metrics`                  | Prometheus metrics            |
| GET    | `/api/endpoints`            | Endpoints as JSON             |

## Configuration
Copy `.env.example` to `.env` and fill it in. Do **not** commit `.env`.
Every variable in `.env.example` is read at startup (host/port, DB URL,
checker timeout & size cap, scheduler interval & concurrency, and optional
basic-auth credentials).

## Build & Run
```sh
cabal build        # compile
cabal test         # run the test suite
cabal run api-contract-monitor
```

## Deployment
Runs on a VPS under systemd, behind nginx (TLS via Certbot) and Cloudflare.
The app binds to `APP_HOST` (default `127.0.0.1`) so only nginx can reach it.

- Service: `systemctl restart haskell-api-monitor`
- Target URL: https://haskell.micutu.com
- The owner handles `git push` and the production restart manually.

## Security notes
- Set `ALLOW_PRIVATE_TARGETS=true` only for local testing — it disables the
  SSRF IP checks.
- Enable `APP_BASIC_AUTH_ENABLED` (with credentials) to require login. When
  enabled it also covers `/metrics`, so configure your scraper accordingly.

## Troubleshooting
- **502 from nginx**: the app is down or bound to the wrong port — check
  `APP_HOST`/`APP_PORT` and `systemctl status haskell-api-monitor`.
- **DB connection failure**: verify PostgreSQL is up and `DATABASE_URL` is set.
