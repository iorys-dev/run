#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# tunnel-up.sh — Shared Cloudflare Tunnel provisioner for all iorys projects
#
# Called by tunnel_functions.sh with IORYS_RUN_DIR pointing at the project root.
# Service discovery is label-driven — add to any docker-compose service:
#
#   labels:
#     cf_expose: "true"           # expose this service through the tunnel
#     cf_expose_port: "8080"      # port cloudflared forwards to (falls back to PORT env, then 80)
#
# Hostname: {service_name}-{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev
#
# Saves to .env:
#   APP_NAMESPACE, APP_PROJECT, CLOUDFLARE_TUNNEL_ID, CLOUDFLARE_TUNNEL_TOKEN
#   CLOUDFLARE_DNS_RECORD_{SERVICE_UPPER}   — one per exposed service
#
# Requires in .env:
#   CF_API_TOKEN   — Cloudflare API token (Account:Tunnel:Edit + Zone:DNS:Edit)
#   CF_ACCOUNT_ID  — Cloudflare account ID
#   APP_PROJECT    — project slug (default: derived from dir name)
#   APP_NAMESPACE  — developer id; auto-generated if empty
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_ROOT="${IORYS_RUN_DIR:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
ENV_FILE="${PROJECT_ROOT}/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}→  ${1}${NC}"; }
success() { echo -e "${GREEN}✓  ${1}${NC}"; }
warn()    { echo -e "${YELLOW}⚠  ${1}${NC}"; }
fail()    { echo -e "${RED}✗  ${1}${NC}"; exit 1; }

[[ -f "$ENV_FILE" ]] || fail ".env not found at $ENV_FILE"
set -a; source "$ENV_FILE"; set +a

for cmd in curl jq openssl docker; do
    command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' is required but not installed."
done

[[ -n "${CF_API_TOKEN:-}" ]]  || fail "CF_API_TOKEN must be set in .env"
[[ -n "${CF_ACCOUNT_ID:-}" ]] || fail "CF_ACCOUNT_ID must be set in .env"

APP_PROJECT="${APP_PROJECT:-$(basename "$PROJECT_ROOT")}"

if [[ -z "${APP_NAMESPACE:-}" ]]; then
    APP_NAMESPACE=$(openssl rand -hex 4 | head -c 7)
    warn "APP_NAMESPACE not set — generated: ${APP_NAMESPACE}"
fi

TUNNEL_NAME="${APP_PROJECT}-${APP_NAMESPACE}"

# ── Discover exposed services from docker-compose labels ──────────────────────
COMPOSE_JSON=$(docker compose -f "${PROJECT_ROOT}/docker-compose.yml" \
    --project-directory "${PROJECT_ROOT}" config --format json 2>/dev/null) \
    || fail "Failed to parse docker-compose.yml — is Docker running?"

