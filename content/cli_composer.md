---
title: 'CLI: Composer'
status:
  tier: 2
  state: complete
---

The `composer` action runs Composer through Tyhp. After a successful `require`, `install`, or `update`, Tyhp runs `generate_tyhpdef --vendor` unless `--no-tyhpdef` is set. `TYHP_NO_VENDOR_TYHPDEF=1` also skips that hook (and the Composer dump-script generate step).

`tyhp composer sync` is a Tyhp subcommand: it writes ambient tyhpdef pins from installed `extra.tyhp.require` onto the root `require-dev` and Composer-updates those packages. It is the same write path as `tyhp build --fix`. Ordinary `tyhp build` and `tyhp lint` never rewrite `composer.json` and never run Composer.

## Usage

```
tyhp composer <command> [args]
tyhp composer sync
tyhp composer --help
```

When no Composer subcommand is given, Tyhp shows this help instead of forwarding to Composer.

```
tyhp composer require guzzlehttp/guzzle
tyhp composer install
tyhp composer update
tyhp composer sync
```

## Options

- `--help` — Show this help (same as `help --subject=composer`).
- `--no-tyhpdef` — Skip `generate_tyhpdef --vendor` after Composer `require`, `install`, or `update`. Does not apply to a direct `tyhp generate_tyhpdef --vendor`.

## Ambient tyhpdefs (`extra.tyhp.require`)

Compiled Tyhp libraries declare which Composer packages their **consumers** must install to type-check the public API. That map lives at `extra.tyhp.require` on the library’s `composer.json`. See [Composer Runtime Packages](project_composerPackages.md#ambient-tyhpdefs-extratyhprequire).

`tyhp/core` is a Composer plugin (`type: composer-plugin`). Allow it once:

```json
"config": {
    "allow-plugins": {
        "tyhp/core": true
    }
}
```

`tyhp init` writes that key. `tyhp composer` (including `install`, `update`, and `require`) writes it before invoking Composer when the key is missing, as do `tyhp composer sync` and `tyhp build --fix`. An explicit `false` is left as-is. A raw `composer` command still needs the key already on disk (or Composer’s prompt). A `--no-dev` Composer install does not write `require-dev` and does not rewrite `composer.json`.

## First `composer require tyhp/core`

The first `composer require tyhp/core` often does **not** install ambient tyhpdefs (`tyhpdef/php` and any extras further down the require tree) in that same transaction. That is expected.

After adding `tyhp/core` (or another Tyhp library that declares extras), run:

```
composer update
```

or:

```
tyhp composer sync
```

If extras are still missing, `tyhp build` and `tyhp lint` explain what to install (`TYHP7701`). `tyhp composer sync` or `tyhp build --fix` writes the installed extra closure onto root `require-dev` (plus `tyhp/compiler` when `tyhp/core` is in the graph, except when the root package is already `tyhp/compiler`) and Composer-updates those packages. The check reads only the root `composer.json` and `vendor/composer/installed.json` — it does not fetch Packagist. If extras on packages that are not installed yet are unknown, run `composer update` first.

## Build and lint

| Command | Extras check |
|---------|----------------|
| `tyhp build` / `tyhp lint` (default) | Reports missing extras (`TYHP7701`, compile fails) and a missing `tyhp/compiler` pin (`TYHP7702`, warning). Does **not** write `composer.json` and does **not** run Composer. |
| `tyhp build --strict` / `tyhp lint --strict` / `build.strictMode` | Same, and `TYHP7702` fails the run. |
| `tyhp build --fix` / `tyhp composer sync` | Writes root `require-dev` from the **installed** extra closure, then Composer-updates those packages. |
| Ordinary `tyhp build` | Never auto-updates Composer. |

`tyhp lint --fix` is the experimental source auto-fixer. It does **not** sync extras. Use `tyhp composer sync` or `tyhp build --fix` for that.

A disjoint extra constraint vs an existing root pin is `TYHP7700`. A `composer.json` parse/write failure during sync is `TYHP7703`.

## Related

- [Composer Runtime Packages](project_composerPackages.md) — `extra.tyhp.require`, library authors, `tyhp/core` plugin
- [Getting Started](intro_gettingStarted.md) — init, first require
- [CLI: Build](cli_build.md) — `--fix` vs ordinary build
- [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md) — `--vendor` after Composer
- [Diagnostic Code Reference](diagnostics_reference.md) — `TYHP7700`–`TYHP7703`
