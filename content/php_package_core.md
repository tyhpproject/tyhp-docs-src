---
title: 'tyhp/core for PHP'
---

`tyhp/core` is the runtime the other `tyhp/*` packages sit on. From PHP you use it to build types, check values, decode JSON into an array of a known shape, copy properties onto an object, and construct a generic class. The namespace is `Tyhp\`.

Calling conventions that every package shares are on [Packages for PHP](php_packages.md).

## Install

PHP 8.2 or newer. No extension is required. `ext-mbstring` is suggested for Unicode-aware string helpers used by compiled Tyhp; the calls on this page do not need it. `ext-tyhp` is suggested too. It is not required. No Tyhp package requires it. Installing it is recommended. It improves the performance and stability of Tyhp runtime code. The loaded module name is `tyhp`. Install it with PIE, not `composer require`:

```bash
pie install tyhp/ext-tyhp
```

The runtime checks `extension_loaded('tyhp')` once per process, then `phpversion('tyhp') >= 0.1.0`. A missing or older module is ignored. There is no warning. `Type::is`, `Type::parse`, `Generic::bind`, and `Json::decode` still behave as specified.

The package version in `composer.json` is `0.4`. Pick the `80N` prefix for the PHP you run (`802` for 8.2 through `805` for 8.5):

```bash
composer require tyhp/core:805.0.4
```

Composer may ask you to allow the `tyhp/core` plugin. Allow it. What that plugin adds to a Tyhp project is described on [tyhp/compiler for PHP](php_package_compiler.md).

## Quick start

This decodes one JSON object and prints the name. The result is an array.

```php
use Tyhp\Type as T;

require 'vendor/autoload.php';

$json = '{"id": 1, "name": "Ada"}';
$user = \Tyhp\Json::decode(T::struct([
    'id' => T::int,
    'name' => T::string,
]))($json);

echo $user['name'], "\n";
```

`Json::decode` takes the type first, then the JSON text. Invalid JSON throws `\JsonException`. A value that does not match the struct throws `\Tyhp\Exceptions\IncompatibleTypeException`.

## Types

`use Tyhp\Type as T`. The constants and the ways to combine them are listed on [Packages for PHP](php_packages.md#types). A parameter that accepts a type is typed `\Tyhp\TypeLike|string`. `\Tyhp\Type` and `\Tyhp\BuiltIn` implement `\Tyhp\TypeLike`.

| Call | Returns |
|------|---------|
| `T::int`, `T::string`, and the other constants | `\Tyhp\BuiltIn` |
| `T::int->nullable()`, `T::int->or(T::string)` | `\Tyhp\Type` |
| `\Tyhp\Type::nullable($type)` | `\Tyhp\Type`. Static factory. `nullable()` is not a `TypeLike` method. |
| `T::list($value)`, `T::map($key, $value)` | `\Tyhp\Type` |
| `T::struct($fields)`, `T::struct($name, $fields)`, `T::struct($name, $fields, $requiredKeys)` | `\Tyhp\Type`. A field map requires every key unless the field is `T::optional(...)`. The three-argument form uses `$requiredKeys` as the required-key list. |
| `T::optional($type)` | `\Tyhp\Type` for a struct field that may be absent |
| `Box::type(...)`, `T::generic($class, ...$args)` | `\Tyhp\Type` |
| `T::parse($spelling)` | `\Tyhp\Type` from text such as `'array<string, App\\Post>'` |
| `\Tyhp\Type::of($value)` | `\Tyhp\Type` describing a value |
| `\Tyhp\Type::is($value, $type): bool` | Whether the value matches |
| `\Tyhp\Type::check($value, $type): void` | Throws `\Tyhp\Exceptions\IncompatibleTypeException` when it does not |

```php
use Tyhp\Type as T;

\Tyhp\Type::check(['id' => 1], T::struct(['id' => T::int, 'nick' => T::optional(T::string)]));
$same = \Tyhp\Type::is('Ada', T::string);
$parsed = T::parse('array<string, App\\Post>');
```

`\Tyhp\Type::is` and `\Tyhp\Type::check` are ordinary calls. They take the value and the type together. When the `tyhp` module is in use, `Type::is` asks it first. A `null` answer means the module declined, and the PHP walk runs. `Type::parse` asks the module and builds `Type` objects from the graph it returns. A `null` graph uses the PHP parser.

`Generic::bind` stays in PHP. When the module is in use, it asks for a cached closure on entry and stores a result only when that result is a `\Closure`. A class bind is not cached. `Json::decode` has no separate module entry. It checks the decoded value with `Type::is`.

## Generic classes

A generic class compiled from Tyhp exposes two static methods. `Box::new` has the same visibility as the constructor and is not final. `Box::type` is public. Pass one type argument per class type parameter, then call the closure `new` returns with the constructor arguments:

```php
use Tyhp\Type as T;

