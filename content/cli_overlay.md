---
title: 'CLI: Overlay'
status:
  tier: 2
  story: '21'
  state: complete
---

The `overlay` action copies a tyhpdef declaration into a **hand-written** overlay file and writes `// @overlay-against:` stamps that record the Layer 1 baseline the overlay was written against.

Overlays themselves — `include` vs `overlay`, last wins, brace `partial`, header-only `partial class Foo<T>;`, overlay `partial function`, `omit` — are documented in [Tyhpdef Overlays](tyhpdef_overlays.md).

## Usage

```
tyhp overlay create <FQN>
tyhp overlay stamp
tyhp overlay stamp <FQN>
```

```
tyhp overlay create \Iterator
tyhp overlay stamp
tyhp overlay stamp \Iterator
tyhp overlay --help
```

## `create <FQN>`

Looks up the fully-qualified Tyhp name in the current compilation (after overlays already in the package have been applied) and copies that declaration into a hand-written overlay file under `_tyhpdef/overlays/` (not `overlays/stubs/`).

Use this (or a file under the project `"overlay"` glob, `./tyhpdef/**/*.tyhpdef` after `tyhp init`) for lasting fixes to types that `--vendor` generated into `vendor-tyhpdef/`. Do not edit those generated files.

- If the overlay file already exists, the declaration is appended.
- If that package’s `composer.json` has `extra.tyhp.package`, `create` appends the hand-written overlay glob at the **end** of `extra.tyhp.package.overlay` when it is not already listed. It never inserts that glob before stub entries.
- Missing FQN is `TYHP7901`. An `extern` type is `TYHP7904` (create is for replacing a real declaration; it does not copy the placeholder into a hollow `class { }` overlay). Invalid extra arguments are `TYHP7900`. Write / manifest failures are `TYHP7903` / `TYHP7902`.

## `stamp` [`<FQN>`]

Rewrites `// @overlay-against:` comments on **stub and hand-written** overlay files from the **Layer 1** baseline (include, overlays not applied). With an FQN, only that declaration is stamped; without one, every overlay file is stamped. Stamping an `extern` declaration is a no-op.

Stamp runs one pass per PHP version Tyhp manages (8.2, 8.3, 8.4, and 8.5 today; a later version is included when it is added to that managed set). Each pass downloads or reuses the managed PHP runtime for that version — the same cache as `generate_tyhpdef`, with its own ini, separate from whatever `php` is on `PATH` — and binds Layer 1 at that runtime's full version. A declaration is stamped on a pass when its `declare(php=…)` and `#[\Tyhp\Php(…)]` gates are satisfied by that version. Constraints use the same Composer syntax as the compiler (`>=8.4`, exact `8.3`, and the other forms the compiler already parses). A declaration with neither gate is stamped on every pass. A declaration whose gate does not match is left unchanged, including another overload of the same name. If the managed runtime for a version cannot be obtained, or it reports a different minor, that pass fails with `TYHP7905` and is not stamped from another PHP version.

The comment text is the compact Layer 1 signature for the declarations active at that version. A stamp that later disagrees with Layer 1 is warning `TYHP8021` at compile time; the overlay is still applied. `--strict` / `build.strictMode` elevates that warning to an error.

## Options

- `--help` — Show this help (same as `tyhp help --subject=overlay`).
- `--strict` — Treat overlay stamp mismatches as errors when compiling.

## Related

- [Tyhpdef Overlays](tyhpdef_overlays.md) — load order, brace `partial`, header `;`, overlay `partial function`, `omit`, stamps
- [CLI: Symbol Tree](cli_symbolTree.md) — dump bound Tyhp names after overlays
- [Extern Types](tyhpdef_extern.md) — name-only placeholders; `create` refuses `extern`
- [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md) — Layer 1 regen, `--vendor`, and `--verify`
- [Diagnostic Code Reference](diagnostics_reference.md) — `TYHP7900`–`TYHP7904`, `TYHP8017`–`TYHP8022`, `TYHP8030`–`TYHP8035`
