---
title: 'FAQ: Project Configuration'
---

## What goes in tyhp.json?

The `tyhp.json` file configures the Tyhp compiler for your project. It specifies which source files to include, where to write compiled PHP output, which PHP version to target, and various build options. Language strictness is not a config knob — null safety and required types are always on. The file uses standard JSON format and is placed in your project root.

A minimal configuration only needs source file patterns and an output path. `tyhp init` also sets `tyhpdefInclude` for `vendor-tyhpdef/` and `overlay` for `tyhpdef/`:

```json
{
    "include": ["./src/**/*.tyhp"],
    "output": {
        "path": "./build"
    },
    "tyhpdefInclude": ["./vendor-tyhpdef/**/*.tyhpdef"],
    "overlay": ["./tyhpdef/**/*.tyhpdef"]
}
```

## How do I set the target PHP version?

Set the `output.phpVersion` option in `tyhp.json`. Supported values are `"8.0"` through `"8.5"`. If the key is omitted, the compiler defaults to **`"8.2"`** and emits warning **TYHP4306** once per compilation. This controls which PHP features the compiler uses in the generated output, which version-gated declarations are visible, **and** which `tyhp/*` Composer MAJOR to install (`"8.3"` → `803.x`). See the Composer Runtime Packages page and [PHP Version Gating](tyhp_0320_phpVersionGating.md).

```json
{
    "output": {
        "phpVersion": "8.3"
    }
}
```

## How do I set tyhp/* versions in composer.json?

Package MAJOR is the **PHP version the artifact is for**, not the compiler version. Each `tyhp/*` package has its own `X.Y`. An app with `output.phpVersion` `"8.4"` and core `0.0` should require `tyhp/core: 804.0.0`. A library that supports PHP 8.3+ should require an OR of the majors using **that package's** X: `803.0.* || 804.0.* || 805.0.*`. See the Composer Runtime Packages page.

## How do I configure source maps?

Set `build.generateSourcemap` to `true` in `tyhp.json`, then run `tyhp build`. Each compiled `.php` file gets a sibling `.php.map` (Source Map v3) and a `//# sourceMappingURL=` comment. Set `build.sourcemapIncludeContent` to `true` to embed the original `.tyhp` text in the map.

```json
{
    "build": {
        "generateSourcemap": true,
        "sourcemapIncludeContent": false
    }
}
```

Use the maps with `tyhp xdebug_proxy` to debug `.tyhp` sources. See [CLI: Source Map Generation](cli_sourcemapGeneration.md).

## How do I exclude files from compilation?

Use the `exclude` array with glob patterns. Files matching any exclude pattern are skipped even if they match an `include` pattern:

```json
{
    "include": ["./src/**/*.tyhp"],
    "exclude": [
        "./src/tests/**",
        "./src/legacy/**",
        "./src/**/*.draft.tyhp"
    ]
}
```

Glob patterns support `*` (any file name), `**` (any directory depth), and `?` (single character).

## Can I have multiple output directories?

Not directly. The <code>output.path</code> option specifies a single output directory. However, PSR-4 namespace mappings (via the <code>psr4</code> option) control the directory structure within the output directory. Each namespace prefix maps to a subdirectory, so classes in different namespaces are written to different subdirectories automatically.

```json
{
    "output": {
        "path": "./build"
    },
    "psr4": {
        "App\\Models\\": "src/Models/",
        "App\\Services\\": "src/Services/"
    }
}
```

If you need completely separate output directories for different parts of your project, consider using multiple `tyhp.json` files with the `--tyhp-project` flag.

## What happens if there is no tyhp.json?

If no `tyhp.json` is found, the compiler uses sensible defaults: it looks for `.tyhp` files in the current directory, outputs to `build/`, targets PHP **8.2** (warning **TYHP4306**), and enables strict type checking. An informational message is displayed to let you know defaults are being used. Run `tyhp init` to create a configuration file.

## Why one `tyhpdef/php` package across PHP 8.2–8.5?

The compiler filters version-gated stubs (`declare(php=…)` / `#[\Tyhp\Php]`) to your `output.phpVersion`. One `tyhpdef/php` package (and one `tyhpdef/php-ext-*` per optional extension) describes APIs that differ by minor; you do not install `tyhpdef/php-8.2` forks or a PHP version matrix. Contributors lint/build against `"8.2"`–`"8.5"` by changing `output.phpVersion`. Packagist artifacts for runtime helpers (`tyhp/core`, …) still use MAJOR `802`–`805` for the PHP the *runtime* package runs on. See [PHP Version Gating](tyhp_0320_phpVersionGating.md) and the Composer Runtime Packages page.

## Why don't scalar methods need `use extension`?

`tyhp/core` contains `global use extension \Tyhp\StringExtensions;` (and the matching Array / Int / Float / Bool / Closure files). Every `.tyhp` file in that compilation already has those methods. A local `use extension \Tyhp\StringExtensions;` with no adaptations warns (`TYHP4169`). Write a local `use` only to hide or rename methods in that file.

## How do I configure the type checker?

Language strictness is not configurable. Null safety, required type annotations (or inferable initializers), and narrowing `mixed` before use are always enforced. The `checker` section only exposes resource limits and tooling knobs:

```json
{
    "checker": {
        "templateStringMaxStates": 256,
        "maxFixIterations": 10
    }
}
```

- `templateStringMaxStates` (default: `256`) — Upper bound on template-string automaton complexity for subtyping checks.
- `maxFixIterations` (default: `10`) — Maximum auto-fix re-run iterations for `tyhp lint --fix`.

## How do I hide a compiler warning?

Add the diagnostic id to `suppressWarnings` in `tyhp.json`. Only **warnings** are hidden — listing an error code has no effect.

```json
{
    "suppressWarnings": ["TYHP8027"]
}
```

CLI `--suppress-warnings=TYHP8027` replaces the JSON array for that run. Use `tyhp --explain TYHP8027` to read the long-form explanation before suppressing a code.

## How do I declare ambient tyhpdefs on a library?

Put everything this package needs to compile in `require-dev`. Copy the subset consumers must install into `extra.tyhp.require` (any Composer package name; duplicate those pins in `require-dev`). Leave author-only wrappers out of extras — `tyhp/decimal` keeps bcmath / gmp / php-decimal tyhpdefs in `require-dev` only.

`tyhp/core` ships a Composer plugin that merges extras onto the application root `require-dev`. Allow `tyhp/core` under `config.allow-plugins`. If extras are missing after `composer require tyhp/core`, run `tyhp composer sync` or `composer update`. See [Composer Runtime Packages](project_composerPackages.md#ambient-tyhpdefs-extratyhprequire).
