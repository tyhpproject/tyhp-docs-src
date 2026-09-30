---
title: 'Project Options List'
status:
  tier: 0
  story: '10'
  state: complete
---

This is the complete reference for all options available in `tyhp.json`. Options can also be passed as CLI arguments where noted. CLI arguments take precedence over file-based configuration.

## General Options

:::member[quiet]
Type: `bool` (default: `false`). When true, suppresses the banner and non-error output. Useful for scripting and CI environments.
:::

:::member[suppressWarnings]
Type: `array<string>` (default: `[]`). Warning codes to hide during build, lint, overlay, and language-server analysis. Each entry is a diagnostic id such as `"TYHP8027"` or `"8027"` (case-insensitive `TYHP` prefix). Matching **warning**-severity diagnostics are dropped: they are not printed, not counted, and do not fail `--strict`. Errors and info diagnostics are never dropped, even if their code is listed. Unknown tokens emit warning **TYHP6003** (`ConfigInvalidValue`) and are ignored. CLI: `--suppress-warnings=TYHP8027,TYHP8021` replaces the JSON array when present.
:::

:::member[type]
Type: `string` (default: `"application"`). Project kind: `"application"` or `"library"`. Library projects always emit `package.tyhpdef` and additive-merge `extra.tyhp.package` onto publish-directory `composer.json` during `tyhp build`.
:::

:::member[locale]
Type: `string` (default: `"en-US"`). Sets the locale for compiler messages and diagnostic output.
:::

