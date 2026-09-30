---
title: 'Extern Types in Tyhpdef'
status:
  tier: 2
  story: '21.1'
  state: complete
---

Composer libraries often type-hint classes they do not `require`. Monolog is the usual example: `ElasticaHandler` lives in `monolog/monolog`, but `\Elastica\Client` lives in `ruflin/elastica`, which is only `suggest` / `require-dev`. The PHP package is right to keep those peers out of `require`. The tyhpdef wrapper must not pull Elastica (or AWS, Gelf, Predis, optional extensions, and similar) into every consumer's `vendor/`.

Without a placeholder, those names are unresolved (`TYHP3019` / `TYHP3020`) and the **wrapper tyhpdef cannot load**, even when the consuming project never touches those handlers.

`extern` is a tyhpdef-only, name-only declaration for a type, function, or const this package mentions but does not own. The name is legal in **tyhpdef signatures**. It is **not** usable in `.tyhp`. A later real declaration of the same Tyhp name and kind silently replaces a compatible placeholder.

## Syntax

`extern` is a contextual keyword in `.tyhpdef`. It may stand immediately before `class`, `interface`, `enum`, `function`, or `const`, or immediately before a type name with no kind word. The form is name-only: a semicolon, no body, no members, no signature, no value, no generics, no `extends` / `implements`, no `abstract` / `final` / `readonly`, no `as` alias, and no backing type on `enum`.

```tyhp
<?tyhpdef

// Kind unknown — typical for hand-written optional peers.
extern \Elastica\Document;
extern \Elastica\Client;

// Kind known (generator / catalog, or you looked it up).
// @provided-by: tyhpdef/php-ext-curl
extern class \CurlHandle;
extern interface \Psr\Log\LoggerInterface;

// Functions and constants — name only, no signature or value.
// @provided-by: tyhpdef/php-ext-bcmath
extern function \bcadd;
extern const \GMP_ROUND_PLUSINF;
```

The bare form (`extern \Name;`) is a kind-unspecified placeholder: it may be replaced by a later real `class`, `interface`, or `enum` of the same fully-qualified name. Use `extern class` / `interface` / `enum` when you know the kind — and that kind must match the originating declaration. Use `extern function` / `extern const` for those PHP name spaces (they coexist with a type of the same name). Combining `extern` with `partial`, `omit`, `deprecated`, or `obsolete` on the **same** declaration is `TYHP8018`. An illegal body, parameter list, return type, or other extra syntax is `TYHP8028`.

## Matching kind

When a tyhpdef package names a type owned by another package, a specified-kind `extern` must use the **same kind** as that originating declaration:

- originating `interface` → `extern interface`
- originating `class` → `extern class`
- originating `enum` → `extern enum`

A mismatch — for example `extern class` for a name declared as `interface` — is `TYHP8029`. Change the placeholder kind to match; do not invent a different PHP type.

The generator copies the catalog kind onto proven optional peers. Hand-written specified kinds follow the same rule. Use the bare form (`extern \Name;`) when you have not looked up the kind.

## `@provided-by`

`// @provided-by:` names the **Tyhp wrapper** that really declares the type — `tyhpdef/ruflin-elastica`, `tyhpdef/php-ext-curl` — not the PHP package (`ruflin/elastica`) and not `ext-curl`.

Generator-owned `extern` always has this comment (the catalog knows the wrapper). Hand-written `extern` may omit it. Diagnostics cite the name as-is: include that `tyhpdef/*` package so a real declaration replaces the placeholder.

## Real wins

When the providing wrapper is included, a real `class` / `interface` / `enum` / function / const of the **same fully-qualified name** silently replaces the placeholder when the kinds are compatible. `TYHP8002` and `TYHP8025` do not fire. Order does not matter: loading the real tyhpdef before or after the `extern` yields the real declaration.

