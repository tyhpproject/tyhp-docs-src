---
title: 'FAQ: CLI'
---

## How do I build my project?

Run `tyhp build` in your project directory. This reads the `tyhp.json` configuration, discovers all included source files, and runs the full compilation pipeline: parse, bind, check, emit. Compiled PHP files are written to the configured output directory (default: `build/`).

```tyhp
tyhp build

# With options:
tyhp build --verbose          # detailed output
tyhp build --strict           # treat warnings as errors
tyhp build --dry-run          # check without writing files
tyhp build --clean            # wipe output directory first
```

After a successful build, the output summary shows file counts, per-phase timing, and any diagnostics:

```tyhp
Build completed successfully.

  Files:     42 source files -> 38 PHP files
  Duration:  1.23s (parse: 0.45s, bind: 0.12s, check: 0.34s, emit: 0.32s)
  Warnings:  2

Output written to: ./build/
```

## How do I inspect the bound symbol tree?

`tyhp symbol_tree` parses and binds the project (the same environment `lint` / `build` use) and dumps every declared symbol and signature as JSON. That includes PHP builtins, Composer package tyhpdefs, overlays, and your `.tyhp` sources — useful when an overlay rename, `partial function` alias, or `partial class X as Y` is not showing up where you expect.

```
tyhp symbol_tree
tyhp symbol_tree --filter=strtoupper
tyhp symbol_tree --out=symbols.json
```

Status lines go to stderr; the JSON document goes to stdout (or `--out`). `--filter` matches the current Tyhp name, FQN, or PHP emit name (case-insensitive substring). See [CLI: Symbol Tree](cli_symbolTree.md).

## How do I use watch mode?

Watch mode is **not** in this alpha. `tyhp build --watch` reports that it is unimplemented. Rebuild with `tyhp build` after edits, or use an external file watcher.

## How do I debug Tyhp code?

Build with `build.generateSourcemap` enabled, then run `tyhp xdebug_proxy` so the IDE talks to the proxy IDE port (default 9003) and XDebug connects to the proxy XDebug port (default 9004). The proxy translates breakpoints and stack frames back to `.tyhp` using the `.php.map` files next to compiled PHP. Without sourcemaps, debug the compiled PHP under `output.path` (default `build/`), or iterate with `tyhp lint`.

## How do I integrate Tyhp with CI/CD?

Use `tyhp lint` in your CI pipeline to check for type errors without producing output files. The `--format json` flag provides machine-readable output for integration with CI tools. Use `--strict` to fail the build on warnings as well as errors.

```tyhp
# In your CI pipeline:
tyhp lint --format json --strict
```

For production builds, run `tyhp build --strict` to ensure a clean build with no warnings. The exit code reflects the result: 0 for success, 4 for errors, 5 for warnings (when `--strict` is not set).

## How do I generate tyhpdef files?

