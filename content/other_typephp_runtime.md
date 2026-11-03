---
title: 'TypePHP (Runtime Type Checker)'
---

TypePHP (`typephp/typephp`) is a pure-PHP library that enforces PHPDoc types while your code runs. It is a different project from [TypePHP (Swoole AOT)](other_typephp.md). Tyhp and this TypePHP both bring richer types such as generics and array shapes to PHP code, but they check them at different times: Tyhp checks types when it compiles, and TypePHP checks values when the code runs.

## What TypePHP Is

TypePHP installs as a Composer dev dependency and starts with the Composer autoloader. A stream wrapper intercepts PHP files as they load, parses them with `nikic/php-parser`, and injects checks based on the PHPDoc annotations already in the code (`@param`, `@return`, `@var`, `@template`). It supports generics, array shapes, `key-of` / `value-of`, and scalar refinements such as `positive-int` and `non-empty-string`. Generics are reified: the type arguments of each object are tracked at runtime in a `WeakMap`. Injected checks stay on the original lines, so stack traces point at the right place. A violation can throw a `TypeError`, log a warning, or be collected into a JSON audit report. It needs no build step or C extension, runs on PHP 8.1 and later, and is open source under the MIT License.

## Similarities

- Both add generics, array shapes, and other types that PHP's native type declarations cannot express
- Both understand PHPStan- and Psalm-style PHPDoc types (Tyhp reads them when [generating tyhpdefs](cli_tyhpdefGeneration.md) for existing packages)
- Both work with existing Composer projects and standard PHP hosting
- Both can check generic type arguments at runtime (Tyhp through the opt-in `build.runtimeGenericChecks` option)

## Differences

## When Types Are Checked

Tyhp checks the whole program before it writes any PHP. A type error is a compile error, even on a code path no test runs. TypePHP checks the values that actually pass through a function, parameter, or return while the code runs, so it reports the mistakes your tests and traffic reach.

## Syntax

Tyhp is a typed superset of the PHP language: types are part of the syntax, and you write `.tyhp` files. TypePHP adds no syntax. Types stay in PHPDoc comments in ordinary `.php` files.

## Build and Adoption

Tyhp has a compile step and is adopted file by file: `.tyhp` files are checked, and `.php` files in the same project pass through unchanged. TypePHP has no build step. It is added to a project with `composer require --dev` and checks the files its configuration includes. Its audit mode lets an existing codebase run its test suite and collect every violation instead of stopping at the first one.

## Generics

Tyhp generics are checked at compile time and erased in the PHP output. Runtime tracking is emitted only where the program needs the type arguments, such as a property typed `T` or a `typeof(T)` call. See [Generics](tyhp_0500_generics.md). TypePHP generics exist only at runtime: each object's type arguments are bound when it is created, and checked on each call.

## Language Features

Beyond types, Tyhp adds language features that compile to PHP, such as structs, async/await, extension methods, operator overloads, and expression trees. TypePHP focuses on type enforcement and does not change the language.

## Implementation and License

Tyhp's compiler is written in C# (.NET) and is licensed under Apache 2.0. TypePHP is written in PHP and is licensed under MIT.

## When to Choose TypePHP

TypePHP fits existing PHP codebases that already have PHPDoc types and want them enforced without changing syntax or adding a build step, and audits of legacy code through its test suite. Tyhp fits projects that want type errors reported before the code runs, types in the syntax, and the other language features Tyhp adds.

## Links

- Website: [typephp.dev](https://typephp.dev/)
- Source: [github.com/typephp-php/typephp](https://github.com/typephp-php/typephp)
