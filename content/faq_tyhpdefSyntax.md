---
title: 'FAQ: Tyhpdef Syntax'
---

## When do I need to write tyhpdef files?

You need tyhpdef files whenever your Tyhp code interacts with PHP code that exists outside the Tyhp project — Composer packages, PHP extensions (like PDO, cURL, or Redis), legacy PHP codebases, or any PHP code that the Tyhp compiler does not compile itself. Tyhpdef files tell the compiler what types those external functions, classes, and constants have so it can type-check your code correctly.

## Can tyhpdef files be auto-generated?

Yes. `tyhp generate_tyhpdef` generates tyhpdefs from PHP extensions (`--ext-name`), Composer packages (`--package-path`), PHP sources (`--source`, `.php` only), and the installed Composer tree (`--vendor` → `vendor-tyhpdef/`). Harvested types rewrite PHPDoc `callable(...)` / `closure(...)` to `callable` and Psalm/PHPStan `empty` to `mixed`. PHP `static` in a value position (parameter, property, `@param`, `@var`, magic `@method` parameter, `@property`) is written as `self`; return positions keep `static` (`: static`, magic `@method` return types, including generic arguments such as `Builder<static>`). A harvested class, interface, trait, or enum whose short name is a reserved word (`is`, `isset`, …) is written fully qualified (`class \Hamcrest\Core\Is`). PHPDoc `@template T of Foo<…>` qualifies class names in the bound to FQCNs (`use` imports, unique PHP / `\Psr\*` shorts, same-package declared types); template parameters and builtins stay unqualified. Native `extends` / `implements` / trait `use` prefer a same-package declared type over a unique PHP / `\Psr\*` short of the same name (`implements Exception` → `\Acme\Exception\Exception`); a true global the package does not declare stays global. Missing generic args on a bound are filled from that type's own default, else its constraint, else `mixed`. PHP-source harvest keeps the first type per FQCN when a later body is identical (kind, modifiers, `extends` / `implements`, members, flags — not doc comments) and warns; divergent bodies are both written and include-layer `TYHP8002` still fires. Harvested `=` / `??` values are tyhpdef literals only. A parameter whose PHP default is not a tyhpdef-safe literal stays optional with `= null` (the same dummy used for harvested implicit-nullable PHP; the declared type is not widened). Const and property `??` values that are not literals are omitted. Unmatched attribute arguments are reduced to `#[Name]`. Libraries always emit `package.tyhpdef` and additive-merge `extra.tyhp.package` on `composer.json` on `tyhp build`. See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md). `--php-targets` reflects each listed minor with managed PHP and emits one gated tree. You can still write tyhpdefs by hand or start from the `tyhpdef/php` package.

## How do I declare PHP APIs that differ by version?

On tyhpdef classes and functions, use `#[\Tyhp\Php("…")]` (or `version:`). File-level `declare(php="…");` and `declare(php="…") { … }` also parse in `.tyhpdef`. `#[\Tyhp\Php]` is illegal on tyhpdef `extension { }` and `struct` (**TYHP4304**) — gate those with `declare(php=…) { }` instead. One `tyhpdef/php` package covers 8.2–8.5 this way. See [PHP Version Gating](tyhp_0320_phpVersionGating.md).

## How do I mark a tyhpdef symbol deprecated?

Use the `deprecated` keyword on the top-level declaration, or `#[\Deprecated]` (a string-literal `$message` is included in **TYHP4500**). Both set deprecation on the symbol; both produce the same warning. See [The deprecated and obsolete Keywords](tyhpdef_deprecatedKeyword.md) and [PHP Engine Attributes](tyhp_0330_phpEngineAttributes.md).

## How do I describe a hooked PHP property?

