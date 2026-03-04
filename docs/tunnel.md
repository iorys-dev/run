# Cloudflare Tunnel Integration

Expose any local iorys dev service publicly over HTTPS via a zero-config
Cloudflare Tunnel — no port forwarding, no self-signed certs.

Subdomain pattern: `{name}-{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev`
where `{name}` is the value of `cf_expose_name` / `cf_expose_N_name`
or the Docker service name when no explicit name is set.
Use the special value `@empty` to omit the prefix entirely: `{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev`.

---

## How it works

```
docker-compose service
        │
        │  label: cf_expose=true
        ▼
  tunnel-up.sh                     Cloudflare API
  ─────────────                    ───────────────
  1. reads labels from             create named tunnel
     docker compose config         configure ingress rules
  2. creates / reuses tunnel  ───► create CNAME per hostname
  3. writes token + DNS IDs        serve via *.iorys.dev SSL
     to .env
        │
        ▼
  cloudflared container
  tunnels HTTP to each service
```

---

## Prerequisites

| What | Details |
|------|---------|
| Cloudflare API token | [dash.cloudflare.com](https://dash.cloudflare.com) → My Profile → API Tokens → **Create Token**. Needs `Account > Cloudflare Tunnel > Edit` and `Zone > DNS > Edit`. |
| Cloudflare Account ID | Right sidebar on any zone page. |
| `iorys/run ≥ 1.1.0` | `composer require --dev iorys/run` |
| `jq`, `curl`, `openssl`, `docker` | Must be on the host running tunnel scripts. |

---

## Quick start

### 1. Set credentials in `.env`

Copy the bundled example and fill in the two required values:

```bash
cp vendor/iorys/run/.env.example .env   # or merge into your existing .env
```

```bash
# ── Required ──────────────────────────────────────────────────────────────────
CF_API_TOKEN=your_token_here     # Account > Tunnel > Edit  +  Zone > DNS > Edit
CF_ACCOUNT_ID=your_account_id_here

# ── Optional ─────────────────────────────────────────────────────────────────
APP_PROJECT=my-project           # project slug — used in subdomain (default: dir name)
APP_NAMESPACE=                   # developer id — auto-generated if left empty

# ── Written automatically by ./run tunnel up — leave empty ───────────────────
CLOUDFLARE_TUNNEL_ID=
CLOUDFLARE_TUNNEL_TOKEN=
CLOUDFLARE_DNS_RECORD_NGINX=
```

### 2. Add expose labels to services

In `docker-compose.yml`, mark every service that should be publicly accessible.

#### Simple form — one hostname per service

```yaml
services:
  nginx:
    image: nginx:1.27-alpine
    labels:
      cf_expose: "true"        # required — marks this service for exposure
      cf_expose_name: "app"    # optional — hostname prefix; defaults to service name
      cf_expose_port: "80"     # optional — defaults to PORT env var, then 80
```

`nginx` with `cf_expose_name: "app"` → `app-{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev`

#### Indexed form — multiple hostnames from one service

Use `cf_expose_N_name` + `cf_expose_N_port` (starting at 0) when a single
container serves traffic on more than one port:

```yaml
services:
  nginx:
    image: nginx:1.27-alpine
    labels:
      cf_expose_0_name: "hub"      # → hub-{project}-{ns}.iorys.dev   → :80
      cf_expose_0_port: "80"
      cf_expose_1_name: "hub-api"  # → hub-api-{project}-{ns}.iorys.dev → :81
      cf_expose_1_port: "81"
```

The two forms cannot be mixed on the same service — if any `cf_expose_N_name`
label is present the indexed form takes precedence.

### 3. Add a `cloudflared` service to docker-compose

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel run
    environment:
      TUNNEL_TOKEN: ${CLOUDFLARE_TUNNEL_TOKEN:-}
    depends_on:
      - nginx   # list your cf_expose services here
```

### 4. Wire `tunnel_functions.sh` into your run script

```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

[[ -f .env ]] && { set -a; source .env; set +a; }

DC="docker compose"
IORYS_RUN_DIR="$PWD"

source vendor/iorys/run/bin/tunnel_functions.sh

# Call ensureTunnel in your up/install commands:
up() {
    ensureTunnel
    $DC up -d --remove-orphans
}

case "${1:-}" in
    up)      up ;;
    tunnel)  tunnel "${2:-status}" ;;
    # ...
