---
title: Roadmap
status:
  tier: 3
  story: '30'
  state: complete
---

Tyhp is built in a deliberately ordered sequence of stories, grouped into four tiers. The guiding principle is a thin vertical slice that compiles and runs end-to-end as early as possible.

**This beta (805.1.2-beta.3)** Stories **27** (object shapes), **27.1** (callable shapes + `type Name = struct { };`), **27.2** (block-target extension syntax), and **27.3** (split runtime / docs / AI developer guide / IDE plugin into dedicated git repos) are next, still in this beta, before deferred Story 22. Other stories remain planned unless noted below.

Stories are numbered contiguously from 01 to 30 with additive sub-stories (`08.5`, `10.5`, `14.5`, `16.5`, `19.5`, `20.5`, `27.1`, `27.2`, `27.3`). Each documentation page carries a Tier/Story badge.

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

## Tier 2 — Developer Experience & Ecosystem (this beta)

1. **Story 17 — Sourcemap generation** (shipped).
2. **Story 18 — XDebug proxy** (shipped).
3. **Story 19 — Language Server (LSP)** (shipped; stdio only).
4. **Story 19.5 — IDE clients (VS Code and PhpStorm)** (shipped).
5. **Story 20 — Tyhpdef generator** (C# CLI integration; `generate_tyhpdef` and `package.tyhpdef` on `tyhp build` shipped, plus `--php-targets` gated emit).
6. **Story 20.5 — PHP version gating** (`declare(php=…)` / `#[\Tyhp\Php]`).
7. **Story 21 — PHP extension Composer packages** (`tyhpdef/php` + `tyhpdef/php-ext-*`; one package per extension across 8.2–8.5 with `declare(php=…)` / `#[\Tyhp\Php]` gates). Includes the built-in scalar method catalog (`$name->toUpper()`, …) via `global use extension \Tyhp\StringExtensions`.
8. **Story 21.1 – 21.12** — Addendum work for tier 2 (shipped).
9. **Story 27 — Object shapes and `__New<T>`** (next).
10. **Story 27.1 — Callable shapes and `type Name = struct { };`** (after 27).
11. **Story 27.2 — Block-target extension syntax** (`extension Name extends Type`; after 27.1 in numbering, may run in parallel).
12. **Story 27.3 — Split runtime, docs, AI developer guide, and IDE plugin into dedicated git repos** (after 27.2).
13. **Story 22 — Web playground** (live .tyhp → PHP) — DEFERRED, not in this beta.

## Tier 3 — Advanced — not in this beta

1. **Story 23 — Compiler optimizer (MVP).**
2. **Story 24 — Advanced optimizations.**
3. **Story 25 — `internal` project-boundary enforcement and the internals overlay (`includeInternals`)** (the modifier itself already hides symbols from published `package.tyhpdef`; see [The internal Visibility Modifier](tyhp_3100_internalModifier.md)).
4. **Story 26 — Null-conditional chaining with assignment.**
5. **Story 29 — Tyhp reflection API** (sourcemap-backed).
6. **Story 30 — Documentation & polish** (final capstone).

> Story 28 (generic defaults) shipped with the alpha; see Tier 1 above.

## Runtime Library Packages

Compiled Tyhp code depends on Composer packages under the `tyhp/` vendor (GitHub org `tyhpproject`):

- `tyhp/core` — type-system support, typed variables, property accessors, and disposable interfaces
- `tyhp/async` — Promise&lt;T&gt;, event loop, cancellation tokens, deferred execution, and async iterators
- `tyhp/decimal` — the decimal type with operator-overload support for precise arithmetic
- `tyhp/lambda` — expression-tree nodes, visitors, and serialization for parsable lambdas
- `tyhpdef/php` — PHP builtin tyhpdefs (8.2 baseline in the alpha)

## Long-Term Vision

Tyhp's long-term goal is a typed superset of the PHP language in the same role TypeScript has for JavaScript: compile-time types, readable PHP output, and use of the existing PHP runtime and ecosystem.
