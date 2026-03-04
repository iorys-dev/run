#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# tunnel-down.sh — Shared Cloudflare Tunnel teardown for all iorys projects
#
# Called by tunnel_functions.sh with IORYS_RUN_DIR pointing at the project root.
# Deletes all CLOUDFLARE_DNS_RECORD_* records found in .env, then the tunnel.
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

[[ -n "${CF_API_TOKEN:-}" ]]  || fail "CF_API_TOKEN must be set in .env"
[[ -n "${CF_ACCOUNT_ID:-}" ]] || fail "CF_ACCOUNT_ID must be set in .env"

cf_api() {
    local method="$1" path="$2" data="${3:-}"
    local args=(-s -X "$method" "https://api.cloudflare.com/client/v4${path}"
        -H "Authorization: Bearer $CF_API_TOKEN"
        -H "Content-Type: application/json"
    )
    [[ -n "$data" ]] && args+=(--data "$data")
    curl "${args[@]}"
}

remove_env() { sed -i "/^${1}=/d" "$ENV_FILE"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${CYAN}Tearing down Cloudflare Tunnel${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Delete all CLOUDFLARE_DNS_RECORD_* entries from .env ──────────────────
DNS_KEYS=$(grep -o '^CLOUDFLARE_DNS_RECORD_[^=]*' "$ENV_FILE" 2>/dev/null || true)
if [[ -n "$DNS_KEYS" ]]; then
    info "Looking up zone for iorys.dev..."
    ZONE_ID=$(cf_api GET "/zones?name=iorys.dev" | jq -r '.result[0].id // empty')
    if [[ -n "$ZONE_ID" ]]; then
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            record_id="${!key:-}"
            [[ -z "$record_id" ]] && continue
            info "Deleting DNS record ${key} (${record_id})..."
            DELETE_DNS=$(cf_api DELETE "/zones/${ZONE_ID}/dns_records/${record_id}")
            if [[ $(echo "$DELETE_DNS" | jq -r '.success') == "true" ]]; then
                success "Deleted ${key}"
            else
                warn "Deletion of ${key} returned: $(echo "$DELETE_DNS" | jq -c '.errors')"
            fi
        done <<< "$DNS_KEYS"
    else
        warn "Could not find zone — skipping DNS cleanup"
    fi
else
    warn "No CLOUDFLARE_DNS_RECORD_* in .env — skipping DNS cleanup"
fi

# ── 2. Delete tunnel ──────────────────────────────────────────────────────────
if [[ -n "${CLOUDFLARE_TUNNEL_ID:-}" ]]; then
    info "Deleting tunnel ${CLOUDFLARE_TUNNEL_ID}..."
    DELETE_TUNNEL=$(cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CLOUDFLARE_TUNNEL_ID}" \
        "{\"cascade\":true}")
    if [[ $(echo "$DELETE_TUNNEL" | jq -r '.success') == "true" ]]; then
        success "Tunnel deleted"
    else
        warn "Tunnel deletion returned: $(echo "$DELETE_TUNNEL" | jq -c '.errors')"
    fi
else
    warn "No CLOUDFLARE_TUNNEL_ID in .env — skipping tunnel cleanup"
fi

# ── 3. Clean .env (preserve APP_NAMESPACE and APP_PROJECT) ───────────────────
info "Cleaning tunnel config from .env..."
remove_env "CLOUDFLARE_TUNNEL_ID"
remove_env "CLOUDFLARE_TUNNEL_TOKEN"
sed -i "/^CLOUDFLARE_DNS_RECORD_/d" "$ENV_FILE"
success "Done"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}✓  Tunnel and DNS records removed.${NC}"
echo -e "  APP_NAMESPACE (${APP_NAMESPACE:-n/a}) preserved in .env."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
