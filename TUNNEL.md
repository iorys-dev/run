# Cloudflare Tunnel Integration Guide

Add public HTTPS/TCP access to any iorys project's local dev environment via
Cloudflare Tunnel — no port forwarding, no self-signed certs.

Subdomain format: `{service}-{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev`
Covered by the `*.iorys.dev` Universal SSL certificate (no extra setup).

---

## Prerequisites

| What | Where to get |
|------|-------------|
| Cloudflare API token | dash.cloudflare.com → My Profile → API Tokens → **Create Token** — needs `Account > Cloudflare Tunnel > Edit` + `Zone > DNS > Edit` |
| Cloudflare Account ID | dash.cloudflare.com → any zone → right sidebar |
| `iorys/run >= 1.0.24` | installed via composer |
| `jq`, `curl`, `openssl` | available on the host running the tunnel scripts |

---

## Quick start for existing iorys projects

### 1. Require iorys/run

```bash
# Laravel / PHP projects
composer require --dev iorys/run

# Node / other projects (add to composer.json, then:)
docker run --rm -v "$PWD":/app -w /app composer:2 install --no-interaction
```

Add repman repository to `composer.json` if not already present:

```json
{
    "repositories": [
        {
            "type": "composer",
            "url": "https://iorys-dev.repo.repman.io"
        }
    ],
    "require-dev": {
        "iorys/run": "^1.0.24"
    }
}
```

### 2. Add devops scripts

Copy or adapt from an existing iorys project. Minimum required files:

```
devops/local/scripts/tunnel-up.sh    # creates tunnel + DNS records + writes .env
devops/local/scripts/tunnel-down.sh  # destroys tunnel + DNS records + cleans .env
```

Make them executable:

```bash
chmod +x devops/local/scripts/tunnel-up.sh devops/local/scripts/tunnel-down.sh
```

The scripts expect these env vars (set in `.env`):

```bash
CF_API_TOKEN=        # Cloudflare API token
CF_ACCOUNT_ID=       # Cloudflare account ID
APP_PROJECT=myapp    # project slug — used in subdomain
APP_NAMESPACE=       # auto-generated on first tunnel up
```

They write back to `.env`:

```bash
APP_NAMESPACE=abc1234
CLOUDFLARE_TUNNEL_ID=<uuid>
CLOUDFLARE_TUNNEL_TOKEN=eyJ...
CLOUDFLARE_DNS_RECORD_APP=<dns-record-id>
# ...any additional DNS record IDs your project defines
```

### 3. Add a cloudflared service to docker-compose

```yaml
# devops/local/compose/cloudflared.yml  (or inline in docker-compose.yml)
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel run
    environment:
      TUNNEL_TOKEN: ${CLOUDFLARE_TUNNEL_TOKEN:-}
    networks:
      - default
```

### 4. Update your `run` script

Set `IORYS_RUN_DIR` and source `tunnel_functions.sh` **after** `DC` is set:

```bash
#!/usr/bin/env bash
# ... your existing run script preamble ...

DC="docker compose"   # or however you detect it

IORYS_RUN_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "vendor/iorys/run/bin/tunnel_functions.sh" ]]; then
    source "vendor/iorys/run/bin/tunnel_functions.sh"
fi
```

This gives you three functions:

| Function | Purpose |
|----------|---------|
| `tunnel [up\|down\|recreate\|status]` | Full tunnel lifecycle management |
| `ensureTunnel` | Call in `up`/`install` — auto-creates tunnel if credentials are set |
| `resolveTunnelDomain` | Returns `{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev` |

Wire them into your dispatcher and `up`/`install` commands:

```bash
up() {
    ensureTunnel          # auto-provisions if not yet configured
    docker compose up -d
}

# If using the iorys/run addCommand framework — tunnel is registered automatically.
# If using a custom case dispatcher, add:
case "$1" in
    tunnel)  shift; tunnel "$@" ;;
    # ...
esac
```

### 5. Add .env.example entries

```bash
CF_ACCOUNT_ID=
CF_API_TOKEN=
APP_PROJECT=myapp
APP_NAMESPACE=                    # auto-generated on first ./run tunnel up

CLOUDFLARE_TUNNEL_ID=
CLOUDFLARE_TUNNEL_TOKEN=
CLOUDFLARE_DNS_RECORD_APP=
# CLOUDFLARE_DNS_RECORD_<SERVICE>=  # one per extra DNS record in tunnel-up.sh
```

### 6. First-time setup

```bash
cp .env.example .env
# fill in CF_ACCOUNT_ID and CF_API_TOKEN

./run tunnel up     # creates tunnel + DNS + writes CLOUDFLARE_TUNNEL_* to .env
./run up            # starts all services including cloudflared
```

---

## Customising tunnel-up.sh for your services

`tunnel-up.sh` owns the ingress rules. Add one entry per service you want to expose.

```bash
# HTTP service (nginx, node dev server, etc.)
{"hostname": "app-${SUFFIX}", "service": "http://nginx:80", "originRequest": {}}

# TCP service (requires cloudflared access on the client side)
{"hostname": "postgres-${SUFFIX}", "service": "tcp://postgres:5432", "originRequest": {}}
```

Create a DNS record for each hostname and save the record ID to `.env`:

```bash
DNS_ID_APP=$(create_or_update_dns "${HOST_APP}")
update_env "CLOUDFLARE_DNS_RECORD_APP" "$DNS_ID_APP"
```

Mirror the cleanup in `tunnel-down.sh`:

```bash
DNS_IDS=("${CLOUDFLARE_DNS_RECORD_APP:-}" "${CLOUDFLARE_DNS_RECORD_<SERVICE>:-}")
# loop deletes each + calls remove_env
```

---

## Accessing TCP services (postgres, redis)

TCP hostnames require `cloudflared` on the developer's machine:

```bash
# Install cloudflared: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/

cloudflared access tcp --hostname postgres-myapp-abc1234.iorys.dev --url localhost:15432
# Then connect your DB client to localhost:15432
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ERR_SSL_VERSION_OR_CIPHER_MISMATCH` | Using multi-level subdomain (e.g. `app.myapp.ns.iorys.dev`) | Use flat format: `app-myapp-ns.iorys.dev` |
| Tunnel shows as healthy but browser gets old content | DNS not propagated yet or browser cache | Hard refresh / wait 30s |
| `tunnel recreate` picks up old token | Stale env vars in shell after `down` | The `tunnel down` handler in `tunnel_functions.sh` unsets all `CLOUDFLARE_*` vars automatically |
| `CF_API_TOKEN` permission error on Total TLS | Total TLS doesn't work for API token auth + tunnel hostnames | No action needed — `*.iorys.dev` Universal SSL covers all flat subdomains |