A kind-unspecified `extern \Name;` is compatible with a later real class, interface, or enum. An `extern class` (or `interface` / `enum`) that arrives after a real type of the same name and kind is a no-op (the real type stays). Two `extern` declarations of the same kind merge; a specific kind claim wins over a later unspecified one. A specified kind that does not match the originating declaration (`extern class` vs real `interface`, or two externs of different specified kinds) is `TYHP8029` — see [Matching kind](#matching-kind). Functions, constants, and types occupy separate PHP name spaces, so `extern function Foo` may coexist with `class Foo`.

Overlay last-wins of a full real type onto `extern` is the same upgrade. Overlay `extern` onto a real type is a no-op. See [Tyhpdef Overlays](tyhpdef_overlays.md).

## Using an `extern` name from `.tyhp`

Using an `extern` type, function, or const in a `.tyhp` file is **TYHP4307**. The primary span is the use; a secondary span labeled "declared here" points at the `extern` declaration. When `@provided-by` is present, help cites that wrapper name.

**A use (TYHP4307):**

| Site | Example |
|------|---------|
| Type annotation (parameter, return, property), including a `\|` or `&` arm | `function f(\Elastica\Client $c): void` |
| Generic type argument | `array<\Elastica\Document>` |
| `new` | `new \Elastica\Client()` |
| `instanceof` | `$x instanceof \Elastica\Client` |
| `catch` (including a catch union arm) | `catch (\Elastica\Exception\ExceptionInterface $e)` |
| `use` / `use function` / `use const` / group `use` of that FQCN | `use \Elastica\Client;` |
| Call whose **return** type is extern | `$handler->getDocument()` when that method returns `\Elastica\Document` |
| Argument to a parameter whose type is extern | `new ElasticaHandler($client)` when the constructor parameter is `\Elastica\Client` |
| Call of an extern function | `\bcadd("1", "2")` |
| Fetch of an extern const | `int $mode = \GMP_ROUND_PLUSINF;` |

A union or intersection is a use when **any** arm is extern. After the providing wrapper is included, that arm is a real type and is no longer a use.

**Not a use:**

- Naming a **real** class whose signature mentions extern (for example `Monolog\Handler\ElasticaHandler`). Mentioning that class is fine until you write a use of the extern type itself.
- Tyhpdef parameter, return, and property types that name an extern type. Those signatures are why the placeholder exists.
- Tyhpdef signatures and mapping bodies that name an extern function or const.
- `extends` / `implements` of an extern type. That is bind **TYHP3026** / **TYHP3027**, not 4307. A real tyhpdef type must not extend or implement an extern type.

## Do not overlay a hollow class

A hollow `class \Foreign\Type {}` overlay is a complete empty type, not a placeholder. User code would type-check without the real package, emit could mention a class that autoload-fails, and a later real wrapper would hit `TYHP8002` / `TYHP8025` instead of upgrading.

Use `extern` for optional peers. Extra names the generator could not prove belong in a hand include file regen does not overwrite, not in a fake empty class.

## Generator: `_tyhpdef/externs.tyhpdef`

`tyhp generate_tyhpdef --package-path` (and package-shaped `--source`) classifies foreign signature types against a catalog of existing `tyhpdef/*` packages:

| Condition | Result |
|-----------|--------|
| Catalog hit, providing PHP package / `ext-*` is in the target **`require`** | No `extern`. The wrapper `require`s that `tyhpdef/*` package. |
| Catalog hit, providing package is in target **`suggest`** or **`require-dev`** (and not `require`) | Emit `extern` with the catalog kind and `// @provided-by: tyhpdef/…`. Do not `require` that wrapper. |
| Catalog miss, or the providing package is in none of those three | Leave the name as written. Bind reports `TYHP3019` / `TYHP3020` until a human adds a wrapper or a hand `extern`. |
| Unqualified name | Never auto-`extern`. |
| Generated type `extends` / `implements` a name that would be `extern` | That generated type is **omitted** (CLI warning). Descendants that `extends` / `implements` an omitted type are omitted too. Members, trait `use`, functions, and aliases whose types refer to an omitted FQCN are stripped. |

PHP-source harvest also omits `@internal` types when `--include-internal` is off. After either seed, omit cascades through `extends` / `implements`, then strips members that actually name an omitted FQCN (`use` imports and already-qualified names). A bare PHPDoc name with no import, left as written, is not treated as a type in another namespace just because the last segment matches; unqualified omit matching is the current namespace only. Intra-package unique-short qualification runs after omit. `--include-internal` keeps `@internal` types and their references. Details: [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#omitted-types).

The catalog indexes **real** `class` / `interface` / `enum` declarations only. Another package's `extern` does not count as providing the type. Catalog hits emit `extern` with that catalog kind so the placeholder matches the originating declaration. When indexing those files, `{` and `}` inside `/** */`, `/* */`, `//`, and quoted strings are not namespace delimiters. Unique harvest shorts for unqualified PHPDoc / hint names come from `php` / `ext-*` wrappers plus unique `\Psr\*` types, not from Composer-library class names. Native `extends` / `implements` / trait `use` still qualify an unqualified or single-segment `\Short` name to a same-package declared FQCN when that type exists in the harvest, even if the short is a unique PHP / `\Psr\*` global; a true global the package does not declare stays global. That rewrite also walks names inside `@template` bounds and other generic, union, and intersection PHPDoc strings (same-package declared types qualify too); remaining unqualified names are still never auto-`extern`. `@provided-by` is always a catalog `tyhpdef/*` name.

A harvested `extern function` whose short name is a PHP or tyhpdef reserved word is written with the enclosing-namespace prefix (`namespace Some\Ns { extern function \Some\Ns\isset; }`). Hand `extern function` uses the same fully-qualified form. See [Reserved-word type names](tyhpdef_classes.md#reserved-word-type-names).

Proven optional-peer `extern` declarations are written to **`_tyhpdef/externs.tyhpdef`** (`AUTO-GENERATED`). Regen **overwrites this file only** (or deletes it when the run classified and produced none). `extra.tyhp.package` `"include"` glob `./_tyhpdef/*.tyhpdef` already loads it.

Hand `extern` for unknown-origin types lives in a **different** include file (for example `_tyhpdef/backers.extern.tyhpdef`) or in overlay. Regen must not touch those. Prefer the bare form (`extern \Name;`) when you have not looked up the kind. When you do specify a kind, it must match the originating declaration. Two `extern` of the same kind merge; a specific kind wins over unspecified.

`tyhp build` writes name-only `extern` (including `extern function` / `extern const`) into this package's `package.tyhpdef` when a public API name is owned by a package listed in this library's `require-dev` but not in `require` and not in `extra.tyhp.require`. Those placeholders include `// @provided-by: <owning package>`. Names owned by a runtime `require` (for example `tyhp/core`) or by an `extra.tyhp.require` entry stay real FQNs — they are not copied and not externed. Unknown origin is left as written. Regen overwrites `package.tyhpdef`. `--package-path` / `--source` still use `_tyhpdef/externs.tyhpdef` as above. Library authors fill `extra.tyhp.require` with what consumers must install; see [Composer Runtime Packages](project_composerPackages.md#ambient-tyhpdefs-extratyhprequire) and [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md).

Not every optional peer has a `tyhpdef/*` wrapper yet. Catalog-miss names stay unresolved until that wrapper exists (then regen) or until you add a hand `extern`.

## Overlay and `overlay create`

Overlay merge of `extern` — last-wins full replace, `partial` cannot target (`TYHP8030`), `omit` may, stamp is a no-op — is documented in [Tyhpdef Overlays](tyhpdef_overlays.md). `tyhp overlay create` refuses an `extern` type (`TYHP7904`); `tyhp overlay stamp` on `extern` is a no-op. See [CLI: Overlay](cli_overlay.md).

## Best Practices

:::tip
DO list consumer-needed tyhpdefs in `extra.tyhp.require` (and duplicate them in `require-dev`). Leave author-only wrappers in `require-dev` only. See [Composer Runtime Packages](project_composerPackages.md#ambient-tyhpdefs-extratyhprequire).
:::

:::tip
DO put hand `extern` for catalog-miss names in a file regen does not overwrite. Leave `_tyhpdef/externs.tyhpdef` to the generator. Write `extern \Name;` when you do not know whether the type is a class, interface, or enum. When you do know, write the same kind as the originating declaration (`extern interface` for an `interface`).
:::

:::danger
DON'T write `extern class` for a name the providing package declares as `interface` (or any other kind mismatch). That is `TYHP8029`. Match the kind; do not invent a different PHP type.
:::

:::danger
DON'T overlay a hollow `class \Foreign\Type {}` as a stand-in for a type this package does not own.
:::

:::danger
DON'T `require` the providing `tyhpdef/*` wrapper from a package that only `suggest`s the PHP peer. That Composer-requires the PHP package for every consumer.
:::

## Related

- [Tyhpdef Overlays](tyhpdef_overlays.md) — last-wins, `partial` / `omit` targeting `extern`, stamps
- [CLI: Overlay](cli_overlay.md) — `overlay create` refuses `extern` (`TYHP7904`); stamp is a no-op
- [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md) — `--package-path` / `--source` catalog and `externs.tyhpdef`; omitted types; `tyhp build` `package.tyhpdef`
- [Composer Runtime Packages](project_composerPackages.md#ambient-tyhpdefs-extratyhprequire) — `extra.tyhp.require` vs author-only `require-dev`
- [Diagnostic Code Reference](diagnostics_reference.md) — `TYHP4307`, `TYHP3026`, `TYHP3027`, `TYHP7904`, `TYHP8028`–`TYHP8030`
