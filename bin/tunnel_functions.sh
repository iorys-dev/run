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
# Service discovery is label-driven — no per-project tunnel scripts needed.
# Add to any service in docker-compose.yml:
#
#   labels:
#     cf_expose: "true"           # expose via tunnel
#     cf_expose_port: "8080"      # port (falls back to PORT env, then 80)
#
# Hostname: {service_name}-{APP_PROJECT}-{APP_NAMESPACE}.iorys.dev
# ──────────────────────────────────────────────────────────────────────────────

IORYS_RUN_DIR="${IORYS_RUN_DIR:-.}"

# Absolute path to this script's directory (vendor/iorys/run/bin/).
# Used to locate the canonical tunnel-up.sh / tunnel-down.sh.
_IORYS_TUNNEL_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# ── Ensure tunnel is provisioned and ingress is in sync ──────────────────────────────
# Call in your `up` / `install` commands.
# - If CF creds are absent: skips silently (tunnel feature is opt-in)
# - If tunnel not yet created: provisions a new one
# - If tunnel already exists: syncs ingress rules to match current labels
ensureTunnel() {
    [[ -z "${CF_API_TOKEN:-}" || -z "${CF_ACCOUNT_ID:-}" ]] && return 0

    if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
        echo -e "\033[0;36m→  Cloudflare Tunnel not configured — creating one...\033[0m"
    else
        echo -e "\033[0;36m→  Syncing Cloudflare Tunnel ingress...\033[0m"
    fi
    bash "${_IORYS_TUNNEL_BIN}/tunnel-up.sh"
    set -a; source "${IORYS_RUN_DIR}/.env"; set +a
}

# ── tunnel sub-command handler ─────────────────────────────────────────────────
# Provides: up | down | recreate | status
# Calls the canonical tunnel-up.sh / tunnel-down.sh from the iorys/run package.
tunnel() {
    local sub="${1:-status}"
    local envfile="${IORYS_RUN_DIR}/.env"

    case "$sub" in
        up|create)
            echo -e "\033[0;36m→  Setting up Cloudflare Tunnel...\033[0m"
            bash "${_IORYS_TUNNEL_BIN}/tunnel-up.sh"
            set -a; source "$envfile"; set +a
            ;;
        down|destroy)
            echo -e "\033[0;36m→  Tearing down Cloudflare Tunnel...\033[0m"
            ${DC:-docker compose} stop cloudflared 2>/dev/null || true
            bash "${_IORYS_TUNNEL_BIN}/tunnel-down.sh"
            # Unset all tunnel-related vars so the current shell state is clean
            unset CLOUDFLARE_TUNNEL_ID CLOUDFLARE_TUNNEL_TOKEN 2>/dev/null || true
            while IFS= read -r var; do unset "$var" 2>/dev/null || true; done \
                < <(compgen -v | grep '^CLOUDFLARE_DNS_RECORD_' || true)
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
