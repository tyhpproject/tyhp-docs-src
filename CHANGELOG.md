# Changelog

Notable changes to the Tyhp documentation published at [tyhplang.com](https://tyhplang.com) and to the site generator in this repository. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The docs are not versioned; releases are dated by publish.

## [Unreleased]

### Added

- Packages for PHP: an index and one page each for `tyhp/core`, `tyhp/async`, `tyhp/decimal`, `tyhp/lambda`, `tyhp/io`, `tyhp/parallel`, and `tyhp/compiler`, for PHP callers. Samples use `T::int`, types-first calls such as `Json::decode(T::struct([...]))($json)` and `Promise::allSettled()($promises)`, and plain calls such as `await(async(...))` and `\_expr`.
- Lazy Objects: `lazy new`, `\Tyhp\Lazy`, and `Generic::bind()->ghost()` when the class or its type arguments are chosen at runtime. Disposables, Generics, the tyhp/core page, and the Quick Reference point at that page, including that an uninitialized lazy object is not disposed.
- Rhetoric: getting started, mapping, querying, saving, migrations, scaffolding, Laravel integration, the translation reference, and coming from EF Core.
- Rhetoric for PHP: the same topics for callers who do not write Tyhp (`rhetoric_php_getting_started.md` and the other `rhetoric_php_*.md` pages). Runtime Packages Overview and Composer Runtime Packages list `tyhp/rhetoric`.

### Changed

- Types and Locals, New Object Declaration Syntax, Structs, Type Narrowing and Guards, Classes in Tyhpdef, CLI: Tyhpdef Generation, the tyhp/core package page, and the Roadmap: `unset` of a local, a typed instance property, or a static property is TYHP4158. Drop a value with `?T = null`. A typed static property needs an initializer (TYHP4418). After construction, every typed instance storage property is initialized (TYHP4419), and a class that declares no constructor runs the nearest ancestor constructor. Array-offset `unset` and unsetting an optional struct field stay legal. `#[\Tyhp\AllowUnset]` is no longer part of `tyhp/core`. A `.tyhpdef` may still document a PHP static property with no default.
- Diagnostic Code Reference: TYHP4158, TYHP4418, and TYHP4419. TYHP4157 remains the read of a property that construction did not initialize.
- Structs, the with keyword, type aliases, the Quick Reference, the syntax FAQ, and struct examples on the tyhp/core, tyhp/io, and tyhp/parallel pages: a struct is constructed with `new Name[prop => value]`, including generic and anonymous structs and spreading another struct.
- Diagnostic Code Reference: TYHP4412–TYHP4417, and TYHP4159 names the construction form that was written.
- Parsable Lambdas, the tyhp/lambda package, tyhp/lambda for PHP, the interop contract, tyhp/core for PHP, the tyhp/io package, tyhp/io for PHP, Runtime Packages Overview, the tyhp/parallel package, and Extensions: the optional `tyhp` module (`pie install tyhp/ext-tyhp`) is recommended and never required. PHP packages build expression trees with the fluent API, and PHP that knows the module is loaded may pass a closure. DNS uses the module when it is loaded and goes through `Offload` otherwise.
- Packages for PHP, tyhp/core for PHP, the tyhp/core package page, and Rhetoric for PHP getting started: `_gnrc` takes the same type arguments as `Generic::bind`, including `T::int`.
- Rhetoric for PHP: samples call `table(Post::class)()`, `model(Post::class)()`, `belongsTo(Blog::class)($path)`, `ContextFactory::new(Context::class)()`, `EloquentQuery::query(Model::class)()`, `select(Post::class)($sql)`, and `transaction(T::int)($callback)`. `entry($model)` and `Expression::of` are ordinary calls (`rhetoric_php_getting_started.md`, and the mapping, querying, saving, Laravel, translation, and coming-from-EF pages).
- Generics, tyhp/core, tyhp/async, tyhp/lambda, the Quick Reference, and the pages that show a PHP generic call: PHP uses `T::int`, `Box::new(T::int)(42)`, `Box::type(T::int)`, binder-first `name(types)(args)` (`Json::decode`, `Promise::reject()($e)`, `Promise::withResolvers(T::int)()`), and plain `#[\Tyhp\InferGeneric]` calls (`await(async(...))`, `_expr`). `Type::struct('Name', [...])` requires every key unless the field is `T::optional`. Diagnostic Code Reference regenerated, including TYHP4404–TYHP4408.
- The tyhp/async Package: PHP waits with `\Tyhp\await($promise, $timeoutMs, $token)` or `$promise->wait($timeoutMs, $token)`. Both suspend inside a loop fiber and run the loop from synchronous PHP. `await` has no `__tyhpGeneric` companion; `async` does.
- Diagnostic Code Reference: regenerated, including TYHP4402 and TYHP4403.
- Compile-Time Constructs and New and Changed Types: `nameof(Type::$prop)` is `__PropertyName<Type>` and can be an attribute argument; a class reference is `Type::class` or `T::class` (`__ClassName<Type>`).
- Parsable Lambdas and Expression Trees: an extension method call stays a `MethodCallExpression` (`$title->startsWith($prefix)`); the extension body is not part of the tree.
- Roadmap: emitted docblocks and templates are marked shipped, and Tier 3 now lists the changes that land before the first stable release (struct initializers, no uninitialized storage, `operator default()`, scalar-conversion contracts, abstract members for trait requirements, and pre-stable compatibility changes). Future Plans is in planned order and adds glob exclusions, pipe operator output, declaration-site variance, and runtime closure and fiber checks.

### Fixed

- tyhp/io for PHP: the `Process` section describes `runAsync` and `mustRunAsync` as returning a promise of a `ProcessResult` array. `mustRunAsync` throws `ProcessFailedException` when `exitCode` is not 0.
- Diagnostic Code Reference: TYHP4412 suggests `new Name() with [...]` only when that name is a class that can be constructed.
- Packages for PHP, tyhp/async for PHP, tyhp/lambda for PHP, and Lazy Objects: those pages state the call or syntax to write.

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