esac
```

---

## Label reference

### Simple form

| Label | Required | Default | Description |
|-------|----------|---------|-------------|
| `cf_expose` | yes | — | Set to `"true"` to expose the service. |
| `cf_expose_name` | no | service name | Hostname prefix: `{name}-{project}-{ns}.iorys.dev`. Use `@empty` to omit the prefix: `{project}-{ns}.iorys.dev` (saves as `CLOUDFLARE_DNS_RECORD_ROOT`). |
| `cf_expose_port` | no | `PORT` env var, then `80` | Container port to forward to. |

### Indexed form (multiple exposes per service)

| Label | Required | Description |
|-------|----------|-------------|
| `cf_expose_N_name` | yes | Hostname prefix for expose slot N (N = 0, 1, 2, …). Use `@empty` to omit the prefix: `{project}-{ns}.iorys.dev` (saves as `CLOUDFLARE_DNS_RECORD_ROOT`). |
| `cf_expose_N_port` | no (default `80`) | Container port for slot N. |

If any `cf_expose_N_name` label exists on a service the indexed form is used
and `cf_expose: "true"` is ignored for that service.

---

## Environment variables

### Input (set these in `.env` before running `./run tunnel up`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CF_API_TOKEN` | yes | — | Cloudflare API token with **Account > Tunnel > Edit** and **Zone > DNS > Edit** permissions. |
| `CF_ACCOUNT_ID` | yes | — | Cloudflare account ID (right sidebar on any zone page). |
| `APP_PROJECT` | no | directory name | Project slug used in subdomain. |
| `APP_NAMESPACE` | no | auto-generated | Developer identifier (e.g. your initials). Auto-generated 7-char string if empty. |

See [`.env.example`](../.env.example) for a ready-to-copy template with inline comments.

### Output (written to `.env` by `tunnel-up.sh`)

| Variable | Description |
|----------|-------------|
| `APP_NAMESPACE` | The namespace that was used (persisted so subsequent runs reuse it). |
| `APP_PROJECT` | The project slug (persisted). |
| `CLOUDFLARE_TUNNEL_ID` | UUID of the created tunnel. |
| `CLOUDFLARE_TUNNEL_TOKEN` | Token passed to the `cloudflared` container. |
| `CLOUDFLARE_DNS_RECORD_{NAME}` | Cloudflare DNS record ID per exposed name (upper-cased, hyphens → underscores). Used by `tunnel-down.sh` for cleanup. |

---

## `./run tunnel` commands

| Command | Description |
|---------|-------------|
| `./run tunnel up` | Create the tunnel, ingress rules, and DNS records. Writes token + IDs to `.env`. |
| `./run tunnel down` | Delete DNS records, delete the tunnel. Cleans `.env`. |
| `./run tunnel recreate` | `down` + `up` + restart `cloudflared` container. |
| `./run tunnel status` | Show current tunnel ID and `cloudflared` container state. |

---

## Helper functions

### `ensureTunnel`

Silently no-ops if the tunnel is already configured (`CLOUDFLARE_TUNNEL_TOKEN`
is present) or if `CF_API_TOKEN` / `CF_ACCOUNT_ID` are not set. Otherwise runs
`tunnel up` automatically.

Call it at the top of your `up` and `install` commands so developers can
bring up the full stack with a single `./run up`.

```bash
up() {
    ensureTunnel
    $DC up -d --remove-orphans
}
```

### `resolveTunnelDomain`

Returns `{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev` when a tunnel is active,
empty string otherwise. Useful for printing URLs or seeding env vars.

```bash
domain=$(resolveTunnelDomain)
[[ -n "$domain" ]] && echo "App is at: https://nginx-${domain}"
```

---

## File locations

```
vendor/iorys/run/
  bin/
    tunnel-up.sh          # creates tunnel, ingress, DNS — called by tunnel_functions.sh
    tunnel-down.sh        # deletes DNS records + tunnel, cleans .env
    tunnel_functions.sh   # tunnel(), ensureTunnel(), resolveTunnelDomain()
  docs/
    overview.md           # package overview and module reference
    tunnel.md             # this file
```

---

## Adding a new service

**Single hostname per service:**

```yaml
services:
  my-api:
    image: my-image
    labels:
      cf_expose: "true"
      cf_expose_name: "api"   # → api-{project}-{ns}.iorys.dev
      cf_expose_port: "3000"
```

**Multiple hostnames from one service:**

```yaml
services:
  nginx:
    image: nginx:alpine
    labels:
      cf_expose_0_name: "web"   # → web-{project}-{ns}.iorys.dev  → :80
      cf_expose_0_port: "80"
      cf_expose_1_name: "api"   # → api-{project}-{ns}.iorys.dev  → :81
      cf_expose_1_port: "81"
```

Then recreate the tunnel to pick up the new ingress rule and DNS record:

```bash
./run tunnel recreate
```

---

## Troubleshooting

**"No services with label `cf_expose=true` found"**
`docker compose config` could not parse the compose file, or no service has
the label set to exactly `"true"`. Run `docker compose config --format json | jq '.services | keys'`
to verify.

**"Failed to parse docker-compose.yml — is Docker running?"**
The script calls `docker compose config` to read labels. Docker must be
running on the host even if you only want to provision the tunnel.

**"Could not find zone ID"**
Check that `CF_API_TOKEN` has `Zone > DNS > Edit` permission for the `iorys.dev` zone.

**Tunnel exists but `cloudflared` keeps disconnecting**
The token in `.env` is stale. Run `./run tunnel recreate` to delete and
re-create the tunnel with a fresh token.

**DNS record already exists warning**
Harmless — the script updates the existing CNAME to point to the current
tunnel ID and proceeds normally.
