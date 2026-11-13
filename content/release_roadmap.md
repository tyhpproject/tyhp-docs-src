---
title: Roadmap
status:
  tier: 3
  story: '30'
  state: complete
---

Tyhp is built in a deliberately ordered sequence of stories, grouped into four tiers. The guiding principle is a thin vertical slice that compiles and runs end-to-end as early as possible.

**This beta (805.1.2-beta.4)** completes Tiers 0–2, apart from the deferred web playground (Story 22), and the first Tier 3 story (Story 22.1). The rest of Tier 3 is next. Features listed under Tier 3 and Future Plans are not in this beta unless marked shipped.

Stories are numbered contiguously from 01 to 30, with additive sub-stories such as `08.5` and `24.1` inserted where needed. Future Plans stories are numbered from 31. Each documentation page carries a Tier/Story badge.

:::note
The two flagships are **Story 08 — the type checker** (the correctness engine on the spine) and **Story 16 — parsable lambdas / expression trees** (the marquee feature that enables LINQ-style query builders and ORMs).
:::

## Tier 0 — Spine (a real program compiles and runs) — done

1. **Story 01 — Foundation:** diagnostic system, compilation pipeline, and build endpoint.
2. **Story 02 — Binder:** name resolution and scope building.
3. **Story 03 — Extension operator overloads & tyhpdef inline extensions.**
4. **Story 04 — Tyhp runtime library modules:** tyhp/core, tyhp/decimal, tyhp/async, tyhp/lambda.
5. **Story 05 — Bind symbols to AST nodes.**
6. **Story 06 — Built-in types, grammar fixes, and compiler infrastructure.**
7. **Story 07 — Testing infrastructure & conformance harness.**
8. **Story 08 — Checker** (type checking & validation) — <i>flagship</i>.
9. **Story 08.5 — Symbol-name types** (`__ClassName`, template string types, …).
10. **Story 09 — Emitter** (basic PHP output).
11. **Story 10 — Build action** (wires everything together).
12. **Story 10.5 — Deferred correctness & quality fixes.**

## Tier 1 — Usable — done (previous alpha)

1. **Story 11 — Emitter feature expansion:** structs, generics erasure, extension methods, operator overloads, type aliases, with, disposables, async/await, compile-time constructs, short function syntax, overloads, type guards, trait requirements, and import lowering.
2. **Story 12 — Lint action.**
3. **Story 13 — CLI polish:** help, init, version, composer integration.
4. **Story 14 — Error-message quality** (diagnostics as a product feature).
5. **Story 14.5 — PHP 8.5 syntax surface + lowering** (`805.0.0`).
6. **Story 15 — The Tyhp ↔ PHP interop contract** (written down).
7. **Story 16 — Parsable lambdas (expression trees)** — <i>flagship wedge showcase</i>.
8. **Story 16.5 — Callable signature utilities** (`__CallableParametersStruct` / `__CallableParametersTuple` / `__CallableReturnType`).
9. **Story 28 — Generic type parameter defaults** (originally sequenced in Tier 3; already in the alpha).

## Tier 2 — Developer Experience & Ecosystem — done (this beta)

