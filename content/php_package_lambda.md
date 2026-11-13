---
title: 'tyhp/lambda for PHP'
---

`tyhp/lambda` builds an expression tree or a property path for a library method that expects one. Build it with the fluent methods on this page and pass the finished object. That is the form to ship in a Composer package, and in any other PHP whose later process you do not control. You cannot know whether that process has the `tyhp` module loaded, or which version is loaded. The fluent form is also the one to use for speed and stability, whether or not the module is installed. The namespace is `Tyhp\`. It depends on `tyhp/core`.

Shared call syntax is on [Packages for PHP](php_packages.md).

## Install

PHP 8.2 or newer. No extension is required. The package version is `0.4`:

```bash
composer require tyhp/lambda:805.0.4
```

`ext-tyhp` is not required. `tyhp/lambda` suggests it. No Tyhp package requires it. Installing it is recommended. It improves the performance and stability of Tyhp runtime code. The loaded module name is `tyhp`. Install it with PIE, not `composer require`:

```bash
pie install tyhp/ext-tyhp
```

The runtime checks `extension_loaded('tyhp')` once per process, then `phpversion('tyhp') >= 0.1.0`. A missing or older module is ignored. There is no warning. The calls on this page still behave as specified.

## Quick start

`\_expr` starts a property path on a class name. `age` is property access. `gte(18)` finishes a comparison. The result is the tree.

```php
require 'vendor/autoload.php';

$adults = \_expr(\App\User::class)->age->gte(18);
```

The class does not have to be loaded to build the tree. Call the object, or pass it to the library method that accepts an expression.

## Which calls take types first

Ordinary calls: `\_expr`, `\_path`, `\Tyhp\Expression::of`, `\Tyhp\PropertyPath::on`.

Types first: `\Tyhp\Expression::lambda`, `\Tyhp\PropertyPath::from`, and `backedBy` on a property-path builder.

## Property paths and comparisons

`\_expr(string $class, string|array ...$segments): \Tyhp\PropertyPathBuilder` is `\Tyhp\Expression::of($class, ...$segments)`. Both are ordinary calls. `\_expr` is skipped when a global function of that name already exists.

`->$name` uses `__get` and appends a property. `prop(string $name, bool $nullSafe = false)` is the same step. `nullSafe()` marks the next property as `?->`.

A comparison returns an `\Tyhp\ExpressionBuilder`. These compare the current path:

| Method | Operator |
|--------|----------|
| `gt`, `gte`, `lt`, `lte` | `>`, `>=`, `<`, `<=` |
| `eq`, `same` | `===` |
| `neq`, `notSame` | `!==` |
| `isNull` | `=== null` |
| `isNotNull` | `!== null` |

`and($other = null)` and `or($other = null)` combine with `&&` and `||`. With no argument they start the right-hand side. Property access then builds that side, and a comparison completes it.

```php
$filter = \_expr(\App\User::class)
    ->age->gte(18)
    ->and()->isActive->same(true);
```

`\_path(string $class): \Tyhp\PropertyPathBuilder` is `\Tyhp\PropertyPath::on($class)`. It is a path with no comparison:

```php
$name = \_path(\App\User::class)->address->city;
```

A property path does not accept a method call. Build that tree from `\Tyhp\Expr`:

```php
$starts = \Tyhp\Expr::param('user', \App\User::class)->name->call('startsWith', 'A');
```

## Passing a closure

When you know the process that runs this PHP has `tyhp` loaded at `0.1.0` or newer, you may pass a closure to a compiled method's `Expression` or `PropertyPath` parameter. That is the easier PHP spelling in that case. `tyhp build` widens a plain `Expression` or `PropertyPath` parameter to `\Tyhp\Expression|\Closure` or `\Tyhp\PropertyPath|\Closure`, and the method calls `\Tyhp\Expression::fromClosure` or `\Tyhp\PropertyPath::fromClosure` when the argument is a closure. A promoted constructor parameter, a by-reference or variadic parameter, a property-hook parameter, a parameter typed as a union with a type other than `null`, and a parameter with `#[\Tyhp\PhpType]` keep their declared type, so build the tree for those.

```php
$adults = fn (\App\User $user) => $user->age >= 18;
$name = fn (\App\User $user) => $user->name;
```

