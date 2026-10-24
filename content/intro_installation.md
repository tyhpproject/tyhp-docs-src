---
title: 'Installing Tyhp'
status:
  tier: 1
  story: '13'
  state: complete
---

The Tyhp compiler is a .NET application targeting .NET 9. This page covers system requirements and how to install the **805.1.2-beta.3** compiler.

## System Requirements

- PHP 8.2, 8.3, 8.4, or 8.5 — required to run compiled output, and to use the Composer `tyhp/compiler` shim
- Composer — required to install `tyhpdef/php`, `tyhp/core`, and other runtime packages. If you already have the Tyhp CLI, `tyhp install composer` can install Composer for you
- Self-contained compiler binaries — no .NET install needed
- Framework-dependent binaries — [.NET 9 runtime](https://dotnet.microsoft.com/en-us/download/dotnet/9.0)

:::note
.NET is only needed on the machine that compiles Tyhp (and only for framework-dependent builds). Deployment servers need PHP only.
:::

## Install with Composer

`tyhp/compiler` is a Composer package. Add it as a **project** `require-dev` dependency; Composer places a `vendor/bin/tyhp` shim that downloads the native compiler.

```bash
composer require --dev tyhp/compiler
vendor/bin/tyhp init
composer update
vendor/bin/tyhp build
```

You can also run Tyhp through the root Composer script that `tyhp init` writes:

```bash
composer tyhp build
```

`composer require` already installs the compiler package and writes a `composer.lock`. `tyhp init` then merges `composer.json` (adding `tyhpdef/php`, `tyhp/core`, `allow-plugins.tyhp/core`, and the scripts) and writes `tyhp.json`, `src/index.tyhp`, and the `build/` and `tyhpdef/` directories. It stops with an error if `tyhp.json` already exists, and it adds Tyhp entries to an existing `.gitignore`. Init does **not** install those newly-added packages for you — because the lock file already exists from the `require` step, use `composer update` (not `composer install`, which would only reinstall what the lock already has) so `tyhpdef/php`, `tyhp/core`, and the `post-autoload-dump` hooks land.

The first `composer require tyhp/core` often does not install ambient tyhpdefs in that same transaction. After adding core, run `composer update` or `tyhp composer sync`. If `tyhp build` reports missing extras (`TYHP7701`), that is the recovery path. See [CLI: Composer](cli_composer.md).

That dump script runs:

1. `vendor/bin/tyhp --install-binary` — download the native compiler if it is not already present (idempotent)
2. `vendor/bin/tyhp generate_tyhpdef --vendor` — type installed Composer libraries and extensions (see [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md))

If you used `--no-scripts`, or the dump step did not run, call those commands yourself before `build`. A later `vendor/bin/tyhp build` does **not** download the native binary; the shim exits with an error and tells you to run `--install-binary`.

## Installation from GitHub Releases

Download a binary from [GitHub Releases](https://github.com/tyhpproject/tyhp/releases), or:

```
curl -fsSL https://raw.githubusercontent.com/tyhpproject/tyhp/main/scripts/install.sh | bash -s --
```

The script selects OS and architecture. If .NET 9 is already installed, it prefers a **framework-dependent** build; otherwise it installs a **self-contained** binary. Pass `--self-contained` or `--framework-dependent` to force a variant.

On Windows, use [`scripts/install.ps1`](https://github.com/tyhpproject/tyhp/blob/main/scripts/install.ps1) instead of the bash script.

### Manual download

1. Open the [releases page](https://github.com/tyhpproject/tyhp/releases) and download the asset for your platform (`tyhp-osx-arm64`, `tyhp-linux-x64`, `tyhp-win-x64.exe`, or the `-fxdependent` variant).
2. Place the binary on your PATH (for example `/usr/local/bin/tyhp`).
3. Verify with `tyhp version`.

If you already have `tyhp` on your PATH and still need Composer, use `tyhp install composer` (below), then `tyhp init` and `composer install`.

## `tyhp install composer` vs `tyhp composer install`

These are different commands.

| Command | What it does |
|---------|----------------|
| `tyhp install composer` | Downloads the [official Composer installer](https://getcomposer.org/download/), verifies its SHA-384 signature, and places the Composer binary |
| `tyhp composer install` | Proxies Composer’s own `install` (install packages from `composer.lock`) |

`tyhp install composer` requires `php` on `PATH`. Default destination is **`./composer.phar`** in the project directory (`--local` is the same). `--global` installs to **`~/.local/bin/composer`**. If a binary is already at the destination, the command leaves it in place unless you pass **`--force`**.

```
tyhp install composer
tyhp install composer --global
tyhp install composer --force
tyhp install --help
```

After Composer is available:

```
tyhp init
composer install
tyhp build
```

## Running the CLI

| Invocation | When to use it |
|------------|----------------|
| `vendor/bin/tyhp build` | Compiler installed via `tyhp/compiler`; Composer `"bin"` |
| `composer tyhp build` | Same binary; extra args after `tyhp` are forwarded by the root `scripts.tyhp` entry (`vendor/bin/tyhp`) |
| `tyhp build` | Native compiler already on `PATH` (GitHub / install script) |

`tyhp init` writes `"tyhp": "vendor/bin/tyhp"` (or `{bin-dir}/tyhp` when Composer `config.bin-dir` is set) and a `scripts-descriptions.tyhp` string so `composer list` (and `composer run-script --list`) describes the script. `composer tyhp --help` forwards `--help` to `vendor/bin/tyhp` instead of showing that description.

## Verifying Installation

```
tyhp version
```

Or, with the Composer shim:

```
vendor/bin/tyhp version
```

You should see output similar to:

```
Tyhp compiler: 805.1.2-beta.3
.NET runtime:   .NET 9.0.x
ANTLR runtime:  4.x.x
OS:             ...
```

## Runtime packages

Compiled projects need Composer packages such as `tyhpdef/php` (PHP builtin tyhpdefs) and `tyhp/core`. `tyhp init` adds `tyhp/core` as **`@dev`** in `require`, `tyhpdef/php` as **`@dev`** in `require-dev`, and `tyhp/compiler` in `require-dev` at the exact version of the compiler package that matches the CLI.

After each build, `tyhp build` prints the other runtime packages your compiled code needs (for example `tyhp/async` when it uses `async`/`await`). When `build.updateComposer` is enabled, it writes them into the `composer.json` in `output.publishPath` and runs `composer install` there. The compiled `tyhp/*` versions it writes match `output.phpVersion` plus **that package's own** `X.Y` (`8.4` + core `0.2` → `tyhp/core: 804.0.2`). Otherwise, require them yourself. Packages you opt into, such as `tyhp/io` and `tyhp/parallel`, are never added for you; see [Runtime Packages Overview](package_intro.md).

How to pin versions for apps vs libraries is on the [Composer Runtime Packages](project_composerPackages.md) page.

`tyhpdef/php` in this alpha is a **PHP 8.2 baseline**. APIs that exist only on PHP 8.3–8.5 may be missing from the stubs.
