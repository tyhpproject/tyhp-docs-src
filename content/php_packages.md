---
title: 'Packages for PHP'
---

These pages are for PHP code that calls a `tyhp/*` package. You install the package with Composer and call it like any other PHP library. You do not write Tyhp to use them.

Each package page has its own install command and a quick start that stands on its own. This page is the shared calling convention.

## The packages

| Package | Namespace | PHP page |
|---------|-----------|----------|
| `tyhp/core` | `Tyhp\` | [tyhp/core for PHP](php_package_core.md) |
| `tyhp/async` | `Tyhp\` | [tyhp/async for PHP](php_package_async.md) |
| `tyhp/decimal` | `Tyhp\` | [tyhp/decimal for PHP](php_package_decimal.md) |
| `tyhp/lambda` | `Tyhp\` | [tyhp/lambda for PHP](php_package_lambda.md) |
| `tyhp/io` | `Tyhp\Io\` | [tyhp/io for PHP](php_package_io.md) |
| `tyhp/parallel` | `Tyhp\` | [tyhp/parallel for PHP](php_package_parallel.md) |
| `tyhp/compiler` | — | [tyhp/compiler for PHP](php_package_compiler.md) |
| `tyhp/rhetoric` | `Tyhp\Rhetoric\` | [Rhetoric for PHP](rhetoric_php_getting_started.md) |

`tyhp/rhetoric` is Laravel database access. Its PHP guide is [Rhetoric for PHP](rhetoric_php_getting_started.md): getting started, mapping, querying, saving, migrations, scaffolding, Laravel integration, the translation reference, and coming from EF Core.

Runtime packages other than `tyhp/compiler` are versioned `80N.X.Y`. `80N` is the PHP you run (`802` for 8.2 through `805` for 8.5), and `X.Y` is the package version. Each package page gives the current pin. `tyhp/compiler` uses the compiler's own version.

## Call syntax

```php
use Tyhp\Type as T;
use function Tyhp\async;
use function Tyhp\await;
```

### Types

`T::int`, `T::string`, `T::float`, `T::bool`, `T::null`, `T::void`, `T::mixed`, `T::never`, `T::array`, `T::object`, `T::callable`, `T::iterable`, and `T::resource` are constants. Each one is a `\Tyhp\BuiltIn` value. `\Tyhp\Type` and `\Tyhp\BuiltIn` both implement `\Tyhp\TypeLike`. A parameter typed `\Tyhp\TypeLike|string` accepts either, or a class name.

`BuiltIn` has `nullable()` and `or()`. `\Tyhp\TypeLike` has `toType()` and `or()`. `nullable()` is not a `TypeLike` method. `\Tyhp\Type::nullable($type)` is the static factory.

```php
T::int->nullable();
T::int->or(T::string);
T::list(T::int);
T::map(T::string, T::int);
T::struct(['id' => T::int, 'name' => T::optional(T::string)]);
```

`T::struct` with a field map requires every key, unless that field is `T::optional(...)`. `T::struct('App\\User', ['id' => T::int])` is the same rule with a name. The three-argument form still takes the required-key list as its third argument, including an empty list: `T::struct('App\\User', ['id' => T::int, 'name' => T::string], ['id'])`.

A class is its class-string: `\App\User::class`. A generic class compiled from Tyhp has `Box::type(T::int)`. That nests: `Map::type(T::string, Box::type(T::int))`. A plain PHP class, or a class whose name you have only at runtime, uses `T::generic(\Vendor\Box::class, T::int)`. A type written as text uses `T::parse('array<string, App\\Post>')`.

### Generic methods

A generic method that cannot take its type from the value arguments takes the types first, then the values:

```php
$user = \Tyhp\Json::decode(T::struct(['id' => T::int, 'name' => T::string]))($json);
$rows = $result->rowsAs(T::struct(['id' => T::int]))();
$failed = \Tyhp\Promise::reject()(new \RuntimeException('no'));
```

Omit a type argument when the method can infer it. `Expression::lambda()($body, $parameters, $fn)` is that call with the type argument left null. It is not a one-step call.

These are ordinary PHP calls. The type comes from an argument:

`Tyhp\async`, `Tyhp\await`, `Promise::then`, `Promise::resolved`, `Promise::all`, `Promise::race`, `Promise::any`, `Promise::timeout`, `Promise::whenAll`, `Promise::whenAny`, `Promise::resolve`, `Promise::run`, `Lazy::proxy`, `Lazy::reset`, `Expression::of`, `PropertyPath::on`, `\_expr`, `\_path`.

These stay two-step:

`Json::decode`, `Json::tryDecode` (the by-ref output is not inferred), `Lazy::ghost`, `Expression::lambda`, `PropertyPath::from`, `backedBy`, `Promise::allSettled`, `Promise::batch`, `Promise::reject`, `Promise::rejected`, `Promise::withResolvers`.

```php
$settled = await(\Tyhp\Promise::allSettled()([$ok, $failed]));
$deferred = \Tyhp\Promise::withResolvers(T::int)();
```

### Generic classes

`\Vendor\Box::new(T::int)(42)` binds `int` and runs the constructor. `new \Vendor\Box(42)` uses the class's declared default. `Box::new` has the constructor's visibility. `Box::type(T::int)` returns the `\Tyhp\Type` for that binding.

### A class or callable chosen at runtime

`\Tyhp\Generic::bind($target, ...$types)` accepts a `\Tyhp\Type`, a `\Tyhp\BuiltIn` such as `T::int`, or a class-string. A class name returns a binder. `new()` and calling the binder both run the constructor, once:

```php
$box = \Tyhp\Generic::bind($className, T::int)->new(42);
$same = \Tyhp\Generic::bind($className, T::int)(42);
```

A second `new()` or call throws `\LogicException`. Binding a callable applies the types and returns the closure: `\Tyhp\Generic::bind(\Tyhp\Promise::resolved(...), T::int)(1)`.

`\_gnrc` is the same idea. It accepts a `\Tyhp\Type`, a `\Tyhp\BuiltIn` such as `T::int`, or a class-string:

```php
use Tyhp\Type as T;

$box = \_gnrc($className, T::int)->new(42);
```

`\_gnrc` does not construct. It returns the binder.

### Async

`async(fn (): int => 42)` returns a `\Tyhp\Promise`. `await($promise)` returns the value. Inside `async` it suspends. From ordinary synchronous PHP it runs the event loop until the work is done. `await($promise, 500)` sets a timeout in milliseconds. `$promise->wait()` is the same call as `await($promise)`, including the timeout and an optional `\Tyhp\CancellationToken`.

### Expressions

```php
\_expr(\App\User::class)->age->gte(18)->and()->isActive->same(true);
\_path(\App\User::class)->name;
```

`\_expr` is `\Tyhp\Expression::of`. `\_path` is `\Tyhp\PropertyPath::on`.

## Related

- [tyhp/core for PHP](php_package_core.md)
- [Runtime Packages Overview](package_intro.md) — the same packages as used from Tyhp
- [Rhetoric for PHP](rhetoric_php_getting_started.md)