$box = \Vendor\Box::new(T::int)(42);
$boxType = \Vendor\Box::type(T::int);
```

`new \Vendor\Box(42)` still runs the constructor and uses the class's declared default type arguments. `Box` in this sample is that compiled class. `tyhp/core` does not ship one. A plain PHP class has no `new()` or `type()`; bind it with `\Tyhp\Generic::bind` below, and describe it with `T::generic(\Vendor\Box::class, T::int)` when you only need the type.

## Classes and callables chosen at runtime

`\Tyhp\Generic::bind(mixed $target, \Tyhp\TypeLike|string|null ...$typeArguments): mixed` binds a class-string or a named callable. A class-string returns a binder. `new()` and invoking the binder both construct, and they construct once. The second attempt throws `\LogicException` with the message `Generic instance of '...' has already been constructed.`

```php
use Tyhp\Type as T;

$box = \Tyhp\Generic::bind($className, T::int)->new(42);
```

A callable returns the closure with those types applied:

```php
use Tyhp\Type as T;

$value = \Tyhp\Generic::bind(\Tyhp\Promise::resolved(...), T::int)(1);
```

`\_gnrc($target, \Tyhp\TypeLike|string|null ...$typeArguments)` is the global function with the same role. It does not construct. A builtin constant is `T::int`:

```php
use Tyhp\Type as T;

$box = \_gnrc($className, T::int)->new(42);
```

`\_gnrc` is skipped when a global function of that name already exists. `\Tyhp\Generic::bind` throws `\Tyhp\Exceptions\InvalidTypeException` when the target has no generic runtime stamp, and `\InvalidArgumentException` when `$target` is neither a class name nor a named callable.

## JSON

Both methods take the struct type first.

`\Tyhp\Json::decode($type)(string $json, int $depth = 512, int $flags = 0): array` decodes objects as associative arrays and checks the value against the struct. `\JSON_THROW_ON_ERROR` is always set. Invalid JSON throws `\JsonException`. A well-formed value that does not match throws `\Tyhp\Exceptions\IncompatibleTypeException`.

`\Tyhp\Json::tryDecode($type)(string $json, array &$out, int $depth = 512, int $flags = 0): bool` uses the same rules. The by-ref `$out` is an array, which is why the type is not inferred. On success it writes `$out` and returns `true`. On invalid JSON or a type mismatch it returns `false` and leaves `$out` unchanged.

```php
use Tyhp\Type as T;

$type = T::struct(['id' => T::int, 'name' => T::string]);
$user = [];
if (\Tyhp\Json::tryDecode($type)($json, $user)) {
    echo $user['name'], "\n";
}
```

## Copying properties

`\Tyhp\ObjectHelper::with(object $object, array $properties): object` writes each key of `$properties` onto `$object` and returns the same object. This is an ordinary call. A missing property throws `\Tyhp\Exceptions\PropertyNotFoundException` (`Property '...' does not exist on class '...'.`).

```php
$updated = \Tyhp\ObjectHelper::with($user, ['name' => 'Grace']);
```

## Lazy objects

`\Tyhp\Lazy` builds a PHP 8.4 lazy object. On PHP 8.2 and 8.3 the same methods run the callback immediately and return an ordinary object.

`Lazy::ghost` takes the class first. The initializer runs on that instance:

```php
$user = \Tyhp\Lazy::ghost(\App\User::class)(function (\App\User $user): void {
    $user->name = 'Ada';
});
```

`Lazy::proxy` and `Lazy::reset` are ordinary calls. The factory's return type is the instance type:

```php
$proxy = \Tyhp\Lazy::proxy(function (\App\User $shell): \App\User {
    return new \App\User('Ada');
});

\Tyhp\Lazy::reset($proxy, function (\App\User $user): void {
    $user->name = 'Grace';
});
```

`Lazy::isLazy(object $object): bool` and `Lazy::initialize($object)` are ordinary calls. On PHP 8.2 and 8.3, `isLazy` returns `false`.

## Contracts you can implement

| Interface | Method |
|-----------|--------|
| `\Tyhp\Contracts\IsDisposable` | `dispose(): void` |
| `\Tyhp\Contracts\Convertible` | Marker. Conversion goes through the interfaces below. |
| `\Tyhp\Contracts\StringConvertible` | `__toString(): string` (`\Stringable`) |
| `\Tyhp\Contracts\IntConvertible` | `__toInt(): int` |
| `\Tyhp\Contracts\FloatConvertible` | `__toFloat(): float` |
| `\Tyhp\Contracts\BoolConvertible` | `__toBool(): bool` |

## Errors

| Exception | When |
|-----------|------|
| `\JsonException` | `Json::decode` was given text that is not JSON. |
| `\Tyhp\Exceptions\IncompatibleTypeException` | A value does not match the type passed to `Json::decode`, `Type::check`, or a similar check. The message is `Incompatible type: expected ..., got ...`. |
| `\Tyhp\Exceptions\InvalidTypeException` | A type argument or a `Generic::bind` target is not usable. It extends `\LogicException`. |
| `\Tyhp\Exceptions\PropertyNotFoundException` | `ObjectHelper::with` named a property the object does not have. |
| `\LogicException` | A `Generic::bind` binder was asked to construct a second time. |

## Related

- [Packages for PHP](php_packages.md) — types, two-step calls, `Generic::bind`
- [tyhp/async for PHP](php_package_async.md), [tyhp/decimal for PHP](php_package_decimal.md), [tyhp/lambda for PHP](php_package_lambda.md)
- [The tyhp/core Package](package_core.md) — the same package as used from Tyhp
