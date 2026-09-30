---
title: 'Tyhpdef Overlays'
status:
  tier: 2
  story: '21'
  state: complete
---

Composer packages can ship a **baseline** of generated `.tyhpdef` files and then **overlay** replacements, member merges, and hides on top. Overlays load after `include`. Later overlay files win for the same Tyhp name. Regen overwrites the baseline and generated stub overlays; hand-written overlays are never regenerated.

This is how `tyhpdef/php` adds generics to PHP types (`Iterator<TKey, TValue>`, `SplStack<T>`, …) without editing the Reflection-generated Layer 1 files.

Name-only `extern` placeholders for optional Composer peers — syntax, `.tyhp` use, and generator `externs.tyhpdef` — are documented in [Extern Types](tyhpdef_extern.md). Overlay merge of `extern` is in the last-wins table below.

## `include` vs `overlay`

A Composer package that ships tyhpdefs declares them on `extra.tyhp.package` in that package’s `composer.json`:

```json
{
    "extra": {
        "tyhp": {
            "package": {
                "include": [
                    "./_tyhpdef/*.tyhpdef",
                    "./_tyhpdef/extensions/*.tyhpdef"
                ],
                "overlay": [
                    "./_tyhpdef/overlays/stubs/*.tyhpdef",
                    "./_tyhpdef/overlays/*.tyhpdef"
                ]
            }
        }
    }
}
```

| Array | When it loads | Duplicate Tyhp name |
|-------|---------------|---------------------|
| `include` | First. Baseline signatures plus package-local `extension { }` files when listed. | Conflict (`TYHP8002`). Additive `partial` may add members (see below). |
| `overlay` | After `include`, **in array order**. Within one glob, paths expand lexicographically. | Last wins: full replace, overlay `partial` member merge, overlay `partial` header `;`, or `omit`. |

Overlay globs must not also appear in `include`. `./_tyhpdef/*.tyhpdef` does not recurse into `overlays/` or `extensions/`. `./_tyhpdef/overlays/*.tyhpdef` does not recurse into `stubs/`. `tyhpdef/php` is tyhpdef-only builtins (`include` is `./_tyhpdef/*.tyhpdef` only). Scalar catalogs live in `tyhp/core` (`package.tyhpdef` plus `_tyhpdef/extensions/*.tyhpdef`).

## Stub overlays, then hand-written

Convention: list **generated stub overlays first**, **hand-written overlays last**.

| Layer | Path | Header / owner |
|-------|------|----------------|
| Layer 1 (baseline) | `_tyhpdef/*.tyhpdef` | `AUTO-GENERATED` Reflection / parsed PHP. `tyhp generate_tyhpdef`. |
| Layer 2 (stubs) | `_tyhpdef/overlays/stubs/*.tyhpdef` | `LAYER 2 (stub harvest)` in the file header. Community Psalm / PHPStan / Phan / PhpStorm. Safe to regenerate. Empty files (no members) are not written. Synonym `@template` names are unified by position; constraints become bounds and defaults; `@implements` / `@extends` type arguments are applied when they match the harvested parent. `tyhp generate_tyhpdef --audit-stubs` reports how this layer compares to those corpora. |
| Layer 3 (hand) | `_tyhpdef/overlays/*.tyhpdef` (not under `stubs/`) | `LAYER 3 (hand overlay)` in the file header. Humans and `tyhp overlay create`. Never regenerated. |

