#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# tunnel_functions.sh — Cloudflare Tunnel lifecycle helpers for iorys projects
#
# Source this file in your project's run script to add `tunnel` command support,
# the `ensureTunnel` auto-provisioning hook, and the `resolveTunnelDomain` helper.
#
# Expected variables set by the project's run script BEFORE sourcing:
#   IORYS_RUN_DIR  — absolute path to the project root (directory of the run script)
#   DC             — docker compose command string ("docker compose" or "docker-compose")
#
# Projects must provide:
#   devops/local/scripts/tunnel-up.sh   — creates tunnel + DNS, writes .env
#   devops/local/scripts/tunnel-down.sh — destroys tunnel + DNS, cleans .env
#
# Subdomain convention:
#   {service}-{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev
#   Covered by *.iorys.dev Universal SSL — no extra cert setup needed.
# ──────────────────────────────────────────────────────────────────────────────

IORYS_RUN_DIR="${IORYS_RUN_DIR:-.}"

# ── Resolve public tunnel base domain ─────────────────────────────────────────
# Returns "{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev" when the tunnel is active.
# Usage:
#   domain=$(resolveTunnelDomain)
#   [[ -n "$domain" ]] && echo "https://app-${domain}"
resolveTunnelDomain() {
    local ns="${APP_NAMESPACE:-}"
    local proj="${APP_PROJECT:-}"
    if [[ -n "$ns" && -n "$proj" && -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
        echo "${proj}-${ns}.iorys.dev"
    fi
}

# ── Auto-provision tunnel if credentials present but no token yet ──────────────
# Call in your `up` / `install` commands to make tunnel setup transparent.
# Skips silently if CF_API_TOKEN / CF_ACCOUNT_ID are not set.
ensureTunnel() {
    [[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]] && return 0
    [[ -z "${CF_API_TOKEN:-}" || -z "${CF_ACCOUNT_ID:-}" ]] && return 0

    echo -e "\033[0;36m→  Cloudflare Tunnel not configured — creating one...\033[0m"
    bash "${IORYS_RUN_DIR}/devops/local/scripts/tunnel-up.sh"
    set -a; source "${IORYS_RUN_DIR}/.env"; set +a
}

# ── tunnel sub-command handler ─────────────────────────────────────────────────
# Provides: up | down | recreate | status
# Calls project-local tunnel-up.sh / tunnel-down.sh scripts.
tunnel() {
    local sub="${1:-status}"
    local scripts="${IORYS_RUN_DIR}/devops/local/scripts"
    local envfile="${IORYS_RUN_DIR}/.env"

    case "$sub" in
        up|create)
            echo -e "\033[0;36m→  Setting up Cloudflare Tunnel...\033[0m"
            bash "${scripts}/tunnel-up.sh"
            set -a; source "$envfile"; set +a
            ;;
        down|destroy)
            echo -e "\033[0;36m→  Tearing down Cloudflare Tunnel...\033[0m"
            ${DC:-docker compose} stop cloudflared 2>/dev/null || true
            bash "${scripts}/tunnel-down.sh"
            # Unset all known tunnel vars so the shell state is clean
            unset CLOUDFLARE_TUNNEL_ID CLOUDFLARE_TUNNEL_TOKEN \
                  CLOUDFLARE_DNS_RECORD_APP CLOUDFLARE_DNS_RECORD_POSTGRES \
                  CLOUDFLARE_DNS_RECORD_REDIS CLOUDFLARE_DNS_RECORD_PORTAL \
                  CLOUDFLARE_DNS_RECORD_ID 2>/dev/null || true
            [[ -f "$envfile" ]] && { set -a; source "$envfile"; set +a; }
            ;;
        recreate)
            tunnel down
            tunnel up
            ${DC:-docker compose} up -d --no-deps cloudflared 2>/dev/null || true
            ;;
        status)
            local domain
            domain=$(resolveTunnelDomain)
            if [[ -n "${CLOUDFLARE_TUNNEL_ID:-}" ]]; then
                echo "  Tunnel ID : ${CLOUDFLARE_TUNNEL_ID}"
                [[ -n "$domain" ]] && echo "  Domain    : *.${domain}"
                ${DC:-docker compose} ps cloudflared 2>/dev/null || true
            else
                echo "  No tunnel configured. Run './run tunnel up' to create one."
            fi
            ;;
        *)
            echo "  Usage: ./run tunnel [up|down|recreate|status]"
            return 1
            ;;
    esac
}

# Register with iorys/run addCommand framework if available
if declare -f addCommand > /dev/null 2>&1; then
    addCommand "tunnel" "tunnel" "Manage Cloudflare Tunnel (up/down/recreate/status)" "[up|down|recreate|status]"
fi
