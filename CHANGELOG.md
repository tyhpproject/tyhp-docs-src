# Changelog

Notable changes to the Tyhp documentation published at [tyhplang.com](https://tyhplang.com) and to the site generator in this repository. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The docs are not versioned; releases are dated by publish.

## [Unreleased]

## 2026-11-04

### Added

- Emitted Docblocks and Templates: PHPStan/Psalm tags on compiled PHP (`emit.docblocks`, `emit.docblockDialect`), and `<?=` as a Tyhp echo with inline HTML in `.tyhp` files.
- Parsable Lambdas and Expression Trees: a Nested Lambdas section, and array literals and `?->` method calls in the list of supported expressions.
- The tyhp/lambda Package: reference entries for `LambdaExpression`, `ArrayExpression`, and `NullSafeMethodCallExpression`, their serialized forms, and `ExpressionShape` / `ExpressionSerializer::shapeKey()` for caching a translation per tree shape.
- Generics: a Declared property types at runtime section on `#[\Tyhp\PropertyType]` and `\Tyhp\Type::fromProperty()`.
- Type Narrowing and Guards: an Assertions section (`\assert()`), loose `!= null` narrowing, `match (true)` / `switch (true)` arms, early exits from `if` / `else`, and property-path narrowing.
- Types and Locals: member access on a possibly null value must be narrowed first (TYHP4198).
- Type Aliases: template string holes that name aliases, which hole types are allowed (TYHP4199), numeric hole text, and assigning interpolated strings to a template type, including nullable hole values.
- PHP Version Gating: a Declarations that need a newer PHP section (readonly property defaults, TYHP4378; enum `__debugInfo()`, TYHP4379) and both codes in the diagnostics table.
- Composer Packages: compiled `tyhp/*` helpers are not published for PHP 8.0 or 8.1, and `build.updateComposer` reports TYHP7108 for those targets.
- TypePHP (Runtime Type Checker): a comparison page for the `typephp/typephp` runtime PHPDoc checker, linked from What is Tyhp? and from the TypePHP (Swoole AOT) page.

### Changed

- Previous Releases, What is Tyhp?, Installing Tyhp, Release Planning, Roadmap, and Composer Runtime Packages: the current compiler is 805.1.2-beta.4.
- Project Options, CLI: Build, the Interop Contract, FAQ: General, What is Tyhp?, the Open Tag page, Lost and Changed Functionality, and the Quick Reference: `emit.docblocks` and `emit.docblockDialect`, running PHPStan or Psalm on emitted PHP, and `<?=` in a `.tyhp` file as a Tyhp echo. Roadmap no longer lists those docblocks as unscheduled.
- The Open Tag page and Project Options: in a tagless project, a `.tyhp` file starting with `<?tyhp` is a tagged template (an empty first section is allowed, then inline HTML and `<?=` in source order, including inside a function or control-flow block, and a later `<?tyhp`). Any other `.tyhp` file is parsed with no open tag, so `<?tyhp` there is not accepted. `<?php` blocks report TYHP2005.
- The with Keyword, Build Configuration, Project Options, and PHP Magic Methods: readonly `new … with` and `clone … with` below PHP 8.3 report TYHP4400; `clone … with` on a `readonly class` below 8.5 reports TYHP4401. The experimental flag covers PHP 8.3–8.4 on a class that is not readonly. Diagnostic Code Reference regenerated, including TYHP4400 and TYHP4401.
- Roadmap: Tier 2 is marked done, Tier 3 adds promise interop, a new Future Plans section lists unscheduled features, and the runtime package list includes `tyhp/io`, `tyhp/parallel`, `tyhp/compiler`, and the `tyhpdef/php-ext-*` packages.
- Parsable Lambdas and Expression Trees: compiled PHP examples show the fluent `\Tyhp\Expr` / `PropertyPath::on()` output, generic `R` inference covers `PropertyPath`, and the TYHP4322 table lists the newly rejected constructs (a class held in a variable, a variable method name, named and unpacked arguments, array spread).
- Interop Contract (CLI): the expression-tree emit section describes the fluent builder output, and `\Tyhp\PropertyType` is listed as a runtime-visible attribute.
- Diagnostic Code Reference: regenerated, with entries for TYHP2005, TYHP4198, TYHP4199, TYHP4378, TYHP4379, TYHP4380, TYHP5024, and TYHP7108, updated text for TYHP4011, TYHP4021, TYHP4024, TYHP4101, TYHP4109, and TYHP4322, and TYHP4108 removed.
- The with Keyword: the readonly section states that every instance property of a `readonly class`, including promoted parameters, follows the readonly rules.
- The tyhp/async Package: `EventLoop::run()` infers its result from the root promise, including `Promise<void>`.
- Installing Tyhp: `tyhpdef/php` is described as covering PHP 8.2–8.5 with version-gated declarations, not as a PHP 8.2 baseline, and non-core extensions are pointed to the `tyhpdef/php-ext-*` packages.

### Fixed

- Composer Runtime Packages, Installing Tyhp, The tyhp/io Package, The tyhp/parallel Package, and Previous Releases: the quoted runtime versions match what is published (`tyhp/*` `0.3`, for example `804.0.3`, and `tyhpdef/php` `0.0.3`).
- The `<?tyhp` and `<?tyhpdef` Open Tags: `.tyhp` files no longer claim to allow `<?php` blocks; PHP code goes in `.php` files.
- Structs: named structs are described as registering a runtime type descriptor (`\Tyhp\Type::register`) in `_functions.php`, not as producing no PHP at all.
- Dark mode: code inside note, tip, warning, and danger callouts is readable, callouts use dark backgrounds, and the sidebar menu on phones is no longer transparent.

## Baseline - 2026-11-02

Tracking starts at commit `402b537`. Earlier changes are not listed.
