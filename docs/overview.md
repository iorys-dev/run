# IORYS Run Script — Overview

A shared shell toolkit for iorys projects. Provides utility functions, Laravel
helpers, and Cloudflare Tunnel lifecycle management for local dev environments.

---

## Installation

Require the package (as a dev dependency):

```bash
composer require --dev iorys/run
```

Add the repman repository to `composer.json` if not already present:

```json
{
    "repositories": [
        {
            "type": "composer",
            "url": "https://iorys-dev.repo.repman.io"
        }
    ],
    "require-dev": {
        "iorys/run": "^1.1.0"
    }
}
```

---

## Setup

Copy the example run script and the env template to your project root:

```bash
cp vendor/iorys/run/bin/run-example.sh run
cp vendor/iorys/run/.env.example .env   # fill in CF_API_TOKEN and CF_ACCOUNT_ID
chmod +x run
```

Or use the interactive manager to scaffold a clean run script:

```bash
vendor/iorys/run/bin/iorys-run init
```

---

## Run Script Manager

`bin/iorys-run` is an interactive CLI that manages the `run` script in your project.

```
vendor/iorys/run/bin/iorys-run <command>
```

| Command | Description |
|---------|-------------|
| `init [--force]` | Scaffold a new `run` script (interactive) |
| `status` | Show version, enabled modules, registered commands |
| `module list` | List all available modules and their status |
| `module enable <name>` | Add a module source line to the managed block |
| `module disable <name>` | Remove a module from the managed block |
| `add-command <cli> <fn> <desc> [usage]` | Append an `addCommand` registration |
| `remove-command <cli>` | Remove a registered command |
| `update` | Run `composer update iorys/run` |

Modules are tracked in your `run` script using a managed block with `# @module <name>` markers:

```bash
#### iorys/run:modules:begin ####
source vendor/iorys/run/bin/functions.sh       # @module functions
source vendor/iorys/run/bin/tunnel_functions.sh # @module tunnel
#### iorys/run:modules:end ####
```

---

## Available modules

| File | Description |
|------|-------------|
| `bin/functions.sh` | Core helpers: `writeInfo`, `getHostIp`, `getServiceIp`, `getServicePort`, `addCommand`, `addAlias` |
| `bin/laravel_functions.sh` | Laravel helpers: `artisan`, `composer`, `tinker`, `migrate`, etc. |
| `bin/tunnel_functions.sh` | Cloudflare Tunnel: `tunnel`, `ensureTunnel`, `resolveTunnelDomain` |
| `.env.example` | Template for all env vars consumed by this package (copy to project `.env`) |

---

## Basic run script

```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

[[ -f .env ]] && { set -a; source .env; set +a; }

DC="docker compose"
IORYS_RUN_DIR="$PWD"

source vendor/iorys/run/bin/functions.sh
# source vendor/iorys/run/bin/laravel_functions.sh   # Laravel projects
# source vendor/iorys/run/bin/tunnel_functions.sh    # Cloudflare Tunnel

up() {
    $DC up -d --remove-orphans
}

case "${1:-help}" in
    up)   up ;;
    down) $DC down ;;
    *)    echo "Usage: ./run [up|down]" ;;
esac
```

---

## Core helper reference

### `addCommand`

Register a shell function as a named `./run` command:

```bash
addCommand "FUNCTION_NAME" "COMMAND_NAME" "Description" "[usage]"
```

### `addAlias`

Alias one command to another:

```bash
addAlias "ALIAS_NAME" "BASE_COMMAND"
```

### `writeInfo` / `getHostIp` / `getServiceIp` / `getServicePort`

Output helpers and Docker service inspection utilities. See
[`bin/functions.sh`](../bin/functions.sh) for full source.

---

## Laravel helpers

Source `bin/laravel_functions.sh` in Laravel projects to get:

| Function | Equivalent |
|----------|-----------|
| `artisan <cmd>` | `docker compose exec php php artisan <cmd>` |
| `composer <cmd>` | `docker compose run --rm php composer <cmd>` |
| `tinker` | `php artisan tinker` |
| `migrate` | `php artisan migrate` |

---

## Further reading

- [Cloudflare Tunnel integration](tunnel.md)
