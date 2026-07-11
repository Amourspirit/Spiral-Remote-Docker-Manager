# Remote Docker Stack

Docker Compose stack for running Arcane Manager with an optional Cloudflare DNS route manager sidecar.

## What This Project Does

- Runs the official Arcane Manager container.
- Persists Arcane data, builds, and backups under local storage directories.
- Optionally manages one or more Cloudflare CNAME records for tunnel-based routing.

The stack is defined in [compose.yaml](compose.yaml) and includes two services:

- `arcane-manager` (profile: `arcane`)
- `arcane-route-manager` (profile: `cf-arcane`)

## Prerequisites

- Docker Engine with Compose v2 (`docker compose`)
- A `.env` file at the project root with required variables
- Cloudflare API token and zone details only if you use the `cf-arcane` profile

## Quick Start

1. Create a `.env` file in the project root.
2. Set the required Arcane environment variables.
3. Start Arcane Manager.

```bash
docker compose --profile arcane up -d
```

1. (Optional) Start route manager profile for Cloudflare record automation.

```bash
docker compose --profile arcane --profile cf-arcane up -d
```

1. Check health and logs.

```bash
docker compose ps
docker compose logs -f arcane-manager
docker compose logs -f arcane-route-manager
```

## Required Environment Variables

### Arcane Manager

These variables are required by `arcane-manager` in [compose.yaml](compose.yaml):

- `COMPOSE_PROJECT_NAME`
- `ARCANE_EXTERNAL_PORT`
- `ARCANE_PUID`
- `ARCANE_PGID`
- `ARCANE_ENCRYPTION_KEY`
- `ARCANE_JWT_SECRET`

Optional:

- `SERVER_TZ` (defaults to `None`)

### Cloudflare Route Manager (Optional)

These are required when using profile `cf-arcane`:

- `CF_API_TOKEN`
- `CF_RECORD_NAMES` (supports separators: comma, semicolon, space, newline)
- `CF_TUNNEL_CNAME` or `CF_TUNNEL_ID`
- `CF_ZONE_ID`
- `CF_CONNECT_TIMEOUT`
- `CF_TUNNEL_TOKEN`
- `CF_TUNNEL_ID` (required in compose; also used to derive `TUNNEL_CNAME` when needed)

Optional toggles:

- `CF_ROUTE_ENABLE_ON_START` (default `1`)
- `CF_ROUTE_DISABLE_ON_STOP` (default `1`)
- `CF_ALLOW_DELETE_MISMATCH` (currently passed through)
- `CF_MAX_TIME` (default `10`)
- `CF_RETRY_COUNT` (default `3`)

## Profiles and Service Behavior

### `arcane` profile

Starts only `arcane-manager`.

- Publishes `${ARCANE_EXTERNAL_PORT}` to container port `3552`.
- Mounts:
  - `./storage/arcane/data:/app/data`
  - `./storage/arcane/builds:/builds`
  - `./storage/arcane/backups:/backups`
  - `/var/run/docker.sock:/var/run/docker.sock:ro`
- Healthcheck command: `/app/arcane health`

### `cf-arcane` profile

Starts `arcane-route-manager` built from [src/Dockerfile](src/Dockerfile).

Key lifecycle behavior from [src/entrypoint.sh](src/entrypoint.sh):

- On start, enables route(s) when `ROUTE_ENABLE_ON_START` is truthy.
- On `SIGTERM`/`SIGINT` and container exit, disables route(s) when `ROUTE_DISABLE_ON_STOP` is truthy.

Route operations are implemented in [src/tunnel_route.sh](src/tunnel_route.sh):

- Validates and deduplicates DNS names from `RECORD_NAMES`.
- Creates missing proxied CNAME records to `TUNNEL_CNAME`.
- Performs atomic enable with rollback if a create operation fails.
- Deletes matching records on disable.

## Common Commands

Start Arcane only:

```bash
docker compose --profile arcane up -d
```

Start Arcane + Cloudflare routing:

```bash
docker compose --profile arcane --profile cf-arcane up -d
```

Stop stack:

```bash
docker compose down
```

Rebuild route manager image:

```bash
docker compose build arcane-route-manager
```

Inspect current route manager logs:

```bash
docker compose logs --tail=200 arcane-route-manager
```

## Project Layout

- [compose.yaml](compose.yaml): main stack definition
- [src/Dockerfile](src/Dockerfile): route manager image definition
- [src/entrypoint.sh](src/entrypoint.sh): startup/shutdown orchestration for route actions
- [src/tunnel_route.sh](src/tunnel_route.sh): Cloudflare DNS API logic
- [storage/arcane](storage/arcane): runtime data, backups, and build artifacts
- [tmp](tmp): local temporary compose artifacts

## Notes

- The route manager currently receives `CF_TUNNEL_TOKEN` from compose but does not use it directly in scripts.
- If `CF_TUNNEL_CNAME` is empty and `CF_TUNNEL_ID` is set, route target falls back to `${CF_TUNNEL_ID}.cfargotunnel.com`.
- `main.py` and [pyproject.toml](pyproject.toml) are lightweight placeholders and are not required to run the Docker stack.