# Each element: "exposed_name:service_name:port"
# Two label formats are supported:
#
#   Indexed (multiple exposes per service):
#     cf_expose_0_name: "app"       cf_expose_0_port: "80"
#     cf_expose_1_name: "app-api"   cf_expose_1_port: "81"
#
#   Simple / backward-compatible (single expose):
#     cf_expose: "true"
#     cf_expose_name: "app"   # optional — defaults to the docker service name
#     cf_expose_port: "80"    # optional — defaults to PORT env var, then 80
mapfile -t EXPOSED < <(echo "$COMPOSE_JSON" | jq -r '
  .services | to_entries[]
  | .key as $svc
  | .value.labels as $labels
  | (
      # Indexed form: cf_expose_N_name / cf_expose_N_port
      [ $labels | to_entries[]
        | select(.key | test("^cf_expose_[0-9]+_name$"))
        | (.key | capture("^cf_expose_(?<n>[0-9]+)_name$").n) as $n
        | {name: .value, port: ($labels["cf_expose_\($n)_port"] // "80")}
      ]
      | if length > 0 then
          .[] | "\(.name):\($svc):\(.port)"
        else
          # Simple / legacy form: cf_expose=true
          if $labels["cf_expose"] == "true" then
            ($labels["cf_expose_name"] // $svc) as $name
            | ($labels["cf_expose_port"] // "80") as $port
            | "\($name):\($svc):\($port)"
          else empty end
        end
    )
')

[[ ${#EXPOSED[@]} -gt 0 ]] \
    || fail "No services with label cf_expose=true found in docker-compose.yml"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${CYAN}Setting up Cloudflare Tunnel${NC}"
echo -e "  Project   : ${GREEN}${APP_PROJECT}${NC}"
echo -e "  Namespace : ${GREEN}${APP_NAMESPACE}${NC}"
echo -e "  Tunnel    : ${GREEN}${TUNNEL_NAME}${NC}"
for entry in "${EXPOSED[@]}"; do
    name="${entry%%:*}"; rest="${entry#*:}"; svc="${rest%%:*}"
    hostname="${name}-${TUNNEL_NAME}.iorys.dev"
    echo -e "  ${name} (${svc}) → ${GREEN}https://${hostname}${NC}"
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ -n "${CLOUDFLARE_TUNNEL_ID:-}" && -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
    warn "Tunnel already configured (ID: ${CLOUDFLARE_TUNNEL_ID})"
    echo "  Run './run tunnel down' first to recreate."
    exit 0
fi

# ── Cloudflare API helper ─────────────────────────────────────────────────────
cf_api() {
    local method="$1" path="$2" data="${3:-}"
    local args=(-s -X "$method" "https://api.cloudflare.com/client/v4${path}"
        -H "Authorization: Bearer $CF_API_TOKEN"
        -H "Content-Type: application/json"
    )
    [[ -n "$data" ]] && args+=(--data "$data")
    curl "${args[@]}"
}

# ── .env writer ───────────────────────────────────────────────────────────────
update_env() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
info "Looking up zone ID for iorys.dev..."
ZONE_ID=$(cf_api GET "/zones?name=iorys.dev" | jq -r '.result[0].id // empty')
[[ -n "$ZONE_ID" ]] || fail "Could not find zone ID — check CF_API_TOKEN permissions."
success "Zone ID: ${ZONE_ID}"

# ══════════════════════════════════════════════════════════════════════════════
info "Checking for existing tunnel '${TUNNEL_NAME}'..."
EXISTING_ID=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?name=${TUNNEL_NAME}&is_deleted=false" \
    | jq -r '.result[0].id // empty')

if [[ -n "$EXISTING_ID" ]]; then
    warn "Found existing tunnel (${EXISTING_ID}) — reusing."
    TUNNEL_ID="$EXISTING_ID"
else
    info "Creating tunnel '${TUNNEL_NAME}'..."
    TUNNEL_SECRET=$(openssl rand -base64 32)
    CREATE_RESP=$(cf_api POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
        "{\"name\":\"${TUNNEL_NAME}\",\"tunnel_secret\":\"${TUNNEL_SECRET}\",\"config_src\":\"cloudflare\"}")
    TUNNEL_ID=$(echo "$CREATE_RESP" | jq -r '.result.id // empty')
    [[ -n "$TUNNEL_ID" ]] || fail "Failed to create tunnel:\n$(echo "$CREATE_RESP" | jq .)"
    success "Tunnel created: ${TUNNEL_ID}"
fi

# ══════════════════════════════════════════════════════════════════════════════
info "Fetching tunnel token..."
TOKEN_RESP=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/token")
TUNNEL_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.result // empty')
[[ -n "$TUNNEL_TOKEN" ]] || fail "Failed to get tunnel token:\n$(echo "$TOKEN_RESP" | jq .)"
success "Token acquired"

# ══════════════════════════════════════════════════════════════════════════════
info "Configuring ingress rules..."
INGRESS_ENTRIES=""
for entry in "${EXPOSED[@]}"; do
    name="${entry%%:*}"; rest="${entry#*:}"; svc="${rest%%:*}"; port="${rest##*:}"
    hostname="${name}-${TUNNEL_NAME}.iorys.dev"
    INGRESS_ENTRIES+="{\"hostname\":\"${hostname}\",\"service\":\"http://${svc}:${port}\",\"originRequest\":{}},"
done
INGRESS_ENTRIES+="{\"service\":\"http_status:404\"}"

INGRESS_RESP=$(cf_api PUT "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
    "{\"config\":{\"ingress\":[${INGRESS_ENTRIES}]}}")
[[ $(echo "$INGRESS_RESP" | jq -r '.success') == "true" ]] \
    || fail "Failed to configure ingress:\n$(echo "$INGRESS_RESP" | jq .)"
success "Ingress configured"

# ══════════════════════════════════════════════════════════════════════════════
create_or_update_dns() {
    local hostname="$1"
    local existing_id
    existing_id=$(cf_api GET "/zones/${ZONE_ID}/dns_records?type=CNAME&name=${hostname}" \
        | jq -r '.result[0].id // empty')
    local payload="{\"type\":\"CNAME\",\"name\":\"${hostname}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"proxied\":true,\"comment\":\"CF tunnel: ${TUNNEL_NAME}\"}"
    if [[ -n "$existing_id" ]]; then
        warn "CNAME ${hostname} already exists (${existing_id}) — updating."
        cf_api PUT "/zones/${ZONE_ID}/dns_records/${existing_id}" "$payload" > /dev/null
        echo "$existing_id"
    else
        local new_id
        new_id=$(cf_api POST "/zones/${ZONE_ID}/dns_records" "$payload" | jq -r '.result.id // empty')
        [[ -n "$new_id" ]] || fail "Failed to create DNS record for ${hostname}"
        echo "$new_id"
    fi
}

declare -A DNS_RECORD_IDS
for entry in "${EXPOSED[@]}"; do
    name="${entry%%:*}"; rest="${entry#*:}"; svc="${rest%%:*}"
    hostname="${name}-${TUNNEL_NAME}.iorys.dev"
    info "Creating DNS CNAME ${hostname}..."
    dns_id=$(create_or_update_dns "${hostname}")
    DNS_RECORD_IDS["$name"]="$dns_id"
    success "DNS record ready (${dns_id})"
done

# ══════════════════════════════════════════════════════════════════════════════
info "Saving to .env..."
update_env "APP_NAMESPACE"           "$APP_NAMESPACE"
update_env "APP_PROJECT"             "$APP_PROJECT"
update_env "CLOUDFLARE_TUNNEL_ID"    "$TUNNEL_ID"
update_env "CLOUDFLARE_TUNNEL_TOKEN" "$TUNNEL_TOKEN"
for name in "${!DNS_RECORD_IDS[@]}"; do
    key="CLOUDFLARE_DNS_RECORD_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
    update_env "$key" "${DNS_RECORD_IDS[$name]}"
done
success "Saved"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}✓  Cloudflare Tunnel ready!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for entry in "${EXPOSED[@]}"; do
    name="${entry%%:*}"
    hostname="${name}-${TUNNEL_NAME}.iorys.dev"
    echo -e "  🌐 ${name}:  ${GREEN}https://${hostname}${NC}"
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "  Run ${CYAN}./run up${NC} to start all services."
echo ""
