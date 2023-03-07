# IORYS Run Script

### Usage

Require package to your project (perhaps as dev-dependency)

```bash
composer require iorys/run
```

---

Copy run-example.sh to your project root and rename it to run

```bash
cp vendor/iorys/run/run-example.sh run
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

Once you have your run script ready, you can run your project by executing `./run` command

### Available functions to use in your run script

```bash
addCommand (FUNCTION_NAME, FUNCTION_COMMAND, FUNCTION_DESCRIPTION, FUNCTION_USAGE)
addAlias (FUNCTION_ALIAS_NAME, FUNCTION_BASE_NAME)
```