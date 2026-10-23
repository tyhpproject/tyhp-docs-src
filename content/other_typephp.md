---
title: 'TypePHP (Swoole AOT)'
---

TypePHP, formerly the Swoole AOT compiler, is an ahead-of-time compiler from the Swoole team that turns PHP-syntax source into native machine code. Tyhp and TypePHP both start from PHP syntax and add compile-time type information, but they produce very different output: Tyhp emits PHP, and TypePHP emits native binaries.

## What TypePHP Is

TypePHP lowers PHP source to C++17 and then compiles it with GCC, Clang, or MSVC. A project can be built as a native executable, a loadable PHP extension, or a shared library. Compiled user code runs as machine code; built-in functions, extensions, and dynamic operations go through the Zend Engine, which is embedded in the output through Swoole's PHPX library. TypePHP adds native scalar storage, typed containers (`std::vector`, `std::map`, and others), `bigInt` / `decimal` / `bigFloat` numerics, and methods callable directly on primitive values. It supports a defined subset of PHP, so existing code usually needs changes before it compiles. The compiler is written in PHP and is self-hosting. It is open source under GPL-3.0.

## Similarities

- Both start from PHP syntax and add static type information checked at compile time
- Both use strict scalar typing rather than PHP's weak coercion
- Both let you call methods on values of types you do not own (Tyhp extension methods; TypePHP universal methods)
- Both offer exact decimal arithmetic (Tyhp through `tyhp/decimal`; TypePHP through its built-in `decimal` type)
- Both restrict some highly dynamic PHP features so the compiler can reason about the program
- Both work with Composer packages

## Differences

## Output and Runtime

Tyhp emits readable PHP 8.2–8.5 that runs on a standard PHP runtime (php-fpm, CLI, or any SAPI). The compiled output performs like any other PHP code. TypePHP's goal is native performance: it ships machine code, and binary-mode executables start without the PHP CLI while still linking PHPX, `libphp`, and any configured native libraries.

## Build and Deployment

A Tyhp deployment server needs only PHP and the Composer dependencies; the compiler runs at build time. TypePHP builds need PHP 8.4–8.5 with development headers and the embed library, a C++17 toolchain, CMake, and GMP/MPFR. Its deployment package carries the native binary and the libraries it links.

## Type System Focus

Tyhp's main feature is its type system: required types on every parameter, property, and return; non-nullable by default; generics; structs; type aliases; union and literal types; and Tyhpdef files for describing existing PHP libraries. TypePHP uses type information primarily to drive native code generation, such as mapping `int`, `float`, and `bool` to C++ scalars and specializing typed containers.

## Program Structure

Tyhp files can contain top-level statements, as PHP files can. In TypePHP, global scope is declaration-only, and binary mode requires a `main()` function.

## Readable Output vs. Source Protection

Tyhp output is ordinary PHP you can read and debug with Xdebug (through sourcemaps). TypePHP output is machine code, which also protects the shipped source.

## Implementation and License

Tyhp's compiler is written in C# (.NET) and is licensed under Apache 2.0. TypePHP's compiler is written in PHP and is licensed under GPL-3.0.

## When to Choose TypePHP

TypePHP fits CPU-bound or numeric workloads, standalone executables, PHP extensions written in PHP syntax, and cases where shipping compiled binaries instead of source matters. Tyhp fits projects that want a stricter, richer type system while staying on standard PHP hosting and the existing PHP toolchain.

## Links

- Website: [swoole.com/aot](https://swoole.com/aot/en/)
- Source: [github.com/swoole/typephp](https://github.com/swoole/typephp)