Use a bodyless hook list on the property: `{ get; set; }`, `{ get; }`, or `{ &get; set; }`. Visibility on a hook (`private set`) is allowed. Hook bodies (`get { }` / `get =>`) belong in `.tyhp`, not `.tyhpdef`. Gate the property with `#[\Tyhp\Php(">=8.4")]` or `declare(php=…)`, not an individual hook (**TYHP8016**). See [Classes in Tyhpdef](tyhpdef_classes.md#properties).

## How do I type PHP extensions?

PHP extensions (like PDO, cURL, mbstring) are typed with tyhpdef files. Always-present builtins ship in `tyhpdef/php` (Core, date, filter, hash, json, libxml, pcre, random, Reflection, SPL, standard — one package covering 8.2–8.5). Optional extensions ship as `tyhpdef/php-ext-*` (for example `tyhpdef/php-ext-curl`, `tyhpdef/php-ext-pdo`, `tyhpdef/php-ext-mbstring`). json, hash, and libxml stay in `tyhpdef/php`. `tyhpdef/php-ext-decimal` is PECL Decimal, not `tyhp/decimal`. To regenerate or add an unpublished extension, run `tyhp generate_tyhpdef --ext-name=… --php-targets=8.2,8.3,8.4,8.5`. See [Composer Runtime Packages](project_composerPackages.md).

## How do I add Tyhp extension methods in a tyhpdef file?

Declare a standalone `extension Name extends Type { }` (or nested `extends Type { }` groups) with short `fn` / `operator` + `=>` members. `$this` is the block target. Return types are required, and empty `{}` is an error. On a tyhpdef class, write thin `extension fn` / `extension operator` mappings (`=>` only; fully erased — PHP cannot call them; `$this` and `self` are the enclosing class), or attach an extension with `use extension` so callers of **that type** get the methods without their own import. File-level `use extension` is opt-in unless the tyhpdef uses `global use extension`. See [Extensions in Tyhpdef](tyhpdef_extensions.md).

## Can a tyhpdef use `global use`?

Yes. `global use` / `global use function` / `global use const` / `global use extension` in a loaded tyhpdef apply to the entire compilation (C# `global using`, not PHP `global $var`). `tyhp/core` uses `global use extension \Tyhp\StringExtensions` (and the matching Array / Int / Float / Bool / Closure files), so scalar methods need **no** per-file import. A consumer file may re-import that symbol locally to alias or adapt it; a redundant non-mutating local `use` warns (`TYHP4169`). A compiled library that authored in-package `global use` copies those statements into `package.tyhpdef`. See [Use statements](tyhp_0350_useStatements.md#global-use) and [Scalar Pseudo-Objects](tyhp_1000_scalarPseudoObjects.md).

## How do I type optional Composer peers?

PHP packages often type-hint classes they only `suggest` or list in `require-dev` (Monolog's Elastica handler is the usual example). The PHP package is right not to `require` those peers. In tyhpdef, declare a name-only `extern \Name;` (or `extern class` / `interface` / `enum` / `function` / `const` when you know the kind) so the wrapper can load; using that name from `.tyhp` is `TYHP4307` until you include the providing `tyhpdef/*` wrapper. A specified type kind must match the originating declaration (`interface` → `extern interface`, `class` → `extern class`, `enum` → `extern enum`); a mismatch is `TYHP8029`. `// @provided-by:` names the **wrapper** (`tyhpdef/ruflin-elastica`, `tyhpdef/php-ext-curl`), not the PHP package. `--package-path` / `--source` write catalog-proven peers to `_tyhpdef/externs.tyhpdef`. `tyhp build` writes author-only owners into `package.tyhpdef`. Do not overlay a hollow `class \Foreign\Type {}`. See [Extern Types](tyhpdef_extern.md).

## Can I override tyhpdef files?

Layer 1 generated files plus Layer 2 stub overlays are the baseline. **Duplicate members in base / `include` tyhpdefs are an error** (`TYHP8002`), including additive `partial` that repeats a member. Last-wins replace, overlay brace `partial` (member merge), overlay header-only `partial class Foo<T>;` (generics / inheritance / `as` / attributes without rewriting members), overlay `partial function` (attribute merge / rename), and `omit` are **overlay** behavior — list those files in `extra.tyhp.package` `"overlay"` (stubs first, hand-written last) or, for `--vendor` stubs, in `tyhp.json` `"overlay"`. Overlay `partial` missing its target warns (`TYHP8019`); overlay `partial function` missing its target warns (`TYHP8031`); `omit` of a missing symbol warns (`TYHP8020`). `--verify` applies overlays when comparing the final API to PHP (`omit` is not a fail). `tyhp symbol_tree --filter=<name>` dumps the bound Tyhp names after overlays. See [Tyhpdef Overlays](tyhpdef_overlays.md) and [CLI: Symbol Tree](cli_symbolTree.md).

## What happens if a tyhpdef is wrong?

Mismatches between tyhpdef declarations and actual PHP code can lead to runtime errors. For example, if you declare a function returns `string` but the actual PHP function returns `int`, the compiled PHP code may pass a value of the wrong type to a subsequent call, resulting in a `TypeError` at runtime. Always keep your tyhpdef files synchronized with the PHP code they describe. When in doubt, use more permissive types (like `mixed`) rather than risk an incorrect narrow type.

## Do I need tyhpdef for Composer packages?

If you want the Tyhp compiler to type-check your interactions with a Composer package, yes. Without a tyhpdef, the compiler does not know the types of the package's classes, methods, and functions. After `composer install`, run `tyhp generate_tyhpdef --vendor` (or rely on `post-autoload-dump`). That prefers a published `tyhpdef/<vendor>-<name>` companion and otherwise writes `vendor-tyhpdef/`. Do not edit generated stubs; put last-wins replaces and `omit` in overlay files listed in `tyhp.json` `"overlay"` (or `extra.tyhp.package` `"overlay"` for a wrapper package). You can still generate one package with `--package-path=./vendor/vendor/package`.

:::tip
You do not need to define every method of a class in a tyhpdef file. Only import the members (methods, properties, constants) that your Tyhp code actually calls. Private members should never be imported since they are not accessible.
:::
