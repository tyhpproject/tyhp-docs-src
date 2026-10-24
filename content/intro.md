---
title: 'What is Tyhp?'
---

:::warning Beta
Tyhp **805.1.2-beta.3** is a public beta. The compiler, type checker, emitter, CLI (`build` / `lint` / `init` / `install` / `composer` / `language_server` / `xdebug_proxy` / `generate_tyhpdef`), sourcemaps, and parsable lambdas work. Syntax and package versions may still change.
:::

Tyhp is a typed superset of the PHP language. The compiler type-checks Tyhp source and emits readable PHP. If you know PHP, most of the syntax is already familiar; Tyhp adds required types, null safety, generics, structs, and a handful of other constructs. The usual comparison is TypeScript’s relationship to JavaScript: a superset language that compiles to the original runtime’s language. Tyhp is not PHP, and it is not affiliated with the PHP Group.

All type checking in Tyhp happens at compile time. Tyhp-only type syntax is erased from PHP hints. Some constructs compile to Tyhp-runtime PHP: property hooks when `output.phpVersion` is below 8.4, `async`/`await` (`Promise::_async` / `_await`), structs (PHP `array`, no runtime shape check), and remaining `$x is T` checks (`\Tyhp\Type::is`). Compiled programs that use those features depend on small Composer packages (`tyhp/core`, `tyhp/async`, `tyhp/decimal`, `tyhp/lambda`). PHP builtins are described via `tyhpdef/php`.

## Key Features

- Compile-time type checking and type inference — types are non-nullable by default
- Generics — type-checked at compile time; PHP is a normal class or function unless `T` is tracked
- Structs — named, typed data that compiles to PHP arrays (no runtime shape check)
- Type guards and smart casts — automatic type narrowing after instanceof, is, and null checks without explicit casts
- Async/await syntax — write asynchronous code with Promise-based concurrency that compiles to PHP
- Extension methods — add methods to existing types without modifying their source
- Operator overloading — define custom behavior for arithmetic and comparison operators on your classes
- Type aliases — create named types for complex type expressions
- Property accessors — computed and validated getters/setters with clean syntax
- Disposable pattern — automatic resource cleanup with deterministic disposal via the using pattern
- Compile-time constructs — nameof(), typeof(), and default() evaluated at compile time
- Tyhpdef files — type definition files for describing external PHP libraries, similar to TypeScript's .d.ts files
- Parsable lambdas / expression trees — capture `fn` expressions as data for query builders and similar APIs

## Why Tyhp

Tyhp does not replace the PHP runtime. You compile Tyhp to PHP, then deploy on the PHP you already run. The compiler checks types, nullability, and generic constraints before that output is written.

- Types are compile-time — hints erase; hooks, async, structs, and remaining `Type::is` still emit Tyhp-runtime PHP
- Gradual adoption — mix `.tyhp` and `.php` files in the same project
- PHP interop — Composer packages and PHP extensions via tyhpdef files
- Readable output — emitted PHP is meant to be readable
- Familiar syntax — if you know PHP, you already know most of Tyhp

## How It Works

The Tyhp compiler processes your source files through a multi-phase pipeline: parsing, binding (symbol and scope resolution), type checking, and emission. Each phase catches different categories of errors. The emitter lowers Tyhp-specific constructs into PHP: structs become arrays, `async`/`await` become `Promise::_async` / `_await`, property hooks polyfill when the target is below PHP 8.4, and the rest maps to ordinary PHP or small `\Tyhp\` helpers. The output runs on a standard PHP runtime.

:::note
This documentation is written for experienced PHP developers. Familiarity with PHP syntax, object-oriented programming, and Composer is assumed.
:::
