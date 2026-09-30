---
title: 'CLI: Introduction'
status:
  tier: 1
  story: '13'
  state: complete
---

The Tyhp CLI is the primary tool for working with Tyhp projects. It covers building, linting, project init, version, help, installing Composer, Composer-aware project wiring (`tyhp composer` / `tyhp composer sync`), the language server, Xdebug debugging, `generate_tyhpdef`, `overlay`, and debug dumps (`tokenize`, `dump_ast`, `symbol_tree`).

## Usage

```
tyhp <action> [options]
```

## Actions

- `build` — Compile `.tyhp` source files into `.php` output. Runs parse, bind, check, emit.
- `lint` — Check the project for errors and warnings without producing output files. Supports text, JSON, and SARIF formats.
- `init` — Initialize a new Tyhp project with a default `tyhp.json` and create or merge `composer.json`.
- `install` — Download toolchain tools. `tyhp install composer` installs Composer (`./composer.phar` by default; `--global` → `~/.local/bin/composer`; `--force` to replace). This is not `tyhp composer install`.
- `version` — Display the compiler version (`tyhp version`, not a `--version` flag).
- `help` — Display help. `tyhp help --subject=<action>` for action-specific help.
- `explain` — Print the long-form explanation for a diagnostic code (`tyhp explain TYHP4001`).
- `composer` — Run Composer with Tyhp-aware processing (`tyhp composer install` proxies Composer’s `install`). `tyhp composer sync` writes ambient `extra.tyhp.require` pins onto root `require-dev`. See [CLI: Composer](cli_composer.md).
- `language_server` — Language Server Protocol over stdin/stdout. See [CLI: Language Server](cli_languageServer.md).
- `xdebug_proxy` — Xdebug + sourcemap debugging. See [CLI: XDebug Proxy](cli_xdebugProxy.md).
- `generate_tyhpdef` — Generate `.tyhpdef` files from PHP extensions, Composer packages, PHP sources, or the whole `vendor/` tree (`--vendor`). See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md). `--php-targets` reflects each listed minor with managed PHP and emits one gated tree. `--php` is the single-target escape hatch for private unpublished extensions.
- `overlay` — Copy a declaration into a hand-written overlay file (`create`) or write `@overlay-against` stamps (`stamp`). See [CLI: Overlay](cli_overlay.md).
- `symbol_tree` — Parse and bind the project, then dump the resolved symbol tree as JSON. See [CLI: Symbol Tree](cli_symbolTree.md).

Developer/debug actions also exist (`tokenize`, `dump_ast`, `clear_cache`, `integrity_check`) and are documented by `tyhp help`.

## Global Options

- `--help` — Display help. Use `tyhp help --subject=<action>` for action-specific help.
- `--tyhp-project=<path>` — Path to the `tyhp.json` project file (defaults to `./tyhp.json`).
- `--quiet` — Suppress the banner and non-diagnostic output.
- `--verbose` — Enable detailed output for each compilation phase.
- `--locale=<locale>` — Set the locale for diagnostic messages (default: en-US).
- `--pid-file=<path>` — Write the process id to this file while the process is running. Opt-in; nothing is written by default. Use a unique path per process if you run more than one long-lived Tyhp command.

## Project File

Most actions require a `tyhp.json` project configuration file. The CLI looks for this file in the current directory by default, or you can specify a path with `--tyhp-project`. If no `tyhp.json` is found, the compiler uses sensible defaults and displays an informational message.

## Exit Codes

- 0 (Success) — No errors; build completed successfully.
- 4 (CompileError) — One or more errors during compilation.
- 5 (CompileWarning) — Warnings but no errors (strict mode for build; always for lint).

## Getting Help

```
tyhp help --subject=build
tyhp help --subject=lint
tyhp help --subject=init
tyhp help --subject=install
tyhp help --subject=composer
tyhp help --subject=generate_tyhpdef
tyhp help --subject=overlay
tyhp help --subject=symbol_tree
tyhp help --subject=language_server
```

With `tyhp/compiler` installed, the same verbs work as `vendor/bin/tyhp …` or `composer tyhp …` (root `scripts.tyhp` forwards extra args). See [Installing Tyhp](intro_installation.md).
