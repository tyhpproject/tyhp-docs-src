---
title: PXP
---

PXP is a project that adds syntax on top of PHP and compiles the result to PHP. Tyhp is also a superset of the PHP language that compiles to PHP. The two differ in scope, approach, and focus.

## What PXP Is

PXP (pxp-lang) is an open-source project that provides a Rust-based parser and compiler for an extended PHP syntax. It began as a high-performance PHP parser and has grown into a language project that adds features like generics to PHP. PXP's tooling infrastructure — parser, AST, and formatter — is written in Rust, giving it strong performance characteristics for parsing and analysis.

## Similarities

- Both are supersets of the PHP language that compile to PHP
- Both aim to add features that PHP currently lacks
- Both support generics as a key language addition
- Both produce standard PHP output that runs on any PHP runtime

## Differences

- Tyhp's primary focus is a comprehensive, enforced type system — every variable, parameter, property, and return type must be typed. PXP focuses on adding syntax features without requiring types everywhere.
- Tyhp includes a compile-time type checker. PXP's type handling is more limited in scope.
- Tyhp provides Tyhpdef files for describing external PHP libraries and Composer packages with full type information, similar to TypeScript's .d.ts files.
- Tyhp includes a runtime library (tyhp/core, tyhp/async, tyhp/decimal, tyhp/lambda) for features that require runtime support.
- Tyhp adds a broader set of language features beyond generics: structs, operator overloads, conversion operators, extension methods, async/await, disposables, expression trees, and more.
- Tyhp's compiler is written in C# (.NET), while PXP's tooling is written in Rust.
- Tyhp includes a linter (`tyhp lint`), a language server (`tyhp language_server`), and sourcemap debugging (`build.generateSourcemap` with `tyhp xdebug_proxy`).

## Complementary Strengths

PXP's Rust-based parser is aimed at PHP-adjacent tooling. Tyhp is a language with a type checker, compiler pipeline, runtime packages, and development tools. Both compile to PHP.