1. **Story 17 — Sourcemap generation** (shipped).
2. **Story 18 — XDebug proxy** (shipped).
3. **Story 19 — Language Server (LSP)** (shipped; stdio only).
4. **Story 19.5 — IDE clients (VS Code and PhpStorm)** (shipped).
5. **Story 20 — Tyhpdef generator** (C# CLI integration; `generate_tyhpdef` and `package.tyhpdef` on `tyhp build` shipped, plus `--php-targets` gated emit).
6. **Story 20.5 — PHP version gating** (`declare(php=…)` / `#[\Tyhp\Php]`).
7. **Story 21 — PHP extension Composer packages** (`tyhpdef/php` + `tyhpdef/php-ext-*`; one package per extension across 8.2–8.5 with `declare(php=…)` / `#[\Tyhp\Php]` gates). Includes the built-in scalar method catalog (`$name->toUpper()`, …) via `global use extension \Tyhp\StringExtensions`.
8. **Story 21.1 – 21.12** — Addendum work for tier 2 (shipped).
9. **Story 27 — Object shapes and `__New<T>`** (shipped).
10. **Story 27.1 — Callable shapes and `type Name = struct { };`** (shipped).
11. **Story 27.2 — Block-target extension syntax** (`extension Name extends Type`; shipped).
12. **Story 27.3 — Split runtime, docs, AI developer guide, and IDE plugin into dedicated git repos** (shipped).
13. **Story 22 — Web playground** (live .tyhp → PHP) — DEFERRED, not in this beta.

## Tier 3 — Advanced — in progress

Tier 3 ends with the first stable release, after release-candidate rounds. Changes that alter how existing code compiles or runs are scheduled in Tier 3, before that release.

1. **Story 22.1 — Emitted docblocks and Tyhp templates** (shipped in this beta): PHPStan and Psalm tags on emitted PHP, and `<?=` as a Tyhp echo in `.tyhp` files. See [Emitted Docblocks](cli_emittedDocblocks.md).
2. **Story 22.2 — Struct initializers:** `new Name[key => value]` as the short form of `new Name() with [key => value]`, and `new Name[]` for `new Name()`, with checked spread (`new Name[...$base, key => value]`).
3. **Story 35 — No uninitialized storage** (implemented): `unset` of a local, a typed instance property, or a static property is an error (TYHP4158). A typed static property needs an initializer (TYHP4418). After construction, every typed instance storage property is initialized (TYHP4419). A class that declares no constructor runs the nearest ancestor constructor. Drop a value with `?T = null`. Array-offset `unset` and unsetting an optional struct field stay legal.
4. **Story 34 — `operator default()`:** a class declares the value `default(MyClass)` produces.
5. **Story 32 — Scalar-conversion contracts:** objects define how they convert to `int`, `float`, `bool`, and `decimal`, the way `\Stringable` works for `string`, and casts on those objects call the conversion.
6. **Story 41 — Abstract members for trait requirements:** a trait that `extends` or `implements` emits `abstract` members for the requirements it uses, so a PHP class that uses the trait without meeting them fails when the class is declared instead of when the method is called.
7. **Story 23 — Compiler optimizer (MVP).**
8. **Story 24 — Advanced optimizations.**
9. **Story 24.1 — Promise interop:** adopt promises from other async libraries with `Promise::from`, optional wrapper packages for ReactPHP, Amp, Guzzle, and HTTP promise interfaces, and an option to run on the ReactPHP or Revolt event loop instead of Tyhp's.
10. **Story 25 — `internal` project-boundary enforcement and the internals overlay (`includeInternals`)** (the modifier itself already hides symbols from published `package.tyhpdef`; see [The internal Visibility Modifier](tyhp_3100_internalModifier.md)).
11. **Story 26 — Null-conditional chaining with assignment** (see [Null-Conditional Assignment](tyhp_3300_nullConditionalAssignment.md)).
12. **Story 29 — Tyhp reflection API** (sourcemap-backed; reports the Tyhp-level structure, such as generics, at runtime).
13. **Story 29.1 — Pre-stable compatibility changes:** small checker and configuration changes that reserve syntax for Future Plans features, so those features can ship after the stable release without changing what existing code does.
14. **Story 30 — Documentation & polish** (final capstone).

> Story 28 (generic defaults) shipped with the alpha; see Tier 1 above.

## Future Plans — after the first stable release

These are planned after Tier 3, in the order below. None has a release target yet, and the order may change with feedback.

1. **Faster cold starts:** a precompiled symbol cache for `tyhpdef/php` and runtime package tyhpdefs.
2. **Exclusions in glob lists:** a glob string that starts with `!` in a `tyhp.json` or `extra.tyhp.package` glob array removes the paths it matches.
3. **Pipe operator output:** when the target is PHP 8.5 or newer, extension-method chains compile to `|>` instead of nested static calls.
4. **Default interface implementations:** an interface can `use` a trait so every implementing class gets it.
5. **Declaration-site variance:** `in T` and `out T` on class, interface, and trait type parameters.
6. **Conditional return types:** `T extends X ? A : B`, a `match (T) { … }` form for multi-way cases, and flag-presence checks for bitmask arguments such as `JSON_THROW_ON_ERROR`. Overloads become shorthand for the same checker model.
7. **Advanced conditional types:** `infer`, opt-in distribution over unions, and recursive conditional types.
8. **Opt-in runtime checks:** at public PHP-callable boundaries, check struct shapes (and later generic bounds) that the compiler already verified in Tyhp code.
9. **Runtime closure and fiber checks:** `is \Closure<…>` and `is \Fiber<…>` test the parameter and return types that PHP reflection can see.
10. **Compiler plugins:** Composer-packaged plugins that add checks, emit hooks, and custom syntax islands. A second version adds highlighting inside islands, fix-its, and statement-form islands.
11. **Tyhp Link:** a build-time linker and tiered loader (`opcache.preload`, a Tyhp loader, then Composer PSR-4) that uses the checker's type graph to load code faster than Composer autoloading alone.

## Runtime Library Packages

Compiled Tyhp code depends on Composer packages under the `tyhp/` and `tyhpdef/` vendors. See [Runtime Packages Overview](package_intro.md).

- `tyhp/core` — type-system support, generics, typed variables, scalar methods, property accessors, and disposable interfaces
- `tyhp/async` — Promise&lt;T&gt;, event loop, cancellation tokens, deferred execution, and async iterators
- `tyhp/decimal` — the decimal type with operator-overload support for precise arithmetic
- `tyhp/lambda` — expression-tree nodes, visitors, and serialization for parsable lambdas
- `tyhp/io` — non-blocking I/O on the async event loop
- `tyhp/parallel` — worker processes for CPU-heavy or blocking work
- `tyhp/compiler` — Composer shim that installs and runs the compiler
- `tyhpdef/php` — PHP builtin tyhpdefs for PHP 8.2–8.5, plus `tyhpdef/php-ext-*` packages for extensions

## Long-Term Vision

Tyhp's long-term goal is a typed superset of the PHP language in the same role TypeScript has for JavaScript: compile-time types, readable PHP output, and use of the existing PHP runtime and ecosystem.
