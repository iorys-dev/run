# IORYS Run Script

### Usage

Require package to your project (perhaps as dev-dependency)

```bash
composer require iorys/run
```

---

Copy run-example.sh to your project root and rename it to run

```bash
cp vendor/iorys/run/bin/run-example.sh run
```

---

Ensure that run is executable

```bash
chmod +x run
```

---

If you are using run script in your laravel project, you would like to include laravel_functions.sh to your run script

```bash
source vendor/iorys/run/bin/laravel_functions.sh
```

This will add some useful functions to your run script, like `artisan` and `lara`, which are aliases for `php artisan`.

---

To add Cloudflare Tunnel support to any project, include tunnel_functions.sh:

```bash
IORYS_RUN_DIR="$(cd "$(dirname "$0")" && pwd)"   # set before sourcing
source vendor/iorys/run/bin/tunnel_functions.sh
```

This adds `tunnel`, `ensureTunnel`, and `resolveTunnelDomain` to your run script.
The project must provide `devops/local/scripts/tunnel-up.sh` and `tunnel-down.sh`.

See [TUNNEL.md](TUNNEL.md) for full integration guide.

---

Once you have your run script ready, you can run your project by executing `./run` command

### Available functions to use in your run script

```bash
addCommand (FUNCTION_NAME, FUNCTION_COMMAND, FUNCTION_DESCRIPTION, FUNCTION_USAGE)
addAlias (FUNCTION_ALIAS_NAME, FUNCTION_BASE_NAME)
```