Use `tyhp generate_tyhpdef` for **external PHP** (not the current project's `.tyhp`):

```
tyhp generate_tyhpdef --ext-name=curl --php-targets=8.2,8.3,8.4,8.5
tyhp generate_tyhpdef --package-path=./vendor/guzzlehttp/guzzle
tyhp generate_tyhpdef --vendor
tyhp generate_tyhpdef --source=./lib/**/*.php
tyhp generate_tyhpdef --validate ./tyhpdef/
tyhp generate_tyhpdef --audit-stubs=./tyhpdef --out=stub-audit.md
```

Exactly one of `--ext-name`, `--package-path`, `--source`, or `--vendor` is required, except `--validate` or `--audit-stubs` which can run alone.

- `--vendor` scans `vendor/composer/installed.json` (default `{projectRoot}/vendor`) and writes to **`vendor-tyhpdef/`**. It prefers published `tyhpdef/*` companions and `tyhpdef/php-ext-*`; otherwise it generates stubs. Do not edit those files — use overlays (`tyhp.json` `"overlay"` / `tyhp overlay create`). `post-autoload-dump` and `tyhp composer` `require` / `install` / `update` run the same mode. `TYHP_NO_VENDOR_TYHPDEF=1` skips the dump-script and `tyhp composer` generate step; `--no-tyhpdef` applies only to `tyhp composer`.
- `--package-path` reads `composer.json` autoload. `--include-dev` also reads `autoload-dev`.
- `--source` is `.php` only (`TYHP7507` otherwise).
- Harvested types rewrite PHPDoc `callable(...)` / `closure(...)` to `callable` and Psalm/PHPStan `empty` to `mixed`. PHP `static` in a value position (parameter, property, `@param`, `@var`, magic `@method` parameter, `@property`) is written as `self`; return positions keep `static` (`: static`, magic `@method` return types, including generic arguments such as `Builder<static>`). Unqualified class names inside `@template` bounds and other generic / union / intersection PHPDoc strings become FQCNs (`use` imports, unique PHP / `\Psr\*` shorts, same-package declared types); template parameters and builtins stay unqualified. Native `extends` / `implements` / trait `use` prefer a same-package declared type over a unique PHP / `\Psr\*` short of the same name; a true global the package does not declare stays global. Missing generic args on a bound are filled from that type's own default, else its constraint, else `mixed`. PHP-source harvest keeps the first type per FQCN when a later body is identical (kind, modifiers, `extends` / `implements`, members, flags — not doc comments) and warns; divergent bodies are both written and include-layer `TYHP8002` still fires. See [Repeated FQCNs](cli_tyhpdefGeneration.md#repeated-fqcns). Harvested `=` / `??` values are tyhpdef literals only (quoted string, number, `true`/`false`/`null`/`[]`, `Class::CONST`). A parameter whose PHP default is not a tyhpdef-safe literal stays optional with `= null` (the same dummy used for harvested implicit-nullable PHP; the declared type is not widened). Const and property `??` values that are not literals are omitted. Unmatched `#[Name(args)]` is reduced to `#[Name]`. See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#harvested-types-defaults-and-attributes).
- Default output for `--ext-name` / `--package-path` / `--source` is `{projectRoot|cwd}/tyhpdef/`. `--vendor` always uses `vendor-tyhpdef/`. `--split` is `file` (default), `namespace`, or `type`.
- `--ext-name` uses **Tyhp-managed PHP** by default. `--php-targets=8.2,8.3,8.4,8.5` reflects each listed minor and emits one gated tree. `--php=<path>` is a single-target escape hatch for private unpublished extensions (illegal with `--php-targets`).
- `--locale` / `--no-docs` control php.net manual comments on `--ext-name`. `--verify` applies overlays and checks the final API (`omit` is not a fail).

`tyhp overlay create \Iterator` copies a declaration into a hand-written overlay. `tyhp overlay stamp` writes `@overlay-against` comments. See [CLI: Overlay](cli_overlay.md).

Tyhp **libraries** always emit `package.tyhpdef` and additive-merge `extra.tyhp.package` onto publish-directory `composer.json` during `tyhp build`. Applications emit `package.tyhpdef` only when `build.generateTyhpdef` is true. PHP builtins are provided by the `tyhpdef/php` Composer package; optional extensions are `tyhpdef/php-ext-*`.

Full flag list: [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md).

## How do I install Composer from Tyhp?

`tyhp install composer` downloads the official Composer installer (SHA-384 verified) and places the binary. Default is `./composer.phar` (`--local`). `--global` installs to `~/.local/bin/composer`. `--force` replaces an existing binary at the destination.

That is not `tyhp composer install`, which runs Composer’s own `install` command (install packages from `composer.lock`). See [Installing Tyhp](intro_installation.md).

## How do I run Tyhp through Composer?

Install `tyhp/compiler` with `composer require --dev tyhp/compiler`. Then:

```
vendor/bin/tyhp build
composer tyhp build
```

`vendor/bin/tyhp` is the package `"bin"`. `composer tyhp …` uses the root `scripts.tyhp` entry (`vendor/bin/tyhp`) so extra args are forwarded. `tyhp init` writes that script and a `post-autoload-dump` that runs `--install-binary` then `generate_tyhpdef --vendor`.

## What is the language server for?

`tyhp language_server` starts the Tyhp Language Server Protocol (LSP) server over stdin/stdout. It uses the same parse, bind, and check pipeline as `tyhp lint`, then keeps that analysis live as you edit. Editors that speak LSP get diagnostics, completion, hover, go-to-definition, find references, rename, and related features.

The Tyhp Language extension for VS Code / Cursor and the PhpStorm plugin launch this command for you. Any other LSP client can start:

```
tyhp language_server --quiet --stdio --tyhp-project=./tyhp.json
```

See [CLI: Language Server](cli_languageServer.md).

## How do I sync ambient tyhpdefs after adding `tyhp/core`?

The first `composer require tyhp/core` often does not install `extra.tyhp.require` packages in that same transaction. Allow the plugin (`config.allow-plugins.tyhp/core` — `tyhp init` and `tyhp composer` write this when missing), then run `composer update` or `tyhp composer sync`.

Default `tyhp build` / `tyhp lint` explain missing extras (`TYHP7701`) and do not rewrite `composer.json`. `tyhp build --fix` and `tyhp composer sync` write root `require-dev` from the installed extra closure. Ordinary `tyhp build` never auto-updates Composer. See [CLI: Composer](cli_composer.md).
