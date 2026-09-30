---
title: 'About Tyhpdef'
status:
  tier: 0
  story: '02'
  state: complete
---

Tyhp is a transpiler that compiles to PHP. When your Tyhp code needs to interact with existing PHP libraries, extensions, or Composer packages, the Tyhp compiler must understand their types and signatures. Tyhpdef is a declaration-only syntax that describes existing PHP code to Tyhp's type system, enabling compile-time type checking for external PHP code.

Tyhpdef files use the `<?tyhpdef` open tag, have the `.tyhpdef` file extension, and contain only type declarations with no implementation code (with a few exceptions). The Tyhp compiler reads these files during compilation but never emits them as PHP output.

## What You Can Declare

Tyhpdef can describe the following PHP constructs to Tyhp:

- Functions (including async, generic, overloaded, and extension functions)
- Standalone `extension Name { }` blocks (short `fn` / `operator` + `=>` mappings)
- Extension members on classes (`extension fn`, `extension operator`, and `use extension`)
- Classes (including abstract, final, generic, and `partial` classes)
- Interfaces (including generic interfaces with extends chains)
- Traits (including generic traits)
- Enums (both unit enums and backed enums with string or int values)
- Constants (typed global constants; `as` aliases; top-level `deprecated` / `obsolete`)
- Variables (typed global variables; `as` aliases; top-level `deprecated` / `obsolete`)

You can also define these supplemental constructs inside a Tyhpdef file to support your declarations:

- Structs (to describe PHP associative array structures)
- Type aliases (to create reusable type definitions)
- Namespaces (to organize declarations)
- Extern types, functions, and constants (name-only `extern class` / `interface` / `enum` / `function` / `const`, or kind-unspecified `extern \Name;`, for names this package mentions but does not own; a specified type kind must match the originating declaration — see [Extern Types](tyhpdef_extern.md))

## How the Compiler Finds Tyhpdef Files

The Tyhp compiler loads type information from multiple sources. Earlier sources take precedence when declarations conflict:

1. Built-in registrations — Core language types (`decimal`, iterators, `callable(...)`, compile-time constructs, and similar) are registered in the compiler itself and are always available.
2. Composer packages with `extra.tyhp.package` on `composer.json` — Runtime libraries (`tyhp/core`, `tyhp/decimal`, `tyhp/async`, `tyhp/lambda`), the always-present `tyhpdef/php` builtins package (Core, date, filter, hash, json, libxml, pcre, random, Reflection, SPL, standard — stubs cover PHP 8.2–8.5; version-gated declarations are filtered to your `output.phpVersion`), and optional `tyhpdef/php-ext-*` packages (curl, PDO, mbstring, …). If that key is omitted, the compiler defaults to PHP **8.2** and emits warning **TYHP4306** once. Install them with your project so `\strlen`, `DateTime`, `\Tyhp\Type`, and other APIs type-check.
3. User project tyhpdefs — files matching `tyhpdefInclude` in `tyhp.json`, plus any `include` entries that end in `.tyhpdef` or `composer.json` (with `extra.tyhp.package` present as an object). If you omit `tyhpdefInclude`, **project `.tyhpdef` files are not loaded**. `tyhp init` sets `"tyhpdefInclude": ["./vendor-tyhpdef/**/*.tyhpdef"]` and `"overlay": ["./tyhpdef/**/*.tyhpdef"]`.

This alpha does **not** scan a `tyhpdef_gen/` directory. Use `tyhp generate_tyhpdef` for PHP extensions, Composer packages, PHP sources, and the installed `vendor/` tree (`--vendor`), `tyhp build` for compiled Tyhp libraries, or start from `tyhpdef/php`. Package overlays (`extra.tyhp.package` `"overlay"`) and project overlays (`tyhp.json` `"overlay"`) load after include. Overlay `partial class Foo<T>;` replaces written header clauses without restating members. Overlay `partial function` merges attributes or renames a live callable without restating the signature. See [Tyhpdef Overlays](tyhpdef_overlays.md).

## Auto-Generating Tyhpdef Files