`fromClosure` reads the tree from the module when the check above passes. Otherwise it tokenizes the closure's source. A closure the reader cannot read throws `\InvalidArgumentException` on both paths. A return type PHP checks, such as `: bool`, makes a closure unreadable, and so does a `use` clause. Write an arrow function, or a `function` whose body is one `return`, with no declared return type. `\Tyhp\PropertyPath::fromClosure` needs a single parameter and a property chain.

`tyhp build` of a Tyhp `fn` emits the fluent chain (`\Tyhp\Expr::param(...)->…->backedBy(fn)` or `\Tyhp\PropertyPath::on(...)->…->backedBy(fn)`), the same whether or not the module is loaded.

## Closures you already have

The closures in this section are the executable half of a tree you already built. They are not read as the tree.

`\Tyhp\PropertyPath::from()(string $sourceType, array $path, \Closure $callable, array $nullSafeFlags = [])` takes the callable's type first, omitted when you want it read from the closure:

```php
$path = \Tyhp\PropertyPath::from()(
    \App\User::class,
    ['name'],
    fn (\App\User $user): string => $user->name,
);
```

`backedBy()` on the builder stores a closure for a path you built fluently. The type argument comes first and is omitted here:

```php
$path = \_path(\App\User::class)->name->backedBy()(
    fn (\App\User $user): string => $user->name,
);
```

`\Tyhp\Expression::lambda()(\Tyhp\Expression\ExpressionNode $body, array $parameters, ?\Closure $callable = null)` builds a tree from nodes. The type argument is omitted so it is read from `$callable` when you pass one:

```php
$parameter = new \Tyhp\Expression\ParameterExpression('user', \App\User::class, 0);
$body = new \Tyhp\Expression\PropertyAccessExpression($parameter, 'age');
$expr = \Tyhp\Expression::lambda()(
    $body,
    [$parameter],
    fn (\App\User $user): mixed => $user->age,
);
```

The finished object is what you pass. `$expr->body` is the root node. `$expr->parameters` is the parameter list.

## Nodes

Every node extends `\Tyhp\Expression\ExpressionNode` and has `string $type` (the value's type spelling) and `string $nodeType`. An `\Tyhp\Expression` adds `$body`, `$parameters`, and `$returnType`. `\Tyhp\Expression\LambdaExpression` has `$parameters`, `$body`, and `$returnType`. `\Tyhp\Expression\ArrayExpression` has `$items`, each an `\Tyhp\Expression\ArrayItem` with `$value` and `$key` (`null` when the key is the next integer).

| Class | Fields a walker reads |
|-------|------------------------|
| `ParameterExpression` | `$name`, `$paramType`, `$index` |
| `PropertyAccessExpression`, `NullSafeAccessExpression` | `$object`, `$property` |
| `MethodCallExpression`, `NullSafeMethodCallExpression` | `$object`, `$method`, `$arguments` |
| `StaticMethodCallExpression` | `$class`, `$method`, `$arguments` |
| `BinaryExpression` | `$left`, `$operator`, `$right` |
| `UnaryExpression` | `$operator`, `$operand`, `$isPrefix` |
| `ConstantExpression` | `$value` |
| `TernaryExpression` | `$condition`, `$ifTrue`, `$ifFalse` |
| `CoalesceExpression` | `$left`, `$right` |
| `ArrayAccessExpression` | `$array`, `$index` |
| `CastExpression` | `$targetType`, `$operand` |
| `NewExpression` | `$class`, `$arguments` |
| `InstanceofExpression` | `$operand`, `$targetType` |
| `ArrayExpression` | `$items` |
| `LambdaExpression` | `$parameters`, `$body`, `$returnType` |

## Failures

These throw `\LogicException`:

| Situation | Message |
|-----------|---------|
| A comparison on `Expression::of` / `\_expr` before any property | `Expression::of() requires at least one property before a comparison.` |
| Property access or `prop()` on a completed builder | `Cannot access properties on a completed expression. Call and()/or() to continue, or start from Expression::of().` |
| A comparison on a completed builder | `Comparisons on ExpressionBuilder require and()/or() followed by a property path, or start from Expression::of().` |
| A comparison immediately after `and()` / `or()` | `Continue the property path after and()/or() before comparing.` |
| `and()` / `or()` while a right-hand path is still open | `Finish the property comparison before calling and()/or().` |
| `and()` / `or()` immediately after another `and()` / `or()` | `Finish the right-hand side after and()/or() before combining further.` |

## Related

- [Packages for PHP](php_packages.md)
- [tyhp/core for PHP](php_package_core.md)
- [The tyhp/lambda Package](package_lambda.md) — the same package as used from Tyhp
