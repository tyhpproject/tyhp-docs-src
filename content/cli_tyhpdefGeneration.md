---
title: 'CLI: Tyhpdef Generation'
status:
  tier: 2
  story: '20'
  state: complete
---

The `generate_tyhpdef` action produces `.tyhpdef` type definition files that describe the type signatures of external PHP code — similar to TypeScript's `.d.ts` files.

Library projects also emit `package.tyhpdef` during `tyhp build`. That is **not** this verb; see [Auto-generation during build](#auto-generation-during-build) and [CLI: Build](cli_build.md).

## Usage

```
tyhp generate_tyhpdef [options]
```

Exactly one of `--ext-name`, `--package-path`, `--source`, or `--vendor` is required, **except** when you only pass `--validate` to parse-check existing files, or `--audit-stubs` to report Layer 2 vs stub corpora.

```
tyhp generate_tyhpdef --ext-name=curl
tyhp generate_tyhpdef --ext-name=curl --php-version=8.3
tyhp generate_tyhpdef --ext-name=myext --php=/opt/php/bin/php
tyhp generate_tyhpdef --package-path=./vendor/guzzlehttp/guzzle --output=./tyhpdef/
tyhp generate_tyhpdef --vendor
tyhp generate_tyhpdef --vendor=/path/to/vendor
tyhp generate_tyhpdef --source=./lib/**/*.php --split=namespace
tyhp generate_tyhpdef --validate ./tyhpdef/
tyhp generate_tyhpdef --audit-stubs=runtime/packages/php/_tyhpdef --out=stub-audit.md
tyhp generate_tyhpdef --ext-name=curl --php-targets=8.2,8.3,8.4,8.5
tyhp generate_tyhpdef --help
```

## Generation modes

| Flag | Mode | How it works | Status |
|------|------|----------------|--------|
| `--ext-name=<name>` | PHP extension | Reflection; PHP required (Tyhp-managed PHP or `--php`) | Shipped |
| `--package-path=<dir>` | Composer package (`composer.json` autoload) | Parses PHP files; no PHP runtime | Shipped |
| `--source=<glob>` | PHP source files (`.php` only) | Parses PHP files; no PHP runtime | Shipped |
| `--vendor[=<dir>]` | Installed Composer tree + root `ext-*` | Companions preferred; otherwise generates stubs | Shipped; writes `vendor-tyhpdef/` |
| `tyhp build` | Compiled Tyhp public API | Emits `package.tyhpdef` (and additive-merges `extra.tyhp.package` on `composer.json` for libraries) | Shipped on `tyhp build`, not this verb |

`--package-path` is the Composer flag. There is no `--composer-package` alias. `--vendor` scans `vendor/composer/installed.json` (Composer 2) plus `ext-*` keys on the root `composer.json`.

### Combining flags

- `--no-php` with `--ext-name` is an error (`TYHP7501`). `--no-php` is ignored for `--source` / `--package-path`.
- `--php` cannot be combined with `--php-targets` (`TYHP7510`).
- `--php-targets` is only valid with `--ext-name`. With `--source` or `--package-path` it is an error.
- `--source` accepts `.php` files only. A `.tyhp`, `.tyhpdef`, or any other path is `TYHP7507` (`TyhpdefSourceNotPhp`). Generate Tyhp APIs with `tyhp build`, or compile then run `--source` / `--package-path` on the emitted PHP.
- `--vendor` cannot be combined with `--ext-name`, `--package-path`, or `--source`. It always writes to `{projectRoot}/vendor-tyhpdef/` (`--output` / `--output-file` do not redirect it).

## PHP runtime for `--ext-name`

Default is **Tyhp-managed PHP**: download + cache + isolated `php -n -c tyhp.ini`. Tyhp does **not** search `PATH`, a local Homebrew install, or `PHP_BINARY`.

Unix/macOS artifacts: [StaticPHP](https://static-php.dev) prebuilt `php` first; Homebrew **bottles** (direct GHCR download, no `brew` command) as fallback. Windows uses official NTS zips from windows.php.net. Credits: [`THIRD_PARTY.md`](https://github.com/tyhpproject/tyhp/blob/main/THIRD_PARTY.md).

- `--php=<path>` — single-target escape hatch (the binary’s own ini; no `-n`). Use this for custom / private extensions or an unknown config. Output is **ungated**.
- `--php-targets=<list>` — reflect each listed minor with **managed** runtimes only (comma-separated, e.g. `8.2,8.3,8.4,8.5`) and emit one gated tree. Illegal with `--php`.
- `--php-runtime-dir=<dir>` — override the managed cache (`TYHP_PHP_RUNTIME_DIR`).
- `--php-version=<version>` — target PHP version string for output metadata.
- `--no-php-runtime-update` — skip managed PHP patch auto-update.
- `--refresh-snapshots` — re-reflect even if PHP snapshots already exist under `tyhpdef_gen/snapshots/`.

Missing managed runtime is `TYHP7501` / `TYHP7508`. Checksum mismatch is `TYHP7509`. A managed runtime that cannot load `--ext-name` is `TYHP7511`; a user binary missing the extension is `TYHP7500`. Patch auto-update failure is warning `TYHP7512` (last-known-good runtime is used).

Cache layout: `{LocalApplicationData}/Tyhp/php-runtimes/{rid}/{major.minor}/{patch}/`. Each cache directory has `ATTRIBUTION.txt`. Manual comments cache under `{LocalApplicationData}/Tyhp/php-manuals/{locale}/` unless `--no-docs`.

Layer 1 output is `{projectRoot|cwd}/tyhpdef/Ext{Name}.tyhpdef` (or `--output` / `--output-file`).

### Multi-target gated output

`tyhp generate_tyhpdef --ext-name=curl --php-targets=8.2,8.3,8.4,8.5` provisions each minor via `PhpRuntimeManager` (download / patch-update / isolated ini), writes Reflection JSON under `{projectRoot}/tyhpdef_gen/snapshots/{minor}/`, diffs the surfaces, and emits **one** Layer 1 tree:

- Identical across every listed minor → ungated declaration
- Added at version V → `declare(php=">=V") { … }` for whole functions/files/structs/extensions, or `#[\Tyhp\Php(">=V")]` on members of a shared class
- Signature changed at V → version-disjoint declarations (constraints do not overlap)
- Removed after V → upper-bound constraint (`<` the next listed target)

If any listed minor cannot be provisioned, the run fails and nothing is merged. Snapshots are reused on later runs unless you pass `--refresh-snapshots`. Regen overwrites Layer 1 and `overlays/stubs/`; it does not touch hand-written `overlays/*.tyhpdef`. Layer 2 harvest does not write a stub overlay that contains no declarations (empty `partial class` files are omitted). Untyped PHP parameters are emitted as `mixed`. Untyped return types are emitted as `mixed`, except constructors and destructors which are emitted as `: void`. Reflection does not invent missing parameters (for example `Closure::__invoke`); those go in an overlay.

`--php` is the ungated escape hatch for a **private unpublished** extension (or an unknown PHP config). Do not combine it with `--php-targets` (`TYHP7510`). For published `tyhpdef/php` / `tyhpdef/php-ext-*` packages, use `--php-targets` so one tree covers 8.2–8.5.

Lint or build the same tree at each `output.phpVersion` in the 8.2–8.5 matrix to confirm the expected APIs are visible. You do not install four PHP versions for that check — gates are evaluated against `output.phpVersion`.

## PHP source (`--source` / `--package-path`)

No PHP runtime. `--package-path` reads that package’s `composer.json` `autoload` and collects the listed PHP files. `--include-dev` also reads `autoload-dev`. Tyhp does **not** use PHP Reflection for vendor packages.

`--source` is glob(s) of `.php` files only (`TYHP7507` otherwise).

Harvested signatures are tyhpdef text, not a splice of the PHP source. See [Harvested types, defaults, and attributes](#harvested-types-defaults-and-attributes).

Unqualified names in PHPDoc and native hints that have no `use` import are rewritten to a catalog FQCN when that short name is unique among PHP builtins (`php` / `ext-*` wrappers) and unique `\Psr\*` types (`DateTime` → `\DateTime`, `CacheItemPoolInterface` → `\Psr\Cache\CacheItemPoolInterface`), or to a same-package FQCN when that type is declared in the same harvest. In native `extends` / `implements` / trait `use`, an unqualified or single-segment `\Short` name that matches a type declared in the same harvest qualifies to that FQCN even when the short is a unique PHP / `\Psr\*` global (`implements Exception` → `\Acme\Exception\Exception`). A true global the package does not declare (`extends \InvalidArgumentException`) stays global. A colliding short (`Builder`) stays as written. Composer-library class names are not unique globals. The same rewrite walks identifiers inside generics, unions, and intersections — including `@template T of SomeType<…>` bounds. Template parameters (`T`) and builtins stay unqualified. Intra-package unique-short qualification of remaining unqualified names runs **after** omitted types are dropped; see [Omitted types](#omitted-types). See [Harvested types, defaults, and attributes](#harvested-types-defaults-and-attributes).

### Optional peers (`externs.tyhpdef`)

After emitting this package's own types, generation classifies remaining foreign signature names against a catalog of existing `tyhpdef/*` packages (in-repo `runtime/packages`, or other catalog roots). The catalog indexes **real** `class` / `interface` / `enum` declarations only — another package's `extern` does not count as providing the type. Catalog hits emit `extern` with that catalog kind (`extern class` / `interface` / `enum`) so the placeholder matches the originating declaration. A hand-written specified kind that disagrees is `TYHP8029`. When indexing those files, `{` and `}` inside `/** */`, `/* */`, `//`, and quoted strings are not namespace delimiters. Classification uses the **PHP** package's `composer.json` (`require` / `suggest` / `require-dev` / `ext-*`), not the wrapper's own manifest.

| Condition | Result |
|-----------|--------|
| Catalog hit, providing PHP package / `ext-*` is in the target **`require`** | No `extern`. Add or keep a `require` of that `tyhpdef/*` on the wrapper. Generate required wrappers first. |
| Catalog hit, providing package is in target **`suggest`** or **`require-dev`** (not `require`) | Emit `extern` with the catalog kind (`extern class` / `interface` / `enum`) and `// @provided-by: tyhpdef/…`. Do not `require` that wrapper. |
| Catalog miss, or the providing package is in none of those three | Leave the name unresolved (`TYHP3019` / `TYHP3020`). No namespace guess. |
| Unqualified name | Leave as written. Never auto-`extern`. |
| Generated type `extends` / `implements` a name that would be `extern` | **Omit** that generated type and warn. Descendants of an omitted type are omitted too; members that still name an omitted FQCN are stripped. |

A required PHP package / `ext-*` with no catalog wrapper is a CLI warning. Those types stay unresolved; generation does not `extern` a required dependency.

Proven optional-peer declarations are written to **`externs.tyhpdef`** in the output directory (for first-party wrappers, `_tyhpdef/externs.tyhpdef`). The file has an `AUTO-GENERATED` header. Regen **overwrites this file only** (or deletes it when the run classified and produced none). `extra.tyhp.package` `"include"` glob `./_tyhpdef/*.tyhpdef` already loads it. Hand `extern` belongs in a sibling include file regen does not overwrite.

`--source` classifies only when the tree is package-shaped (`composer.json` with `autoload`). Default file set stays Composer `autoload` only; do not turn on `--include-dev` for published wrappers.

See [Extern Types](tyhpdef_extern.md).

### Omitted types

PHP-source harvest (`--package-path` / `--source`) omits a type when its immediate `extends` / `implements` is a catalog `extern` (the providing package is only `suggest` or `require-dev`, not `require`), or when the type is `@internal` and `--include-internal` is off. Harvest then:

1. **Cascades the omit** through descendants that `extends` / `implements` an omitted type.
2. **Strips members** (and trait `use` / functions / aliases) whose types **actually refer** to an omitted FQCN — including `use` imports and already-qualified harvest names.
3. A **bare PHPDoc name** (no import, left as written) is **not** treated as a reference to an omitted type in a **different** namespace just because the last segment matches. Unqualified omit matching is current-namespace only.
4. Intra-package unique-short qualification runs **after** omit, so it cannot rewrite a bare PHPDoc name onto a now-omitted type.

`--include-internal` keeps `@internal` types and members that refer to them.

### Repeated FQCNs

PHP-source harvest (`--package-path` / `--source`, including `--vendor` stubs from those modes) emits the first `class` / `interface` / `trait` / `enum` for a fully-qualified name. When a later declaration of that FQCN has an **identical** body — kind, modifiers, `extends` / `implements`, members, and flags; **not** doc comments — generate keeps the first, skips the later, and warns.

When the bodies **differ**, both declarations stay in the output. Include-layer `TYHP8002` still reports the duplicate.

### Anonymous-class returns

A PHP `return new class { … }` (and the same expression in Tyhp) is harvested as an object-shape alias, not as `object`. The generator invents a collision-safe name in the same namespace (`createClock_Return`, or `OwningType_method_Return`, with a numeric suffix on collision) and uses that alias as the function or method return type (or as a union arm). Public instance members and a `__construct` signature (when present) are copied; private members are omitted. If the anonymous class `extends` / `implements` real types, the alias right-hand side is those nominal types intersected with `object { … }`. The anonymous class itself is still skipped as a named PHP class (`anonClass@` is not written).

`__FunctionReturnType<'createClock'>` / `__MethodReturnType<Plugin, 'parseConstraint'>` recover that harvested shape when the author did not pick a nicer alias. Hand overlays may `omit` the generated alias and last-wins replace the callable return.

See [Object Shapes and `__New<T>`](tyhp_3400_newTypeConstraint.md).

### Conditional declarations

PHP-source harvest turns a few top-level conditions into tyhpdef gates. Other `if` bodies are skipped.

| PHP | Emitted tyhpdef |
|-----|-----------------|
| `if (!function_exists(name)) { function name … }` | `fallback function` |
| `if (!defined('NAME')) { define('NAME', …); }` | `fallback const` |
| `if (extension_loaded('intl')) return;` | Following declarations are wrapped in `declare(ext="!intl")` |
| `if (!extension_loaded('intl')) return;` | Following declarations are omitted |
| `if (function_exists(…)) return;` or `if (defined(…)) return;` | Following declarations are `fallback` |
| `if (PHP_VERSION_ID >= 80300) return require 'other.php';` | This file's later declarations use `declare(php="<8.3")`. `other.php` uses `declare(php=">=8.3")` |

A declaration can carry more than one of these. `declare(php=…)` and `declare(ext=…)` nest. See [Fallback functions](tyhpdef_functions.md#fallback-functions) and [Extension presence](tyhp_0320_phpVersionGating.md#extension-presence).

## `--vendor` (installed Composer packages)

Scan the project's installed Composer packages and root `ext-*` requirements, prefer published Tyhp companions, and otherwise generate stubs into **`vendor-tyhpdef/`**. `tyhp init` wires this as the second `post-autoload-dump` command. `tyhp composer require` / `install` / `update` (success, without `--no-tyhpdef`) runs the same mode.

```
tyhp generate_tyhpdef --vendor
tyhp generate_tyhpdef --vendor=/path/to/vendor
```

Bare `--vendor` uses `{projectRoot}/vendor`. The directory must contain Composer 2 `vendor/composer/installed.json` (`TYHP7516` / `TYHP7517` if missing or invalid). Inventory comes from that file, not from walking `vendor/*/*`. Root `composer.json` `require` / `require-dev` keys named `ext-*` are included (platform extensions are not in `vendor/`).

Skip the root package, `php`, `tyhp/compiler`, and packages with no autoloadable `.php`. Extensions already covered by `tyhpdef/php` (Core, date, filter, hash, json, libxml, pcre, random, Reflection, SPL, standard) are not regenerated.

### Companions vs generated stubs

For each installed library `vendor/name`, the companion Composer name is **`tyhpdef/<vendor>-<name>`** (`/` → `-`, for example `monolog/monolog` → `tyhpdef/monolog-monolog`). For `ext-<name>`, the first-party package is **`tyhpdef/php-ext-<name>`**.

| Situation | What happens |
|-----------|----------------|
| Install path already has `extra.tyhp.package` on `composer.json` | Skip generate (the binder loads that package from `vendor/`) |
| Companion / `tyhpdef/php-ext-*` already installed | Skip generate; **delete** any previously generated stub for that library or extension |
| Published companion exists but is not required | Add it to root `require-dev` and install, then skip generate |
| Otherwise | Generate `--package-path` or `--ext-name` stubs into `vendor-tyhpdef/` |

`--vendor` also adds missing compiled runtime packages to root **`require`** as **`@dev`** when they are not already named: `tyhp/core`, `tyhp/async`, `tyhp/lambda`, `tyhp/decimal`. Missing `tyhpdef/php` and first-party `tyhpdef/php-ext-*` packages go in **`require-dev`** as `@dev`. It does not overwrite an existing pin.

A single package or extension failure is warning `TYHP7518` (or `TYHP7519` if a Composer require batch fails); the rest of the run continues. The command is an error (`TYHP7520`) only when every candidate failed.

### Output: `vendor-tyhpdef/`

```
vendor-tyhpdef/<vendor>.<package>.tyhpdef
vendor-tyhpdef/ExtCurl.tyhpdef
```

`--vendor` does not write into `tyhpdef/` or into `vendor/`. Unchanged package+version identities are skipped unless you pass `--overwrite`. `tyhp init` gitignores `vendor-tyhpdef/` and sets `"tyhpdefInclude": ["./vendor-tyhpdef/**/*.tyhpdef"]`.

Every generated file starts with a header that says not to edit it. Re-running `--vendor` overwrites those files. Lasting type fixes belong in **overlay** tyhpdefs (`tyhp.json` `"overlay"`, default `./tyhpdef/**/*.tyhpdef` after init; or `tyhp overlay create`). See [Tyhpdef Overlays](tyhpdef_overlays.md).

### Composer hooks and opt-out

Root `post-autoload-dump` (written by `tyhp init`) runs `--install-binary` then `generate_tyhpdef --vendor`. Set **`TYHP_NO_VENDOR_TYHPDEF=1`** (also `true` or `yes`) to skip that generate step when Composer is running the dump script, and to skip the same generate after `tyhp composer` `require` / `install` / `update`. Direct `tyhp generate_tyhpdef --vendor` still runs. `--no-tyhpdef` on `tyhp composer` skips the proxy hook only; it does not apply to a direct `--vendor` invocation.

## Layer 1 and Layer 2

- **Layer 1** — Reflection baseline (`--ext-name`) or parsed PHP signatures (`--source` / `--package-path`). Written as the primary `.tyhpdef`.
- **Layer 2** — stub harvest into generated overlay files under `{output}/overlays/stubs/*.tyhpdef` when a stub cache or vendored snapshot is present. Never mixed into the Layer 1 file.

`--require-stubs` (default **off**) makes a missing Layer 2 stub cache an error (`TYHP7514`). Without it, a missing cache is warning `TYHP7513` and harvest is skipped. Psalm vs PHPStan type disagreement is warning `TYHP7515` (Layer 1 type is kept). Class-level `@template` lists are unified **by position** across corpora (PHPStan names win when present) so synonym placeholders such as `TArrayValue` / `TData` / `TValue` become one parameter. An explicit constraint becomes both the Tyhp `extends` bound and the default; `@template T of mixed` emits `T = mixed` with no bound; an unconstrained parameter has neither. When a defaulted parameter would be followed by a required one, trailing unconstrained parameters receive `= mixed` so the list is legal Tyhp. Harvest applies `@implements` / `@extends` type arguments onto the Layer 1 parent names when the parent is already listed and the argument count matches that parent's harvested generic arity in the same run (unknown parents from another extension keep the stub arity). Changing a type's generic list or inheritance header is overlay `partial class Foo<…> implements …;` (header-only); changed members are a separate `partial class Foo { … }` in the same stub overlay. If a conventional placeholder would still be undeclared, harvest does not write the overlay (`TYHP7521`). A Layer 2 declaration is omitted when the harvested signature matches Layer 1 (doc-comment hole-fill alone does not produce an overlay). `tyhp generate_tyhpdef --audit-stubs=<tree>` reports how committed Layer 2 compares to those corpora (consensus and harvest faithfulness) without regenerating files.

Stub corpora are fetched into a gitignored cache (`tools/stub-cache/`). URLs and credit live in `runtime/README.md` and [`THIRD_PARTY.md`](https://github.com/tyhpproject/tyhp/blob/main/THIRD_PARTY.md). Generated overlay trees may include a `SOURCES.md`.

Hand-written overlays load last at bind time. `--verify` **applies** overlays when comparing final forms (see below). See [Tyhpdef Overlays](tyhpdef_overlays.md).

## Default output

- With a project (`tyhp.json`): `{projectRoot}/tyhpdef/`
- Without a project: `{cwd}/tyhpdef/`
- `--output=<path>` overrides the directory
- `--output-file=<path>` writes a single file (relative paths resolve against the output directory unless absolute)
- `--vendor` always writes `{projectRoot}/vendor-tyhpdef/` (see above)

`tyhp build` never writes here. It emits `package.tyhpdef` (and additive-merges `extra.tyhp.package` on `composer.json` for libraries) in the publish directory.

### `--split` layout

Default is `file`: one `.tyhpdef` per generation target, flat under `tyhpdef/`.

| Mode | Result |
|------|--------|
| `file` (default) | Extension: `tyhpdef/ExtJson.tyhpdef`. Composer package: `tyhpdef/guzzlehttp.guzzle.tyhpdef`. `--source`: `tyhpdef/source.tyhpdef` unless `--output-file`. |
| `namespace` | One file per namespace (`tyhpdef/GuzzleHttp.Client.tyhpdef` style; globals on the primary file or `_global.tyhpdef`). |
| `type` | One file per class/interface/trait/enum. Useful for huge Composer packages; do not use it for `--ext-name=standard`. |

Layer 2 always lands in `tyhpdef/overlays/stubs/*.tyhpdef`.

## Documentation comments

Docs are **on** unless `--no-docs`.

- `--ext-name` builds `/** */` from the **php.net HTML manual** (`--locale`, default `en`). `--no-docs` also skips the manual download.
- `--source` / `--package-path` and `tyhp build` **copy** comments from source and apply tyhpdef adjustments. Copied PHP-source summary, description, and tag lines replace `*/` with `* /` so they cannot close the `/** */`.
- Stubs **fill remaining holes** (and remain the extra **type** source).

## Harvested types, defaults, and attributes

`generate_tyhpdef` writes expressions the tyhpdef parser can read. PHP-source harvest (`--source` / `--package-path`) and Layer 2 stub types use the same rewrite; parameter `=` values and attributes are sanitized again when the file is written (including `--ext-name`).

**Types.** PHPDoc `callable(...)` and `closure(...)` shapes become `callable`. Psalm/PHPStan `empty` in a type position becomes `mixed`. A type that still has unmatched `()` `{}` `[]` `<>` is emitted as `mixed`. The PHP `empty()` construct is unchanged: it types as `bool` and emits as `empty(...)`. PHP `static` in a value position — a parameter, property, `@param`, `@var`, magic `@method` parameter, or `@property` — is written as `self`. Return positions keep `static` (`: static`, magic `@method` return types, including generic arguments such as `Builder<static>`). Unqualified class names inside PHPDoc type strings — `@template T of Foo<object>`, unions, intersections, and other generics — resolve to FQCNs from `use` imports, those unique PHP / `\Psr\*` shorts, and types declared in the same package. Native `extends` / `implements` / trait `use` prefer a same-package declared type over a unique PHP / `\Psr\*` short of the same name (`implements Exception` → `\Acme\Exception\Exception`); a true global the package does not declare (`extends \InvalidArgumentException`) stays global. Template parameters (`T`) and builtins (`object`, `int`, `mixed`, …) stay unqualified. When a generic bound is written without type arguments (`@template T of Repository` and `Repository` is itself generic), harvest fills the missing arguments from that type's own default, else its constraint, else `mixed` (`Repository<TEntity extends object>` → `Repository<object>`; unconstrained `Box` → `Box<mixed>`). Already-written arguments are kept.

**Declared names.** A harvested `class` / `interface` / `trait` / `enum` whose short name is a PHP or tyhpdef reserved word (`is`, `isset`, …) is written with a fully-qualified declared name (`class \Hamcrest\Core\Is`) so the parser treats it as a name rather than a keyword. Alias headers (`class PhpName as TyhpName`) and `extern function` names inside a `namespace { }` use the same enclosing-namespace prefix. See [Reserved-word type names](tyhpdef_classes.md#reserved-word-type-names).

**Defaults and `??`.** Parameter `=`, property `??`, and const `??` keep a value when it is already a single-line tyhpdef expression: a quoted string, a number (including `0x` / `0b` / `0o`), `true` / `false` / `null` / `[]`, or `Class::CONST`. Concatenation, nowdocs, heredocs, `/regex/` bodies, interpolations, multiline text, leftover `$this`, unquoted source, and unmatched delimiters are not copied.

A harvested parameter that had a PHP default stays optional. When that default is not a tyhpdef-safe literal, generate writes `= null` — the same dummy used for harvested implicit-nullable PHP (`string $timezone = null`). The declared type is unchanged (`int` stays `int`; it is not rewritten as `int|null`). Const and property values omit an unrepresentable `??` initializer (`const string NAME;`, `public string $text;`). Restore a specific start value in a [hand overlay](tyhpdef_overlays.md) if you need it.

**Attributes.** If the whole `#[Name(args)]` is unmatched, generate writes `#[Name]`.

## `--validate`, `--verify`, and `--audit-stubs`

| Flag | What it does |
|------|----------------|
| `--validate=<path>` | Parse-check existing `.tyhpdef` files (file or directory). Non-zero if any fail. Can run **alone** (no `--ext-name` / `--package-path` / `--source` / `--vendor`). |
| `--verify` | Regenerate Layer 1, apply overlays (`extra.tyhp.package` `"overlay"` array, or `overlays/stubs` then `overlays/*.tyhpdef`), and check that the **final** API covers PHP. Requires a generation mode. |
| `--audit-stubs=<path>` | Compare committed Layer 1 and Layer 2 (`overlays/stubs/`) with Psalm, PHPStan, PhpStorm, and Phan. Writes a markdown report (stdout, or `--out=<file>`). Does **not** regenerate files. Exit 0 unless the path or stub cache is missing. Cannot combine with a generation mode. |

`--verify` overlay rules:

- Fully **missing** golden PHP symbols → fail (`TYHP7506`).
- Symbols **`omit`ted by an overlay** → **not** a fail (intentional hide).
- Extra overlay-only members are allowed.
- Compatible generics/overloads/structs that still cover the PHP signature pass.

`--verify` is a generator check, not a substitute for compile-time overlay load. Overlay load in the binder is documented in [Tyhpdef Overlays](tyhpdef_overlays.md).

`--audit-stubs` is a **report**, not a gate. php.net is not the oracle for generics — Layer 1 already comes from Reflection / the manual. The audit compares Layer 2 to the stub corpora (the same sources harvest uses) and to what harvest would have written:

| Bucket | Meaning |
|--------|---------|
| `agree` | Layer 2 matches harvest, or neither side refined Layer 1 |
| `psalm-phpstan-disagree` | Psalm and PHPStan both typed this and differ (harvest keeps Layer 1) |
| `template-arity-mismatch` | Psalm and PHPStan declare a different number of `@template` parameters |
| `template-order-mismatch` | Same template names in a different order (for example Fiber) |
| `faithfulness-mismatch` | Layer 2 wrote a type that is not the harvest consensus |
| `one-corpus` | Only one corpus supplied a non-weak type |
| `not-in-layer-2` | Harvest would refine a weak Layer 1 type, but Layer 2 does not |
| `layer-2-no-stub` | Layer 2 has a signature with no matching stub symbol |

The path is a tyhpdef tree (`…/_tyhpdef`), a package directory that contains `_tyhpdef/`, or `…/overlays/stubs`. Layer 3 hand overlays are not part of this comparison. Missing stub cache is `TYHP7514` (the audit always requires stubs; it will fetch `tools/stub-cache/` when needed).

## Options

- `--help` — Show this help (same as `help --subject=generate_tyhpdef`).
- `--ext-name=<name>` — PHP extension to reflect.
- `--package-path=<path>` — Composer package directory (`composer.json` autoload).
- `--source=<glob>` — PHP source globs. `.tyhp` / `.tyhpdef` / non-`.php` paths are `TYHP7507`.
- `--vendor[=<dir>]` — Scan Composer `vendor/` (default `{projectRoot}/vendor`) and write stubs to `vendor-tyhpdef/`. Exclusive with the other generation modes.
- `--output=<path>` — Output directory (default `tyhpdef/`). Ignored for `--vendor`. `tyhp build` never writes here.
- `--output-file=<path>` — Single output file (relative paths resolve against `--output`).
- `--split=file\|namespace\|type` — CLI `tyhpdef/` layout (default `file`).
- `--php=<path>` — User PHP binary for `--ext-name` (single-target escape hatch; illegal with `--php-targets`).
- `--php-targets=<list>` — Managed PHP minors, comma-separated. Emits one gated tree (`declare(php=…)` / `#[\Tyhp\Php]`). Illegal with `--php` (`TYHP7510`). Only valid with `--ext-name`.
- `--php-runtime-dir=<dir>` — Managed PHP cache override (`TYHP_PHP_RUNTIME_DIR`).
- `--php-version=<version>` — Target PHP version string for output metadata.
- `--include-dev` — Also collect Composer `autoload-dev` (with `--package-path` or `--vendor`).
- `--locale=<locale>` — php.net manual language for `--ext-name` (default `en`).
- `--no-docs` — Skip `/** */` (`--ext-name` also skips the manual download).
- `--include-internal` — Include `@internal` items (off by default). Without it, PHP-source harvest omits those types, descendants that `extends` / `implements` them, and members that name them. With it, those types and their references stay. See [Omitted types](#omitted-types).
- `--include-deprecated` / `--no-deprecated` — Deprecated items (on by default).
- `--overwrite` — Overwrite existing tyhpdef files.
- `--require-stubs` — Missing Layer 2 stub cache is an error (off by default).
- `--no-php` — Error with `--ext-name`; ignored for `--source` / `--package-path`.
- `--no-php-runtime-update` — Skip managed PHP patch auto-update.
- `--refresh-snapshots` — Re-reflect even if PHP snapshots already exist.
- `--validate=<path>` — Parse-check existing `.tyhpdef` files.
- `--audit-stubs=<path>` — Layer 2 vs stub-corpus report (markdown to stdout or `--out`).
- `--out=<file>` — Write the `--audit-stubs` report to a file instead of stdout.
- `--verify` — Overlay-aware check of the final API against PHP (`omit` is not a fail).

## Auto-generation during build

Not a `generate_tyhpdef` flag. After check and before optimize/emit:

| Project `"type"` | `build.generateTyhpdef` | Output (in `output.publishPath`, default: the project root) |
|------------------|-------------------------|--------------------------------------------|
| `"library"` | **Ignored** | Always `package.tyhpdef` **and** `extra.tyhp.package` on `composer.json` |
| `"application"` | `true` | `package.tyhpdef` only (no `extra.tyhp.package`) |
| `"application"` | `false` / unset | Nothing |

If `extra.tyhp.package` already exists on publish-directory `composer.json`, the build adds missing generated keys and array items only. Existing entries are not removed or changed.

```json
{
    "type": "application",
    "build": {
        "generateTyhpdef": true
    }
}
```

The build walks bound Tyhp symbols (not a CLI parse of `.tyhp` into `tyhpdef/`). Libraries with executable entrypoint files report `TYHP7505` and skip writing artifacts. `tyhp build` emits name-only `extern` (including `extern function` / `extern const`) into `package.tyhpdef` for names owned by a `require-dev` package that is not also in `require` or `extra.tyhp.require`, with `// @provided-by: <owning package>`. Runtime `require` owners (for example `tyhp/core`) and `extra.tyhp.require` owners stay FQNs and are not copied. Unknown origin is left as written. Symbols marked `internal` are omitted from `package.tyhpdef` (the same as `private`). Optional-peer placeholders for PHP packages still come from `--source` / `--package-path` (`_tyhpdef/externs.tyhpdef`); see [Extern Types](tyhpdef_extern.md) and [The internal Visibility Modifier](tyhp_3100_internalModifier.md). Library authors declare ambient tyhpdefs in `extra.tyhp.require`; see [Composer Runtime Packages](project_composerPackages.md#ambient-tyhpdefs-extratyhprequire).

Authored `type Name = object { … }` aliases are copied into `package.tyhpdef`. Functions and methods that `return new class { … }` get a generated shape alias as the return type, the same way PHP-source harvest does; see [Anonymous-class returns](#anonymous-class-returns).

Standalone Tyhp `extension { }` becomes a PHP backer class (`class PhpName as Name__tyhpExtensionBacker`) plus a tyhpdef `extension Name { }` with short `=>` mappings. File-level `use` / `use extension` is not copied. In-package `global use` / `global use extension` that the library authored is written into `package.tyhpdef` (FQNs, including `hide` / `insteadof` / `as`). Libraries that did not author `global use` stay opt-in for consumers. See [Extensions in Tyhpdef](tyhpdef_extensions.md) and [Extensions](tyhp_2100_extensions.md).

Generated `package.tyhpdef` copies declaration attributes that are part of the Tyhp contract (`#[\Attribute(…)]`, `#[\Tyhp\NoEmit]`, `#[\Tyhp\PhpType]`, `#[\Tyhp\AllowUnset]`, `#[\Tyhp\Optimize\Pure]`, and user attributes). `#[\Tyhp\Php]` is omitted when the gate is already a `PhpGate`. Every emitted generic class, method, and function is stamped `#[\Tyhp\GenericRuntime(erased: …, layouts: [1], compiler: …)]` (`factory` / `binder` only when helpers exist; `aliasFactory` is unchanged). `GenericRuntime` is a real PHP attribute (not `NoEmit`). PHP builtin and overlay tyhpdefs that declare generics or aliases without that stamp keep erase / inline emit. Consumer Tyhp emits `\Tyhp\Generic::bind` for stamped foreign sites; empty intersection with this compiler's layouts is `TYHP5023`.

## Hooked properties

Generated tyhpdefs emit hooked properties as bodyless lists (`{ get; set; }`, `{ &get; }`, `private set`, and so on). Bodies are never copied.

- **`tyhp build`:** when a Tyhp property has hooks, the generated tyhpdef includes that hook list. The generator does **not** add `#[\Tyhp\Php(">=8.4")]` — Tyhp’s 8.2–8.3 polyfill is the contract for those libraries.
- **`generate_tyhpdef`:** hooks exist in the PHP engine from 8.4. A single-target run emits what that PHP has (hooked or storage). With `--php-targets`, if hook shape differs across minors (storage on 8.2/8.3, hooked on 8.4+), the merge emits version-disjoint members — a gated storage form and a gated hooked form — the same way it splits a method that gained a parameter. If every target agrees, it emits one declaration.

## Related diagnostics

`TYHP7500`–`TYHP7520` cover generation, managed PHP, stubs, `--verify`, and `--vendor`. Include-layer `TYHP8002` still fires when harvest writes two divergent bodies for the same FQCN; see [Repeated FQCNs](#repeated-fqcns). Optional-peer `extern` diagnostics (`TYHP4307`, `TYHP3026`, `TYHP3027`, `TYHP8028`–`TYHP8030`) are documented in [Extern Types](tyhpdef_extern.md) and the [Diagnostic Code Reference](diagnostics_reference.md).
