# Haskell Type-Safe API Contract Monitor

## Project Description
A web-based Haskell application that monitors API endpoints and validates their responses against user-defined contracts. It ensures API reliability by detecting contract drift, slow responses, unexpected statuses, and more.

## Features
- JSON contract validation (types, required/optional fields, strict matching)
- Uptime and latency monitoring
- HTTP checks targeting owned APIs
- Prevents internal probing via SSRF mitigation
- PostgreSQL backed

## Stack
- Haskell
- Servant & Lucid (Web Layer)
- Aeson (JSON parsing)
- PostgreSQL (Database)

## Folder Structure
- `app/`: Contains `Main.hs`
- `src/`: Core logic (Types, Server, Checking, DB)
- `test/`: Tests (Hspec + QuickCheck)
- `public/`: Assets (CSS, JS)
- `templates/`: HTML templates
- `scripts/`: Helper scripts for deployment and building
- `logs/`, `data/`: App logs and stored samples

## Environment Variables
The application uses a `.env` file for configuration. Do not commit `.env`. See `.env.example` or look at `.env` for placeholders.

## Security
This tool restricts monitoring of local or private IP addresses unless `ALLOW_PRIVATE_TARGETS` is set to true in `.env`.

## How to Build and Run
- Tests: `cabal test`
- Build: `cabal build`
- Run locally: `cabal run api-contract-monitor`

## Deployment
- Deployment is on a VPS with Systemd and Nginx.
- Target URL: https://haskell.micutu.com
- **Important**: The owner handles git commit and push manually.

## Database
Uses PostgreSQL. Update the `DATABASE_URL` in `.env` accordingly.

## Troubleshooting
- If port is occupied, the deployment script scans for an available port and updates `.env`.
- Database connection failure: check PostgreSQL is running.
- Nginx 502: The Haskell server might be down or binding to the wrong port.