The **folder** is the layer: `overlays/stubs/` vs `overlays/` (and Layer 1 lives beside those folders, not under them). Stub overlay basenames match Layer 1 when `--output-file` is set (for example `Ext.Xsl.tyhpdef` in both trees). Layer 2 types use the same harvest rewrite as `generate_tyhpdef`, including Psalm/PHPStan `empty` in a type written as `mixed`, and reserved-word type names written as FQCNs (`class \Hamcrest\Core\Is`). Hand overlays of those types use the same fully-qualified declared name. PHP-source harvest writes PHP `static` as `self` in value positions and keeps `static` on returns; `@template` bounds (FQCN qualification and filled generic arguments) are documented in [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#harvested-types-defaults-and-attributes). Generate may omit types whose parent is a catalog `extern` or `@internal`, and strip members that name them — see [Omitted types](cli_tyhpdefGeneration.md#omitted-types). When a later harvested type has the same FQCN and an identical body (kind, modifiers, `extends` / `implements`, members, flags — not doc comments), generate keeps the first and warns; divergent bodies stay so include-layer `TYHP8002` still fires — see [Repeated FQCNs](cli_tyhpdefGeneration.md#repeated-fqcns). See also [Reserved-word type names](tyhpdef_classes.md#reserved-word-type-names).

`tyhp overlay create` writes a hand-written file and appends that glob at the **end** of `"overlay"` if it is not already listed. It never inserts the hand-written glob before stubs.

## Last wins, by Tyhp name

Identity is the **Tyhp name**, not the PHP name. Each overlay declaration applies against the symbol table as left by previous overlays:

| Overlay declaration | Baseline already has that Tyhp name | Result |
|---------------------|-------------------------------------|--------|
| Ordinary (full) symbol | yes | **Replace** the whole symbol (functions: the entire overload set) |
| Ordinary (full) symbol | no | **Add** |
| Ordinary (full) real type | yes, and it is `extern` | **Replace**; the placeholder becomes that real type |
| Overlay `extern` | yes, and it is a real type | **No-op** (the real type stays) |
| Overlay `extern` | no | **Add** the placeholder |
| Overlay `partial` type `{ … }` | yes (same name and kind, not `extern`) | Merge members only — listed members replace; new members are added. Written header clauses are ignored |
| Overlay `partial` type `{ … }` | yes, and it is `extern` | Skip; **error** `TYHP8030` |
| Overlay `partial` type `{ … }` | no | Skip; **warning** `TYHP8019` |
| Overlay `partial` type `;` (header) | yes (same name and kind, not `extern`) | Replace **written** header clauses (generics, `extends`, `implements`, `as`); omitted clauses and unlisted members stay. Attributes merge onto the type |
| Overlay `partial` type `;` (header) | yes, and it is `extern` | Skip; **error** `TYHP8030` |
| Overlay `partial` type `;` (header) | no | Skip; **warning** `TYHP8019` |
| Overlay `partial function` | yes | Merge attributes onto the existing callable (the entire overload set). Parameters, return type, generics, and docs are unchanged. Optional `as` **renames** the current Tyhp name unless the same overlay file also keeps it |
| Overlay `partial function` | no | Skip; **warning** `TYHP8031` |
| `omit` | yes (including `extern`) | Remove that Tyhp name (it is not found) |
| `omit` | no | **Warning** `TYHP8020`; no-op |

Header-only `partial class Foo<T> implements …;` is overlay-only (`TYHP8034` in an include file). A bare `partial class Foo;` with no generics, inheritance, `as`, attributes, or matching keep-for-alias warns (`TYHP8035`). Overlay `partial function` is a separate form: it merges attributes and may rename (see below).

A full overlay `function \php as tyhp(...)` **adds** the alias and leaves the original Tyhp name. Overlay `partial function X as Y` (and overlay `partial class X as Y;`) **replaces** `X` with `Y` unless the same overlay file also keeps `X`. To hide a name without adding another, use `omit`.

## Overlay `partial` vs include `partial`

`partial` is legal on tyhpdef `class` / `enum` / `interface` / `trait` in both include files and overlay files. The merge rules differ:

| | Include `partial` | Overlay `partial` |
|--|-------------------|-------------------|
| Purpose | Add members to a type already in the include set | Last-wins member merge and/or header merge after include |
| Brace `{ … }` | Additive members. Written generics / `extends` / `implements` are ignored | Listed members **replace** (including overload sets). Written header clauses are ignored |
| Header `;` | Illegal (`TYHP8034`) | Replace **written** header clauses; omitted clauses and unlisted members stay |
| Duplicate member | Error `TYHP8002` | Listed member **replaces** (including its overload set) |
| Missing target type | Error `TYHP8014` | Warning `TYHP8019`; skip |
| `omit` | Illegal (`TYHP8017`) | Allowed on a member inside the brace `partial` type |

```tyhp
<?tyhpdef

// Overlay: replace current() / key() and keep other Iterator members
// @overlay-against: interface Iterator
partial interface Iterator {
    // @overlay-against: function current(): mixed
    public function current(): TValue;
    // @overlay-against: function key(): mixed
    public function key(): TKey;
}
```

A full overlay of `Iterator<TKey = mixed, TValue = mixed>` replaces the whole type, including members. Prefer header-only `partial interface Iterator<TKey = mixed, TValue = mixed>;` when only the generic header changes, and a second `partial interface Iterator { … }` for member signature edits.

## Overlay `partial` header form (`partial class Foo;`)

Overlay-only semicolon form on `class` / `interface` / `trait` / `enum`. Written clauses replace; omitted clauses stay. Unlisted members stay.

```tyhp
<?tyhpdef

partial class SplObjectStorage<TObject extends object = object, TData = mixed> implements \Countable, \Iterator<int, TObject>, \Serializable, \ArrayAccess<TObject, TData>;

#[\Tyhp\Optimize\Pure]
partial class DateTime;

partial class SplObjectStorage;
partial class SplObjectStorage as ObjectStorage;
```

- Present generics / `extends` / `implements` / `as` replace that clause; omitted clauses keep the current type.
- Attributes merge onto the type (same last-wins rule as `partial function`).
- `#[\Tyhp\Php]` on a header `;` targets the matching live gated declaration.
- `partial class X as Y;` renames the current Tyhp name to `Y` (same PHP emit name) unless the same overlay file also has `partial class X;`.
- Bare `partial class X;` with no other clauses warns (`TYHP8035`) unless that keep is paired with an `as` in the same file.
- Include files: **error** `TYHP8034`. Brace `partial class X { members }` remains legal in include (additive members).
- `final` / `readonly` / `abstract` on the semicolon form are ignored. Changing kind, targeting `extern` (`TYHP8030`), or combining with `omit` (`TYHP8018`) is not this form.

Same overlay file may list a header `;` then a brace `partial class Foo { members }`. Header apply and member merge are independent; later overlay files last-win.

See [Classes in Tyhpdef](tyhpdef_classes.md#partial-types-base--include) for include `partial`.

## Overlay `partial function`

Name-only `partial function` merges **attributes** onto an existing free function or method without restating the signature. It is overlay-only (`TYHP8032` in an include file). A parameter list, return type, generics, `async`, visibility, or `omit` on the same declaration is a parse error — not a full replace. An optional `as` alias is allowed.

Match is by the **current Tyhp name**, not the Layer 1 PHP name. After a rename, a later overlay must target the alias that is live now.

```tyhp
<?tyhpdef

#[\Tyhp\Optimize\Pure]
partial function \str_contains;

partial function \strtolower as str2LC;

partial function \strtoupper;
partial function \strtoupper as str2UC;

partial class \DateTime {
    #[\Tyhp\Optimize\Pure]
    partial function format;
}
```

- `partial function X;` — keep `X`, merge attributes.
- `partial function X as Y;` — register `Y` for the same callable (same PHP emit name) and **replace** `X`, unless the same overlay file also has `partial function X;`.
- Keep + alias in one file exposes both Tyhp names. Order in that file does not matter. A later overlay that only names `Y as Z` replaces `Y` and leaves `X` if `X` was kept earlier.

The merge applies to the **entire current overload set**. Existing parameters, return type, generics, and docs stay; overlay attributes are unioned onto the live symbol (same attribute type last-wins). A missing target is skipped with warning `TYHP8031`.

Methods are only valid inside an overlay `partial` type (`TYHP8033` on a full overlay class). `partial function` does not add a new callable; it only keeps, renames, or aliases one that already exists.

An optional stamp may be name-only (`function array_map`). A full Layer 1 stamp is still allowed and still reports `TYHP8021` on mismatch. No stamp does not report `TYHP8022`.

### Rename across overlay layers

Layer 1 (include):

```tyhp
<?tyhpdef
function strtolower(string $string): string;
function strtoupper(string $string): string;
```

Layer 2 (overlay):

```tyhp
<?tyhpdef
partial function strtolower as str2LC;

partial function strtoupper;
partial function strtoupper as str2UC;
```

Layer 3 (later overlay; match the **live** Tyhp names):

```tyhp
<?tyhpdef
partial function str2LC as string_to_lower_case;
partial function str2UC as string_to_upper_case;
```

After Layer 3, Tyhp can call `string_to_lower_case`, `string_to_upper_case`, and `strtoupper`. It cannot call `strtolower`, `str2LC`, or `str2UC`. PHP emit still uses the original PHP names (`strtolower` / `strtoupper`).

`tyhp symbol_tree --filter=strto` dumps the bound names and signatures so you can confirm which aliases are live. See [CLI: Symbol Tree](cli_symbolTree.md).

## `omit`

`omit` is **overlay-only**. Using it in an include / baseline tyhpdef is `TYHP8017`. The signature may be a skeleton — parameters and a class body are not required.

```tyhp
<?tyhpdef

omit function \array_map();
omit class \Closure {};

partial class \DomainException {
    omit public function getPrevious();
}
```

`partial`, `omit`, `deprecated`, `obsolete`, and `extern` cannot be combined on the **same** declaration (`TYHP8018`). `omit` on a member inside an overlay `partial` type is a different declaration and is allowed. Overlay `omit` of an `extern` type is allowed and removes the name. Overlay `partial` cannot target an `extern` type (`TYHP8030`); a full overlay replace with a real `class` / `interface` / `enum` of the same name and kind upgrades the placeholder (`TYHP8029` if the kinds disagree).

## `// @overlay-against:`

An optional comment records the compact **Layer 1** signature the overlay was written against. Functions: one line for the whole signature. Types: one line for the **header only**; each overlaid member may have its own line. Compact stamps omit visibility (`public` / `protected` / `private`) and `final` / `abstract` / `static`. When the declaration also has a docblock or attributes, the stamp is the last line before the keyword (docblock, then attributes, then stamp).

```tyhp
<?tyhpdef

// @overlay-against: interface Iterator extends Traversable
interface Iterator<TKey = mixed, TValue = mixed> extends \Traversable<TKey, TValue> {
    // @overlay-against: function current(): mixed
    public function current(): TValue;
}
```

| Stamp vs Layer 1 | Result |
|------------------|--------|
| Matches | Apply silently |
| Name-only stamp on `partial function` (`function foo` / `function foo;`) | Apply silently when the target was found |
| Mismatches | Warning `TYHP8021`; overlay **still applied**. `--strict` / `build.strictMode` elevates to an error |
| No stamp, replace of an existing symbol | Warning `TYHP8022` if the overlay is not a compile-time-compatible rewrite of the baseline; still applied |
| No stamp, `partial function` | No compatibility check |
| No stamp, add of a new symbol | No compatibility check |

An `as` alias (`function call_user_func as call_user_func_unsafe`) **adds** a Tyhp name and leaves Layer 1 in place. The stamp still names the **PHP original** (`function call_user_func(...)`), and the compiler compares it to that Layer 1 signature — not to the alias name. Variadic `...` in the stamp is ignored when comparing, so `mixed ...$args` matches a Layer 1 compact stamp of `mixed $args`.

`@overlay-against:` does not apply to `extern` declarations (there is no Layer 1 member list). Stamping an `extern` is a no-op.

`tyhp overlay stamp` rewrites these comments from the Layer 1 baseline on **both** stub overlays (`overlays/stubs/`) and hand overlays (`overlays/*.tyhpdef`), one pass per managed PHP version. A pass writes a stamp only onto declarations whose `declare(php=…)` / `#[\Tyhp\Php(…)]` gate that version satisfies. See [CLI: Overlay](cli_overlay.md).

## Creating overlays

```
tyhp overlay create \Iterator
tyhp overlay stamp
tyhp overlay stamp \Iterator
```

`create` copies the current declaration into a hand-written overlay file. It refuses `extern` types (`TYHP7904`) so it does not copy a placeholder into a hollow `class { }` overlay. `stamp` writes or updates `@overlay-against` comments. See [CLI: Overlay](cli_overlay.md) and [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md) (`--verify` applies overlays when checking the final API against PHP; `omit` is not a fail).

## Project overlays for `vendor-tyhpdef/`

`tyhp generate_tyhpdef --vendor` writes into **`vendor-tyhpdef/`** (loaded via `tyhp.json` `"tyhpdefInclude"`). Those files are generated; re-running `--vendor` overwrites them. Do not edit them.

Lasting type fixes go in overlay tyhpdefs listed in `tyhp.json` `"overlay"`. `tyhp init` sets that glob to `./tyhpdef/**/*.tyhpdef`. `tyhp overlay create` copies a declaration into a hand overlay and ensures a hand-written overlay glob is listed on the manifest.

```tyhp
<?tyhpdef
// Generated by `tyhp generate_tyhpdef --vendor`. Do not edit this file.
// Re-running --vendor overwrites it. Put lasting changes in overlay tyhpdefs
// (tyhp.json "overlay", or `tyhp overlay create`), not in vendor-tyhpdef/.
```

## Best Practices

:::tip
DO put generic parameters and other hand refinements in overlay tyhpdefs — including const/property `??` start values that generate omitted because they were nowdocs, regex bodies, or other non-tyhpdef literals, and more precise parameter defaults when generate wrote `= null` for an unrepresentable PHP default. Leave Layer 1 as the generated baseline so regen does not wipe your edits. Use overlay `partial class Foo<T> implements …;` when only the header changes, and a second `partial class Foo { … }` for member edits.
:::

:::tip
DO list stub overlays before hand-written overlays in `"overlay"`. Last file wins for the same Tyhp name.
:::

:::tip
DO run `tyhp overlay stamp` after regenerating Layer 1 so `@overlay-against` comments match the new baseline.
:::

:::tip
DO use `tyhp symbol_tree --filter=<name>` when an overlay rename is not visible in `.tyhp`. The dump is the bound environment `lint` / `build` use.
:::

:::tip
DO document what an overlay changes (generics, parameters, return types, purity). `@inheritDoc` alone is enough only when the signature is unchanged — and then say why the overlay exists.
:::

## Common Mistakes

:::danger
DON'T list overlay globs in `"include"`. Duplicate Tyhp names in include are errors, not last-wins replaces.
:::

:::danger
DON'T use `omit` or overlay last-wins replace in a baseline / include tyhpdef. `omit` is overlay-only (`TYHP8017`).
:::

:::danger
DON'T use include `partial` to change generics or `extends`. Write overlay `partial class Foo<T> extends Bar;` (header-only). A full overlay `class Foo<T> { … }` replaces the whole type, including members.
:::

:::danger
DON'T overlay a hollow `class \Foreign\Type {}` as a stand-in for a type this package does not own. That is a complete empty type, not a placeholder. `tyhp overlay create` refuses `extern` types for the same reason. See [Extern Types](tyhpdef_extern.md).
:::

:::danger
DON'T write `partial function foo as bar` or `partial class Foo as Bar` in a later overlay after an earlier overlay already renamed that name. Match the **current** Tyhp name (`bar as baz`), not the Layer 1 PHP name.
:::

:::danger
DON'T edit generated files under `vendor-tyhpdef/`. `--vendor` overwrites them. Put lasting changes in overlay tyhpdefs (`tyhp.json` `"overlay"` / `tyhp overlay create`).
:::

## Related

- [CLI: Symbol Tree](cli_symbolTree.md) — dump bound Tyhp names after overlays
- [CLI: Overlay](cli_overlay.md) — `create` / `stamp`
- [Functions in Tyhpdef](tyhpdef_functions.md#overlay-partial-function) — overlay `partial function`
- [Classes in Tyhpdef](tyhpdef_classes.md#partial-types-base--include) — include `partial` (additive members)
- [Diagnostic Code Reference](diagnostics_reference.md) — `TYHP8017`–`TYHP8022`, `TYHP8030`–`TYHP8035`