`tyhp generate_tyhpdef` produces `.tyhpdef` files from PHP extensions (Tyhp-managed PHP Reflection), Composer packages (`--package-path`), PHP sources (`--source`, `.php` only), and the installed Composer tree (`--vendor` → `vendor-tyhpdef/`). Harvested PHPDoc `@template` bounds qualify nested class names to FQCNs and fill missing generic arguments (see [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#harvested-types-defaults-and-attributes)). PHP-source harvest omits a type whose immediate `extends` / `implements` is a catalog `extern`, or that is `@internal` when `--include-internal` is off; descendants and members that name those types are dropped as well (see [Omitted types](cli_tyhpdefGeneration.md#omitted-types)). When a later harvested type has the same FQCN as one already emitted and the body is identical (kind, modifiers, `extends` / `implements`, members, flags — not doc comments), generate keeps the first, skips the later, and warns. Divergent bodies are both written; include-layer `TYHP8002` still fires (see [Repeated FQCNs](cli_tyhpdefGeneration.md#repeated-fqcns)). Libraries always emit `package.tyhpdef` and additive-merge `extra.tyhp.package` onto publish-directory `composer.json` during `tyhp build`; applications emit `package.tyhpdef` when `build.generateTyhpdef` is true.

See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md) for `--php-targets` gated emit and `--vendor`. Compiler version gates (`declare(php=…)` / `#[\Tyhp\Php]`) are documented in [PHP Version Gating](tyhp_0320_phpVersionGating.md). Overlays are documented in [Tyhpdef Overlays](tyhpdef_overlays.md). Optional Composer peers use name-only `extern` placeholders (`extern \Name;`, `extern class` / `interface` / `enum` / `function` / `const`); a specified type kind must match the originating declaration. `--package-path` / `--source` write them to `_tyhpdef/externs.tyhpdef`, and `tyhp build` writes author-only owners into `package.tyhpdef` — see [Extern Types](tyhpdef_extern.md).

:::note
Auto-generated tyhpdef files may use broad types like mixed where more specific types could be used. Harvest writes Psalm/PHPStan `empty` in a type as `mixed`. PHP `static` in a value position (parameter, property, `@param`, `@var`, magic `@method` parameter, `@property`) is written as `self`; return positions keep `static` (`: static`, magic `@method` return types, including generic arguments such as `Builder<static>`). A class, interface, trait, or enum whose short name is a reserved word (`is`, `isset`, …) is written fully qualified (`class \Hamcrest\Core\Is`). PHPDoc `@template T of Foo<…>` (and similar generic, union, and intersection type strings) qualify nested class names to FQCNs from `use` imports, unique PHP / `\Psr\*` shorts, and same-package declared types; template parameters (`T`) and builtins stay unqualified. Native `extends` / `implements` / trait `use` prefer a same-package declared type over a unique PHP / `\Psr\*` short of the same name (`implements Exception` → `\Acme\Exception\Exception`); a true global the package does not declare (`extends \InvalidArgumentException`) stays global. A generic bound written without type arguments is completed from that type's own default, else its constraint, else `mixed`. Harvested parameter defaults that are not tyhpdef literals stay optional with `= null` (the same dummy used for harvested implicit-nullable PHP; the declared type is not widened). Const and property `??` values that are not tyhpdef literals are omitted. Unmatched attribute arguments are written as `#[Name]`. Review Layer 1 output and Layer 2 stub overlays; put omitted `??` values, more precise parameter defaults, and other hand refinements in hand-written overlay files (`_tyhpdef/overlays/*.tyhpdef`), not in the generated baseline.
:::

## When to Create Tyhpdef Files

:::tip
DO create tyhpdef files for: C extensions with no PHP source (e.g., custom PECL extensions), legacy PHP libraries without type declarations, Composer packages that lack PHPDoc or native type hints, and internal PHP libraries shared between PHP and Tyhp projects.
:::

:::danger
DON'T create tyhpdef files for: PHP builtins already covered by `tyhpdef/php` (Core, standard, SPL, date, json, hash, libxml, and similar — install that package instead of redeclaring them), optional extensions already covered by a `tyhpdef/php-ext-*` package, or Tyhp **application** code you are not publishing — `.tyhp` files are already fully typed. Tyhp **libraries** always emit `package.tyhpdef` and additive-merge `extra.tyhp.package` on `tyhp build`. For third-party PHP, prefer `tyhp generate_tyhpdef --vendor` (after Composer has populated `vendor/`) or `--package-path=…` / `--source=…` over retyping every member by hand. Do not edit `vendor-tyhpdef/` — use overlays.
:::

## Accuracy Matters

The types and structures in your Tyhpdef files are the sole source of truth the Tyhp compiler uses for external PHP code. Anything incorrect or incomplete in those files can lead to compile-time errors (false positives or missed real errors) and runtime errors (type mismatches in the generated PHP output).

:::warning
Always ensure your tyhpdef declarations match the actual PHP implementation. Declaring a method as returning int when it actually returns string will cause the compiler to accept incorrect code and produce runtime type errors.
:::

## Tyhpdef vs Tyhp

While Tyhpdef syntax closely resembles Tyhp, there are key differences:

- Tyhpdef files use <?tyhpdef, not <?tyhp
- Tyhpdef files have the .tyhpdef extension, not .tyhp
- Tyhpdef contains declarations only — no executable top-level code. The `=>` expression on `extension fn` / `extension operator` and on standalone `extension Name { }` members is a rewrite template, not emitted PHP
- Ordinary method and function declarations end with a semicolon instead of a curly-brace body
- Tyhpdef code is never compiled into PHP output — it exists only for the compiler's type system

## PHP version gating

Tyhpdef can describe APIs that differ by PHP minor. Use `#[\Tyhp\Php("…")]` (or `version:`) on classes, functions, and other legal attribute targets, or wrap declarations with `declare(php="…");` / `declare(php="…") { … }`.

`#[\Tyhp\Php]` is illegal on `struct` and on tyhpdef `extension { }` (**TYHP4304**). See [PHP Version Gating](tyhp_0320_phpVersionGating.md).