:::member[cache-dir]
Type: `string` (default: system local application data directory). Sets the directory used for caching parsed ASTs and build state. Caching speeds up subsequent builds by reusing parsed results for unchanged files. Supports [string interpolation](#string-interpolation).
:::

## String interpolation

Selected path-like strings in `tyhp.json` expand `{name}`-style placeholders when the project is loaded. Use `{{` and `}}` for a literal brace. An unknown placeholder, an unset `{env.NAME}`, or a missing Composer field is error **TYHP6009**.

Identity comes from **`composer.json` next to `tyhp.json`** (the project root), never from a `composer.json` that `build.updateComposer` may write under `output.publishPath`. `tyhp init` writes `name` but not `version`; add `"version"` before using `{version}`. Composer is loaded only when a Composer-sourced variable is used.

**Composer** (from that root `composer.json`):

- `{name}` — package name (`vendor/package` may contain one `/`)
- `{name.vendor}`, `{name.package}` — split on `/`; if there is no slash, both are the whole name
- `{name.slug}` — `{name}` with `/` replaced by `-`
- `{version}` / `{projectVersion}` — the `version` string
- `{version.major}`, `{version.minor}`, `{version.patch}` — leading numeric components (`3.4.1-beta.1` → `3`, `4`, `1`); a missing slice is `"0"`
- `{version.suffix}` — everything after the patch, including the leading separator (`3.4.1-beta.1` → `-beta.1`, `3.4.1+build` → `+build`, `5.34.12.5.3.22` → `.5.3.22`). Empty when there is no suffix (not an error)
- `{composer.type}` — Composer's `type` field

**Tyhp** (no Composer file required):

- `{type}` — tyhp.json `"application"` or `"library"`
- `{phpVersion}`, `{phpVersion.major}`, `{phpVersion.minor}` — from `output.phpVersion` (`8.2` → major `8`, minor `2`)
- `{phpVersion.id}` — Tyhp PHP id: major plus a two-digit minor (`8.2` → `802`, `8.6` → `806`)
- `{profile}` — `build.profile`, or `"debug"` when unset
- `{tyhpVersion}` — the running compiler version
- `{env.NAME}` — process environment variable `NAME` (set it before invoking `tyhp`)

**Copy-time** (only in `output.publishContent` `dst`, after globs are expanded):

- `{fileName}`, `{fileStem}`, `{extension}` (includes the leading `.`; empty when the file has no extension), `{recursiveDir}` (directory of the matched relative path, no trailing slash; empty at the match root), `{relativePath}`. `{fileStem}` is empty for a dotfile whose name is all extension (`.gitignore`).

A `dst` that still contains file variables is the destination for that one file (it does not also append the glob-relative path). A trailing `/` on `dst` means a directory: only `{fileName}` is appended. That lets `{fileStem}.txt` be unique per match.

**Interpolated keys:** `cache-dir`; `output.path`; `output.publishPath`; `output.publishContent` `src` / `dst` / `exclude`; `psr4` **values** (not keys); `psr4Includes`; `build.entryPointAutoloader` values; `xdebugProxy.sourceMapDir`, `xdebugProxy.tyhpSourceRoot`, and `xdebugProxy.phpOutputRoot`.

**Not interpolated:** `include` / `exclude` / `tyhpdefInclude` / `tyhpdefExclude` / `overlay`; `output.phpVersion`; `output.namespacePrefix`; flags and enums. Substituted values cannot be empty (except `{version.suffix}`, `{recursiveDir}`, `{extension}`, and `{fileStem}`), contain `\`, or use `..` as a path segment. `{env.*}` follows the same rules (a tag like `v1.2.3` is fine).

## Source File Options

:::member[include]
Type: `array<string>`. Glob patterns for source files to include in the project. Supports `*` (any file), `**` (any directory depth), and `?` (single character) wildcards. Example: `["./src/**/*.tyhp", "./src/**/*.php"]`.
:::

:::member[exclude]
Type: `array<string>`. Glob patterns for files to exclude from the project. Files matching these patterns are skipped even if they match an `include` pattern. Useful for excluding test files, vendor directories, or generated code.
:::

:::member[source.tagless]
Type: `bool` (default: `false`). When true, `.tyhp` and `.tyhpdef` files are parsed without requiring `<?tyhp` / `<?tyhpdef`. Closing `?>` is an error in this mode. Nested as `"source": { "tagless": true }`.
:::

## Output Options

These options are nested under the `"output"` key in `tyhp.json`.

:::member[output.path]
Type: `string` (default: `"build/"`). The directory where compiled PHP files are written, relative to the project root. The directory is created automatically if it does not exist. Supports [string interpolation](#string-interpolation).
:::

:::member[output.publishPath]
Type: `string` (default: `"."`). The published package root, relative to the directory that contains `tyhp.json`. `composer.json` (library `extra.tyhp.package` is merged here) and `package.tyhpdef` are written here. Compiled PHP still uses `output.path`, which may be this directory or a subdirectory such as `src/`. Sourcemaps stay next to the PHP they describe. Supports [string interpolation](#string-interpolation) (for example `"./publish/{version}"`).
:::

:::member[output.publishClean]
Type: `bool` (default: `false`). When true, `tyhp build` deletes `output.publishPath` and recreates it before compiling. The build fails if that path is the project root (the default `"."`), a system directory, or overlaps a source include path. Use this only with a dedicated publish directory such as `"./publish"`. `--clean` still only deletes `.php` / `.php.map` under `output.path`.
:::

:::member[output.publishContent]
Type: `array<object>` (default: `[]`). Copy extra files into `output.publishPath` after a successful emit. Each entry:

- `src` (`string` or `string[]`, required) — file, directory, or glob (`*`, `?`, `**`). Relative to the project root unless absolute. A directory with no glob copies that tree. Supports [string interpolation](#string-interpolation).
- `dst` (`string`, default `"."`) — destination under `output.publishPath`. Omitted, `""`, or `"."` is the publish root. A trailing `/` forces a directory. If `src` is not a glob and resolves to one file, a `dst` whose last segment has an extension is a rename (`LICENSE` → `LICENSE.txt`). Glob `src` always treats `dst` as a directory unless `dst` uses copy-time file variables (`{fileName}`, `{fileStem}`, and so on). Destinations cannot escape the publish directory. Supports interpolation; file variables expand per matched file.
- `exclude` (`array<string>`, default `[]`) — globs subtracted from `src` matches. Supports interpolation.
- `flat` (`bool`, default `false`) — copy using only the file name. When false, a `**` glob keeps the path matched by `**` under `dst`.
- `preserve` (`string`, default `"newest"`) — `"newest"` copies when dest is missing or source is newer; `"always"` overwrites; `"never"` copies only if dest does not exist.
- `skipUnchanged` (`bool`, default `true`) — skip when dest exists and size plus last-write time match the source.
- `overwriteReadOnly` (`bool`, default `true`) — replace a read-only dest file.
- `required` (`bool`, default `false`) — error if `src` matches nothing; otherwise warn.
- `followSymlinks` (`bool`, default `false`) — copy symlink targets instead of recreating the symlink.

`--dry-run` reports planned copies without writing. Two matches that flatten to the same dest in one entry is an error; later entries win for the same dest, still subject to that entry's `preserve` / `skipUnchanged`.
:::

:::member[output.phpVersion]
Type: `string` (default: `"8.2"`). The oldest PHP version the compiled output runs on. Supported values: `"8.0"` through `"8.5"`. This affects which PHP features the emitter uses in the generated code and which gated declarations the binder keeps. A PHP version gate (`declare(php=…)` / `#[\Tyhp\Php]`) that holds for every version from this one up emits no check; one that holds for only some versions emits a `\PHP_VERSION_ID` check in the PHP. This key itself is not interpolated; use `{phpVersion}` or `{phpVersion.id}` in other path keys (`"8.2"` → `{phpVersion.id}` `802`).

If the key is omitted (and the legacy top-level `phpVersion` key is also omitted), the compiler uses `"8.2"` and emits warning **TYHP4306** once per compilation — not per file. That default is the compiler check/emit target. It is not the managed PHP runtime used by `tyhp generate_tyhpdef`.

An explicit but unsupported value is a different path: warning **TYHP6006** and a fallback to `"8.4"`. See [PHP Version Gating](tyhp_0320_phpVersionGating.md).
:::

:::member[output.strictTypes]
Type: `bool` (default: `true`). When true, adds `declare(strict_types=1);` to all compiled PHP output files. Recommended for type safety.
:::

:::member[output.namespacePrefix]
Type: `string | null` (default: `null`). A namespace prefix added to or stripped from all namespaces in the output. Used when the compiled output needs a different namespace root than the source code.
:::

:::member[output.comments]
Type: `bool` (default: `true`). Controls whether comments from the Tyhp source are preserved in the compiled PHP output. Set to `false` to strip comments for smaller output.
:::

## Build Options

These options are nested under the `"build"` key in `tyhp.json`, except where noted.

:::member[build.generateSourcemap]
Type: `bool` (default: `false`). When `true`, `tyhp build` writes a Source Map v3 `.php.map` file next to each compiled `.php` file and appends `//# sourceMappingURL=`. Used by `tyhp xdebug_proxy`. See [CLI: Source Map Generation](cli_sourcemapGeneration.md).
:::

:::member[build.sourcemapIncludeContent]
Type: `bool` (default: `false`). When `true` with `build.generateSourcemap` enabled, embed original `.tyhp` source in each map's `sourcesContent` array.
:::

:::member[build.generateTyhpdef]
Type: `bool` (default: `false`). For **applications**, write `package.tyhpdef` in the publish directory (`output.publishPath`, default: the project root) when `true`. **Libraries always emit** `package.tyhpdef` and additive-merge `extra.tyhp.package` on `composer.json`; this key is ignored for `"type": "library"`. See [CLI: Build](cli_build.md) and [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#auto-generation-during-build).
:::

:::member[build.updateComposer]
Type: `bool` (default: `false`). When true, generates or updates a `composer.json` in `output.publishPath` with PSR-4 autoload mappings (relative to that file) and Tyhp runtime package dependencies.
:::

:::member[build.entryPointAutoloader]
Type: `object | null` (default: `null`). A map of named autoloader paths. When set, entry point files (root code files) will have `require_once` statements added for the Composer autoloader. Example: `{"default": "vendor/autoload.php"}`. Map **values** support [string interpolation](#string-interpolation).
:::

:::member[build.structBacking]
Type: `string` (default: `"array"`). Controls how Tyhp structs are represented in compiled PHP. The default `"array"` compiles structs to associative arrays.
:::

:::member[build.decimalBacking]
Type: `string` (default: `"bcmath"`). The PHP extension used for decimal arithmetic. Supported values: `"bcmath"`, `"gmp"`.
:::

:::member[build.decimalScale]
Type: `int` (default: `28`). The default number of decimal places for decimal arithmetic operations.
:::

:::member[build.decimalRounding]
Type: `string` (default: `"halfUp"`). The default rounding mode for decimal arithmetic.
:::

:::member[build.allowEval]
Type: `bool` (default: `false`). When true, re-enables `eval()` usage in Tyhp code. By default, `eval()` is disabled for security and type-safety reasons.
:::

:::member[build.experimentalReadonlyCloneWith]
Type: `bool` (default: `false`). When true, allows `clone ... with` on `readonly` properties for PHP 8.2–8.4 by emitting a compiler wrapper. PHP 8.5+ supports this natively and does not need the flag. `new ... with` on `readonly` never requires it. In-place `$obj with [...]` still cannot set `readonly` after construction.
:::

:::member[build.runtimeGenericChecks]
Type: `bool` (default: `false`). When true, the emitter inserts runtime type checks at generic parameter and return boundaries (in addition to compile-time checking). Off by default.
:::

## Optimization Options

```status
tier: 3
story: '23'
state: planned
```

:::warning Not in this alpha
In this alpha the optimize pass is a no-op.
:::

These options are nested under the `"build"` key in `tyhp.json` and control the compiler optimizer. Each option also has a corresponding CLI flag that overrides the file value.

:::member[build.profile]
Type: `string` (default: `"debug"`). The build profile that sets coordinated defaults for optimization, source maps, and comment output. Supported values: `"debug"`, `"balanced"`, `"release"`. CLI: `--profile=<value>`.
:::

:::member[build.optimize]
Type: `string` (default: derived from `profile`). The optimization level applied to the compiled output, overriding the profile default. Supported values: `"none"`, `"basic"`, `"aggressive"`. `basic` enables extension inlining, constant folding, dead code elimination, and unused import pruning. CLI: `--optimize=<value>`.
:::

:::member[build.optimizations]
Type: `object` (default: `{}`). Per-module enable/disable overrides applied on top of the `optimize` level. Keys are optimization module names; values are booleans. Use this to turn individual optimizations on or off without changing the overall level. CLI: `--optimize-enable=<module>` and `--optimize-disable=<module>`.
:::

## PSR-4 Autoload Options

:::member[psr4]
Type: `object | null` (default: `null`). PSR-4 namespace-to-directory mappings for the compiled output. Keys are namespace prefixes (with trailing `\\`), values are directory paths. Example: `{"App\\": "src/"}`. Values support [string interpolation](#string-interpolation); keys do not.
:::

:::member[psr4Includes]
Type: `array<string> | null` (default: `null`). Additional PSR-4 autoload paths to include in the generated `composer.json`. Supports [string interpolation](#string-interpolation).
:::

## Checker Options

These options are nested under the `"checker"` key in `tyhp.json`. They control resource limits and tooling behavior — not language strictness.

:::note
Null safety, required type annotations, and narrowing `mixed` before use are unconditional language rules. There are no `checker.*` toggles that relax them.
:::

:::member[checker.templateStringMaxStates]
Type: `int` (default: `256`). Upper bound on template-string automaton complexity for subtyping/inclusion checks. When exceeded, the checker is conservative and emits a diagnostic.
:::

:::member[checker.maxFixIterations]
Type: `int` (default: `10`). Maximum auto-fix re-run iterations for `tyhp lint --fix`.
:::

## Tyhpdef Options

:::member[tyhpdefInclude]
Type: `array<string>`. Glob patterns for tyhpdef files to load. These files provide type information for existing PHP code, Composer packages, and PHP extensions. The `TyhpdefConfig` class default is `["**/*.tyhpdef"]`, but loading **clears** that list then reads `tyhp.json`. If you omit `tyhpdefInclude`, **no** project `.tyhpdef` files are loaded. `tyhp init` sets `["./vendor-tyhpdef/**/*.tyhpdef"]` so generated `--vendor` stubs load. Hand overlays belong in `"overlay"`, not this array. Entries in `include` that end in `.tyhpdef` or `composer.json` (with `extra.tyhp.package` present as an object) are also loaded as tyhpdefs.
:::

:::member[overlay]
Type: `array<string>` (default: `[]`). Glob patterns for overlay tyhpdefs loaded **after** `tyhpdefInclude` (last wins for the same Tyhp name). `tyhp init` sets `["./tyhpdef/**/*.tyhpdef"]`. Put lasting type fixes here — generated files under `vendor-tyhpdef/` are overwritten by `generate_tyhpdef --vendor`. See [Tyhpdef Overlays](tyhpdef_overlays.md).
:::

:::member[tyhpdefExclude]
Type: `array<string>` (default: `[]`). Glob patterns for tyhpdef files to exclude from loading.
:::

## CLI-Only Options

These options are only available as command-line arguments and override corresponding config file values.

:::member[--clean]
Wipe the output directory before building. Deletes all `.php` and `.php.map` files in the output directory. Safety checks prevent cleaning the project root or system directories.
:::

:::member[--verbose]
Enable detailed output during compilation. Shows per-phase timing, cache statistics, file counts, and memory usage.
:::

:::member[--dry-run]
Run the full compilation pipeline (parse, bind, check, emit) but do not write any output files. Reports what would be written.
:::

:::member[--strict]
Treat warnings as errors. The build fails if any warnings are produced, in addition to errors.
:::

:::member[--tyhp-project]
Specify the path to the `tyhp.json` project file. Overrides the default behavior of looking in the current working directory.
:::

:::member[--watch]
**Not in this alpha.** `tyhp build --watch` prints that watch mode is unimplemented, then runs a normal one-shot build.
:::

:::member[--fix]
On `tyhp lint`: apply auto-fixable diagnostic replacements (experimental). On `tyhp build`: write stale `extra.tyhp.require` pins onto root `require-dev` and Composer-update those packages (same as `tyhp composer sync`). Ordinary `tyhp build` never auto-updates Composer. See [CLI: Composer](cli_composer.md).
:::

## Lint-Specific Options

:::member[--format]
Output format for lint diagnostics. Supported values: `text` (default, human-readable), `json` (machine-readable), `sarif` (SARIF v2.1.0 for GitHub Code Scanning and similar).
:::

:::member[--file]
Lint a single file instead of the whole project. Still loads tyhpdefs and built-in types for full type checking.
:::

## Action-Specific Options

:::member[ext-name]
Type: `string`. Used with the `generate_tyhpdef` action. Specifies the PHP extension name to generate type definitions for (`--ext-name`). See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md).
:::

:::member[subject]
Type: `string`. Used with the `help` action. Specifies which action to display help for.
:::

## Complete Example

Below is a comprehensive `tyhp.json` showing all available options with their default values. In practice, you only need to specify the options you want to change from their defaults.

```json
{
    "type": "application",
    "quiet": false,
    "locale": "en-US",
    "suppressWarnings": [],

    "include": ["./src/**/*.tyhp", "./src/**/*.php"],
    "exclude": ["./src/legacy/**"],
    "source": {
        "tagless": false
    },

    "output": {
        "path": "./build",
        "publishPath": ".",
        "publishClean": false,
        "publishContent": [],
        "phpVersion": "8.2",
        "strictTypes": true,
        "namespacePrefix": null,
        "comments": true
    },

    "build": {
        "generateSourcemap": false,
        "sourcemapIncludeContent": false,
        "generateTyhpdef": false,
        "updateComposer": false,
        "structBacking": "array",
        "decimalBacking": "bcmath",
        "decimalScale": 28,
        "decimalRounding": "halfUp",
        "allowEval": false,
        "experimentalReadonlyCloneWith": false,
        "runtimeGenericChecks": false
    },

    "psr4": {
        "App\\": "src/"
    },

    "checker": {
        "templateStringMaxStates": 256,
        "maxFixIterations": 10
    },

    "tyhpdefInclude": ["./vendor-tyhpdef/**/*.tyhpdef"],
    "overlay": ["./tyhpdef/**/*.tyhpdef"],
    "tyhpdefExclude": []
}
```

A library that publishes per version can interpolate the root `composer.json` identity (add `"version"` if `tyhp init` did not write it):

```json
{
    "type": "library",
    "include": ["./src/**/*.tyhp"],
    "output": {
        "path": "./publish/{version}/src",
        "publishPath": "./publish/{version}",
        "phpVersion": "8.4",
        "publishContent": [
            { "src": "README.md" },
            { "src": "docs/**/*.md", "dst": "{recursiveDir}/{fileName}" }
        ]
    }
}
```
