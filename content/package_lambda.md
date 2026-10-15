---
title: 'The tyhp/lambda Package'
---

The `tyhp/lambda` package is the runtime behind [parsable lambdas](tyhp_3000_parsableLambdas.md). When you pass an inline `fn` to a parameter typed `Expression<callable(T): R>` or `PropertyPath<callable(T): R>`, the compiler builds objects from this package that describe the lambda's code as a tree. Your library receives that tree, inspects it, and translates it into something else: a SQL `WHERE` clause, a validation rule, a column name, a serialized query sent to another service.

This page is the API reference and usage guide for the package. It covers every public class, the node types that make up a tree, how to walk and translate a tree, the fluent builders that let plain PHP code create trees, and the JSON format produced by the serializer. For the language side — which `fn` bodies can become trees, how types are inferred, and which compiler errors you can get — see [Parsable Lambdas and Expression Trees](tyhp_3000_parsableLambdas.md).

## Installation

`tyhp build` adds `tyhp/lambda` to your `composer.json` when your compiled code uses `Expression` or `PropertyPath`, so you rarely add it by hand. The package depends on `tyhp/core`. Version pins follow the same `80N.X.Y` scheme as the other compiled `tyhp/*` packages; [Composer Runtime Packages](project_composerPackages.md) explains which pin to use, and [Runtime Packages Overview](package_intro.md) shows how the packages relate.

The package uses three namespaces:

| Namespace | Contents |
|---|---|
| `Tyhp\` | `Expression`, `PropertyPath`, and the fluent builders `PropertyPathBuilder` and `ExpressionBuilder` |
| `Tyhp\Expression\` | The node classes, `ExpressionVisitor`, `ExpressionSerializer`, and the `Serialized*` struct types |
| `Tyhp\Expression\Structs\` | The `PathNode` struct |

## How the pieces fit together

An expression tree has two halves. The **container** is an `Expression` object: it knows the lambda's parameters, its return type, and a compiled closure that runs the original code. The **body** is a tree of `ExpressionNode` objects, one node per operation in the lambda's body.

```text
Tyhp\Expression<TCallableShape>            body, parameters, callable, returnType
├── Tyhp\PropertyPath<TCallableShape>      adds the property chain ($path)
│   └── Tyhp\PropertyPathBuilder<T>        fluent builder, created by Expression::of()
└── Tyhp\ExpressionBuilder<T>              fluent builder, created by a comparison

Tyhp\Expression\ExpressionNode             abstract base: $type, $nodeType, accept()
├── ParameterExpression                    the lambda parameter ($u)
├── PropertyAccessExpression               $u->age
├── NullSafeAccessExpression               $u->address?->city
├── MethodCallExpression                   $u->displayName()
├── StaticMethodCallExpression             Money::of($u->amount)
├── BinaryExpression                       $u->age >= 18, $a && $b
├── UnaryExpression                        !$u->isActive
├── ConstantExpression                     18, $capturedVariable, User::ADULT_AGE
├── TernaryExpression                      $c ? $a : $b
├── CoalesceExpression                     $a ?? $b
├── ArrayAccessExpression                  $u->tags[0]
├── CastExpression                         (string) $u->age
├── NewExpression                          new Address($u->city)
└── InstanceofExpression                   $u->address is Address
```

Trees reach your code in one of four ways:

- **From the compiler, as an `Expression`.** An inline `fn` passed to an `Expression<callable(...): R>` parameter becomes a full tree of nodes.
- **From the compiler, as a `PropertyPath`.** An inline `fn` that is only a property chain (`fn ($u) => $u->address->city`), passed to a `PropertyPath<callable(T): R>` parameter, becomes a `PropertyPath` with the chain as an array of names.
- **From the fluent builders.** Plain PHP code cannot write parsable lambdas, so `Expression::of(User::class)->age->gte(18)` builds an equivalent tree by method calls. This is how PHP callers use a Tyhp library that expects expression trees.
- **By constructing nodes yourself.** Every node class and `Expression` have public constructors. This is useful in tests and when you rebuild a tree.

The examples on this page use these two classes:

```tyhp
<?tyhp

namespace App;

class Address {
    public function __construct(
        public string $city,
        public string $country,
    ) {}
}

class User {
    public const int ADULT_AGE = 18;

    public function __construct(
        public string $name,
        public int $age,
        public bool $isActive,
        public Address $address,
        public ?string $nickname = null,
        public array<string> $tags = [],
    ) {}

    public function displayName(): string {
        return $this->nickname ?? $this->name;
    }
}
```

## Getting started

A function that accepts `Expression<callable(User): bool>` receives a tree instead of a closure. It can look at the tree, and it can still run the original code by calling the expression like a function. A function that accepts `PropertyPath<callable(User): mixed>` receives the property chain.

```tyhp
<?tyhp

namespace App;

use Tyhp\Expression;
use Tyhp\PropertyPath;

final class Inspector {
    public static function describe(Expression<callable(User): bool> $predicate): void {
        echo $predicate->body->nodeType, "\n";        // binary
        echo $predicate->parameters[0]->name, "\n";   // u
        echo $predicate->returnType, "\n";            // bool

        $ada = new User('Ada', 36, true, new Address('Oslo', 'NO'));
        echo $predicate($ada) ? 'matches' : 'does not match', "\n";
    }

    public static function column(PropertyPath<callable(User): mixed> $path): string {
        return $path->getPath();
    }
}

int $minAge = 18;
Inspector::describe(fn ($u) => $u->age >= $minAge && $u->isActive);
echo Inspector::column(fn ($u) => $u->address->city), "\n";   // address.city
```

The captured variable `$minAge` appears in the tree as a `ConstantExpression` holding `18`. Its value is read each time the call runs, so a different `$minAge` produces a different tree.

## Expression

### Expression&lt;TCallableShape&gt;

`Tyhp\Expression` is the container for a tree. Its single type argument is the callable shape of the lambda: `Expression<callable(User): bool>` describes a lambda that takes a `User` and returns `bool`; `Expression<callable(User, User): int>` takes two; `Expression<callable(): string>` takes none. Every `Expression` keeps the compiled closure, so code that receives one can either inspect it or run it.

`PropertyPath`, `PropertyPathBuilder`, and `ExpressionBuilder` all extend `Expression`, so everything in this section applies to them too.

:::member[readonly public \Tyhp\Expression\ExpressionNode $body]
The root node of the tree. For `fn ($u) => $u->age >= 18 && $u->isActive` this is a `BinaryExpression` with operator `&&`. Walk it with an [`ExpressionVisitor`](#expressionvisitor) or by checking node classes with `is` / `instanceof`.
:::

:::member[readonly public array<\Tyhp\Expression\ParameterExpression> $parameters]
One `ParameterExpression` per lambda parameter, in declaration order. `$parameters[0]->name` is the parameter name without `$` (`'u'`), `paramType` is the parameter's type as a string (`'App\User'`), and `index` is its position.

These objects describe the parameters; they are not the same instances as the `ParameterExpression` nodes inside `$body`. Match parameters to body nodes by `index`, not by object identity.
:::

:::member[readonly public \Closure<TCallableShape> $callable]
The compiled closure for the original lambda. For a compiler-built tree this is the `fn` you wrote; for builder-made trees it is a closure the builder generated that evaluates the same logic.
:::

:::member[readonly public string $returnType]
The lambda's return type spelled as a string, for example `'bool'`, `'int'`, or `'mixed'`. The compiler takes it from the result type in the parameter's callable shape: an `fn` passed to `Expression<callable(User): bool>` gets `'bool'`, even though the body's own inferred type might be narrower. `PropertyPathBuilder` uses `'mixed'` and `ExpressionBuilder` uses `'bool'`.

The value is informational. The package does not enforce it.
:::

:::member[public mixed $lastResult = null]
The last value returned by `__invoke()` (or by `PropertyPath::getValue()`). It is the only mutable property on `Expression`.
:::

:::member[public function __construct(ExpressionNode $body, array<ParameterExpression> $parameters, \Closure<TCallableShape> $callable, string $returnType): void]
Creates an expression from a root node, its parameter descriptions, the closure to run, and the return-type string. The compiler calls this constructor with named arguments when it converts an `fn`. You call it yourself when you build or rebuild a tree by hand.

```php
<?php

use Tyhp\Expression;
use Tyhp\Expression\BinaryExpression;
use Tyhp\Expression\ConstantExpression;
use Tyhp\Expression\ParameterExpression;
use Tyhp\Expression\PropertyAccessExpression;

$u = new ParameterExpression('u', \App\User::class, 0);

$isAdult = new Expression(
    new BinaryExpression(
        new PropertyAccessExpression($u, 'age', 'int'),
        '>=',
        new ConstantExpression(18, 'int'),
        'bool',
    ),
    [$u],
    fn (\App\User $u): bool => $u->age >= 18,
    'bool',
);
```

The constructor does not check that the tree and the closure describe the same logic. Keep them consistent yourself.
:::

:::member[public function __invoke(__CallableParametersRest<TCallableShape> ...$args): __CallableReturnType<TCallableShape>]
Runs the stored closure with `$args`, so an `Expression` can be called like a function: `$predicate($user)`. The result is stored in `$lastResult` and returned.

An `Expression` is callable, so you can pass it to a PHP function parameter declared `callable`, such as `\array_filter()`, or to a Tyhp `callable(T): R` parameter with the same shape. A `\Closure` parameter also accepts an `Expression` argument: the compiler passes its `->callable`.
:::

:::member[public function compile(): \Closure<TCallableShape>]
Returns the stored closure (`$callable`) unchanged. Use it when you want the closure as a value of its own, for example to keep it in a `\Closure<callable(T): R>` variable.

```tyhp
<?tyhp

function activeUsers(array<User> $users, Expression<callable(User): bool> $predicate): array<User> {
    \Closure<callable(User): bool> $test = $predicate->compile();
    return \array_values(\array_filter($users, $test));
}
```
:::

:::member[public function equals(\Tyhp\Expression $other): bool]
Returns `true` when both expressions have the same parameters, return type, and body. It delegates to [`ExpressionSerializer::equals()`](#expressionserializer), which compares the JSON form of both trees, so the closures are ignored: two separately written `fn` expressions with the same shape compare equal.

Parameter **names** are part of the comparison. `fn ($u) => $u->age >= 18` and `fn ($x) => $x->age >= 18` are not equal. Captured values are compared too, so the same lambda captured with two different values of `$minAge` is not equal.
:::

:::member[public function and(?\Tyhp\Expression<TCallableShape> $other = null): \Tyhp\Expression]
Combines this expression with `$other` using `&&` and returns a new `ExpressionBuilder`. The new body is `BinaryExpression($this->body, '&&', $other->body, 'bool')`, the parameters are this expression's parameters, and the new closure calls both closures with short-circuit evaluation.

When `$other` is omitted, the method returns an `ExpressionBuilder` that waits for a right-hand side built with property access and a comparison. That form is intended for PHP callers:

```php
<?php

// $compiled is an Expression<callable(User): bool> received from Tyhp code.
$combined = $compiled->and()->isActive->same(true);
```

The declared return type in Tyhp is `Expression`. In Tyhp code, pass `$other`. See [Combining expressions](#combining-expressions) for how the parameters of the two sides relate.
:::

:::member[public function or(?\Tyhp\Expression<TCallableShape> $other = null): \Tyhp\Expression]
Same as `and()`, but combines with `||`. The combined closure returns `true` as soon as the left side is true.
:::

:::member[public static function of<T extends object>(__ClassName<T> $sourceType, string|array ...$segments): \Tyhp\PropertyPathBuilder<T>]
Starts a fluent builder rooted at the class `$sourceType` and returns a `PropertyPathBuilder<T>`. Pass property names either as separate strings or as one array of strings to seed the path:

```php
<?php

use App\User;
use Tyhp\Expression;

Expression::of(User::class)->address->city;          // address.city
Expression::of(User::class)->prop('address')->prop('city');
Expression::of(User::class, 'address', 'city');
Expression::of(User::class, ['address', 'city']);
Expression::of(User::class)->age->gte(18);            // ExpressionBuilder
```

A string containing a dot is one segment: `Expression::of(User::class, 'address.city')` has the single segment `'address.city'`.

**Throws** `\InvalidArgumentException` when the segments mix strings and arrays, or when the array contains a non-string. See [Fluent builders](#fluent-builders-for-php-callers) for the full builder API.
:::

:::member[public static function andAll(Expression<callable(mixed): bool> $first, Expression<callable(mixed): bool> $second, Expression<callable(mixed): bool> ...$rest): Expression<callable(mixed): bool>]
Combines two or more boolean expressions with `&&`, left to right: `andAll($a, $b, $c)` produces the body `(($a && $b) && $c)`. The result is a plain `Expression`, and its parameters are the first expression's parameters.

The parameters are typed `Expression<callable(mixed): bool>`. Builder results can be passed directly, and PHP code can pass any `Expression`. In Tyhp code that holds `Expression<callable(User): bool>` values, combine them with `$a->and($b)` instead.

```php
<?php

use App\User;
use Tyhp\Expression;

$eligible = Expression::andAll(
    Expression::of(User::class)->age->gte(18),
    Expression::of(User::class)->isActive->same(true),
    Expression::of(User::class)->address->country->eq('NO'),
);
```
:::

:::member[public static function orAll(Expression<callable(mixed): bool> $first, Expression<callable(mixed): bool> $second, Expression<callable(mixed): bool> ...$rest): Expression<callable(mixed): bool>]
Same as `andAll()`, but combines with `||`.
:::

## PropertyPath

### PropertyPath&lt;TCallableShape&gt;

`Tyhp\PropertyPath` is an `Expression` that is only a chain of property reads. Use it for APIs that need a property *reference* rather than a predicate: ORM column mappings, `orderBy`, `select`, form field bindings, validation messages. Because the chain is written as code, renaming the property in your IDE updates every reference, and a typo is a compile error.

When an `fn` is passed to a `PropertyPath<callable(T): R>` parameter, the compiler emits a `new \Tyhp\PropertyPath(...)` with the source class, the result type, the array of property names, and your `fn` as the closure. Chains that use `?->` also pass a `nullSafeFlags` array. The compiled output is shown on the [language page](tyhp_3000_parsableLambdas.md#propertypath-compiled-php-output).

The tree in `$body` is built from the chain, not from your `fn`. Its parameter is always named `source`, with `paramType` set to the source class, and every property node has the type `'mixed'`:

```text
fn ($u) => $u->address->city

PropertyAccessExpression  property: 'city'
└── PropertyAccessExpression  property: 'address'
    └── ParameterExpression  name: 'source', paramType: 'App\User', index: 0
```

:::member[readonly public array<string> $path]
The property names in access order. For `fn ($u) => $u->address->city` this is `['address', 'city']`.
:::

:::member[public function __construct(string $sourceType, string $resultType, array<string> $path, \Closure<TCallableShape> $callable, bool $allowEmpty = false, array<bool> $nullSafeFlags = []): void]
Creates a property path. Normally the compiler calls this; you call it in tests or when you build a path from data.

- `$sourceType` — the class the chain starts from, for example `User::class`. It becomes the `paramType` of the `source` parameter.
- `$resultType` — the type of the final value as a string. It becomes `$returnType`.
- `$path` — the property names in order.
- `$callable` — the closure that reads the value.
- `$allowEmpty` — when `true`, an empty `$path` is accepted. An empty path describes the source object itself.
- `$nullSafeFlags` — one flag per segment. `true` makes that segment a `NullSafeAccessExpression` (`?->`) in the tree. Missing entries count as `false`.

**Throws** `\InvalidArgumentException` when `$path` is empty and `$allowEmpty` is `false`.

```php
<?php

use Tyhp\PropertyPath;

$city = new PropertyPath(
    \App\User::class,
    'string',
    ['address', 'city'],
    fn (\App\User $u): string => $u->address->city,
);
```
:::

:::member[public function getPropertyName(): string]
Returns the last segment: `'city'` for `$u->address->city`. Returns `''` for an empty path. This matches what `nameof(fn (User $u) => $u->address->city)` gives at compile time.
:::

:::member[public function getPath(): string]
Returns the segments joined with dots: `'address.city'`. Returns `''` for an empty path.
:::

:::member[public function getSegments(): array<string>]
Returns `$path`, the segments as an array: `['address', 'city']`.
:::

:::member[public function getValue(mixed $source): __CallableReturnType<TCallableShape>]
Runs the closure on `$source` and returns the value at the end of the chain. Like `Expression::__invoke()`, it stores the result in `$lastResult`.

Whatever the closure throws (for example reading through `null` without `?->`) propagates unchanged. A chain with `?->` returns `null` when a null-safe link is `null`.

```tyhp
<?tyhp

function readColumn(User $user, PropertyPath<callable(User): string> $column): string {
    return $column->getValue($user);
}

readColumn($user, fn ($u) => $u->address->city);   // 'Oslo'
```
:::

## Fluent builders for PHP callers

A Tyhp library can expose methods that take `Expression<callable(T): bool>` or `PropertyPath<callable(T): R>`. Tyhp callers pass an `fn`. PHP callers cannot, because the PHP compiler does not capture lambda bodies. The fluent builders fill that gap: they build the same kind of tree from method calls, starting at `Expression::of()`.

```php
<?php

use App\User;
use Tyhp\Expression;

// PropertyPath: a property reference
$sortColumn = Expression::of(User::class)->address->city;

// Expression: a predicate
$isEligible = Expression::of(User::class)->age->gte(18)
    ->and()->isActive->same(true);

$repository->orderBy($sortColumn)->where($isEligible);
```

### Builder lifecycle

A chain moves through these states. Each method returns a **new** builder; builders are never modified in place, so you can keep an intermediate builder and branch from it.

1. `Expression::of(User::class)` returns a `PropertyPathBuilder` with an empty path.
2. Property access (`->address`, `->prop('address')`) appends a segment and returns another `PropertyPathBuilder`. A `PropertyPathBuilder` is a `PropertyPath`, so you can pass it anywhere a `PropertyPath` is expected.
3. A comparison (`->gte(18)`, `->eq('Oslo')`, `->isNull()`, …) turns the path into a completed `ExpressionBuilder` whose body is `path <operator> value`. This step is one-way.
4. `->and()` or `->or()` with no argument starts a right-hand side. Property access then builds the right-hand path, and a comparison completes the compound expression.
5. `->and($other)` or `->or($other)` combines with an existing expression in one step.

The `->name` property syntax is for PHP. It works through `__get()`, and the classes carry `@mixin T` docblock tags so PhpStorm, PHPStan, and Psalm autocomplete the source class's property names. In Tyhp code, use `->prop('name')` or pass segments to `Expression::of()`.

```tyhp
<?tyhp

use Tyhp\Expression;
use Tyhp\ExpressionBuilder;
use Tyhp\PropertyPathBuilder;

PropertyPathBuilder<User> $city = Expression::of(User::class)->prop('address')->prop('city');
ExpressionBuilder<User> $adult = Expression::of(User::class)->prop('age')->gte(18);
ExpressionBuilder<User> $active = Expression::of(User::class, 'isActive')->same(true);
ExpressionBuilder<User> $eligible = $adult->and($active);
```

### Comparison methods

Both builders have the same ten comparison methods. On a `PropertyPathBuilder` they compare the current path. On an `ExpressionBuilder` they complete the right-hand side after `and()` / `or()`. Each returns `ExpressionBuilder<T>`.

| Method | Operator in the tree | Meaning |
|---|---|---|
| `gt(mixed $value): ExpressionBuilder<T>` | `>` | greater than |
| `gte(mixed $value): ExpressionBuilder<T>` | `>=` | greater than or equal |
| `lt(mixed $value): ExpressionBuilder<T>` | `<` | less than |
| `lte(mixed $value): ExpressionBuilder<T>` | `<=` | less than or equal |
| `eq(mixed $value): ExpressionBuilder<T>` | `==` | loose equality |
| `neq(mixed $value): ExpressionBuilder<T>` | `!=` | loose inequality |
| `same(mixed $value): ExpressionBuilder<T>` | `===` | strict equality |
| `notSame(mixed $value): ExpressionBuilder<T>` | `!==` | strict inequality |
| `isNull(): ExpressionBuilder<T>` | `===` with `null` | value is `null` |
| `isNotNull(): ExpressionBuilder<T>` | `!==` with `null` | value is not `null` |

A comparison produces `BinaryExpression(<path>, <operator>, ConstantExpression($value, 'mixed'), 'bool')`. The path nodes and the constant have the type `'mixed'`, because the builder does not know the property types. The generated closure reads the path from its argument and applies the same PHP operator.

### Reading values along a path

Builder closures read each segment from whatever value the previous segment produced:

- an **array** (including Tyhp structs, which compile to arrays) is read by key;
- an object implementing **`\ArrayAccess`** is read by offset;
- any other **object** is read as a property.

A strict segment throws `\TypeError` when the current value is `null`, when an array key or `\ArrayAccess` offset does not exist, or when the value is a scalar. A segment marked null-safe (`->prop('city', nullSafe: true)`) returns `null` in those cases instead.

Each null-safe flag covers only its own segment. Unlike PHP's `?->`, a null-safe segment does not short-circuit the rest of the chain, so every segment that can see `null` needs its own flag:

```php
<?php

// Safe when address is null: the city read is the hop that sees null.
$city = Expression::of(User::class)->prop('address')->prop('city', nullSafe: true);

// Throws \TypeError when address is null: only the address read is null-safe.
$strict = Expression::of(User::class)->prop('address', nullSafe: true)->prop('city');
```

### Builder errors

| Situation | Exception and message |
|---|---|
| Comparison on `Expression::of(X)` with no property | `\LogicException`: "Expression::of() requires at least one property before a comparison." |
| Property access or `prop()` on a completed `ExpressionBuilder` | `\LogicException`: "Cannot access properties on a completed expression. Call and()/or() to continue, or start from Expression::of()." |
| Comparison on a completed `ExpressionBuilder` | `\LogicException`: "Comparisons on ExpressionBuilder require and()/or() followed by a property path, or start from Expression::of()." |
| Comparison right after `and()` / `or()` with no property | `\LogicException`: "Continue the property path after and()/or() before comparing." |
| `and()` / `or()` while a right-hand path is waiting for its comparison | `\LogicException`: "Finish the property comparison before calling and()/or()." |
| `and()` / `or()` right after another `and()` / `or()` | `\LogicException`: "Finish the right-hand side after and()/or() before combining further." |
| Assigning a property on a builder | `\BadMethodCallException` from `__set()` |
| Calling a method of the source class on a builder | `\BadMethodCallException` from `__call()` |
| Mixed or non-string segments passed to `of()` | `\InvalidArgumentException` |

An `ExpressionBuilder` that is waiting for its right-hand side is still an `Expression`, but its body and closure are only the left side. Finish the chain with a comparison before you hand it to code that reads the tree.

### PropertyPathBuilder&lt;T&gt;

`Tyhp\PropertyPathBuilder<T extends object>` extends `PropertyPath<callable(T): mixed>`. It is the builder you get from `Expression::of()` while the chain contains only property access. Its `$returnType` is `'mixed'`, and its closure reads the path as described in [Reading values along a path](#reading-values-along-a-path).

:::member[public function __construct(string $sourceType, array<string> $path = [], array<bool> $nullSafeFlags = []): void]
Creates a builder for `$sourceType` with an optional starting path and per-segment null-safe flags. An empty path is allowed. `Expression::of()` and `PropertyPathBuilder::of()` are the usual entry points.
:::

:::member[public static function of<T extends object>(__ClassName<T> $sourceType, string|array ...$segments): \Tyhp\PropertyPathBuilder<T>]
The same as `Expression::of()`. Segments are separate strings or one array of strings.

**Throws** `\InvalidArgumentException` for any other segment shape.
:::

:::member[public function prop(string $name, bool $nullSafe = false): \Tyhp\PropertyPathBuilder<T>]
Returns a new builder with `$name` appended. When `$nullSafe` is `true`, that segment becomes a `NullSafeAccessExpression` in the tree and returns `null` instead of throwing when it reads through `null` or a missing key.
:::

:::member[public function __get(string $name): \Tyhp\PropertyPathBuilder<T>]
Property syntax for `prop($name)`: `$builder->address` is `$builder->prop('address')`. Use it from PHP.
:::

:::member[public function __set(string $name, mixed $value): void]
Always throws `\BadMethodCallException`. Builders are read-only.
:::

:::member[public function __call(string $name, array<int|string, mixed> $arguments): mixed]
Always throws `\BadMethodCallException`. A property path cannot contain method calls; IDEs may still offer the source class's methods because of the `@mixin` tag.
:::

The ten [comparison methods](#comparison-methods) promote the path to an `ExpressionBuilder<T>`.

### ExpressionBuilder&lt;T&gt;

`Tyhp\ExpressionBuilder<T extends object>` extends `Expression<callable(T): bool>`. You get one from a comparison on a `PropertyPathBuilder`, or from `and()` / `or()` on any `Expression`. Its `$returnType` is `'bool'`.

:::member[public function __construct(string $sourceType, ExpressionNode $body, array<ParameterExpression> $parameters, \Closure $callable, string $returnType = 'bool', array<string> $path = [], array<bool> $nullSafeFlags = [], ?\Tyhp\Expression<callable(T): mixed> $pendingLeft = null, ?string $pendingCombinator = null): void]
The full constructor. `$path` and `$nullSafeFlags` hold the right-hand path while a chain continues after `and()` / `or()`, and `$pendingLeft` / `$pendingCombinator` hold the left side and the operator until the comparison completes it. Application code normally uses `Expression::of()`, `fromComparison()`, or `continueFrom()` instead.
:::

:::member[public static function fromComparison<TSource extends object>(string $sourceType, ExpressionNode $body, array<ParameterExpression> $parameters, \Closure $callable): \Tyhp\ExpressionBuilder<TSource>]
Wraps an existing boolean body, its parameters, and its closure as a completed builder. This is what a `PropertyPathBuilder` comparison returns.
:::

:::member[public static function continueFrom<TOf extends object>(\Tyhp\Expression $left, string $combinator, string $sourceType): \Tyhp\ExpressionBuilder<TOf>]
Returns a builder that waits for a right-hand side to combine with `$left`. `$combinator` must be `'&&'` or `'||'`. This is what `and()` and `or()` return when called without an argument.

**Throws** `\InvalidArgumentException` for any other combinator.
:::

:::member[public function prop(string $name, bool $nullSafe = false): \Tyhp\ExpressionBuilder<T>]
Appends a segment to the right-hand path after `and()` / `or()`.

**Throws** `\LogicException` on a completed builder.
:::

:::member[public function __get(string $name): \Tyhp\ExpressionBuilder<T>]
Property syntax for `prop($name)`. Use it from PHP.
:::

:::member[public function __set(string $name, mixed $value): void]
Always throws `\BadMethodCallException`.
:::

:::member[public function __call(string $name, array<int|string, mixed> $arguments): mixed]
Always throws `\BadMethodCallException`.
:::

:::member[public function and(?\Tyhp\Expression<callable(T): bool> $other = null): \Tyhp\ExpressionBuilder<T>]
With `$other`, returns a completed builder for `$this && $other`. Without it, returns a builder waiting for a right-hand path and comparison.

**Throws** `\LogicException` when this builder is not complete (see [Builder errors](#builder-errors)).
:::

:::member[public function or(?\Tyhp\Expression<callable(T): bool> $other = null): \Tyhp\ExpressionBuilder<T>]
Same as `and()`, with `||`.
:::

The ten [comparison methods](#comparison-methods) complete a right-hand side. Called on a completed builder, they throw `\LogicException`.

### Combining expressions

`and()`, `or()`, `andAll()`, and `orAll()` build a new `BinaryExpression` from the two bodies and keep the **left** expression's `$parameters`. The right body keeps its own `ParameterExpression` nodes. If the two sides were written with different parameter names — for example a compiler-built `fn ($u) => …` on the left and a builder-made right side, whose parameter is always called `source` — the combined tree contains both names. A translator should match parameters by `index`, which is the same on both sides.

## Expression nodes

Every node extends `Tyhp\Expression\ExpressionNode`. All node classes except the abstract base are `final`, and all node properties are `readonly`.

### ExpressionNode

:::member[readonly public string $type]
The type of the value this node produces, spelled as a string. In compiler-built trees it is the type the checker inferred: `'int'`, `'?string'`, `'App\User'`, `'bool'`. Class names are fully qualified without a leading backslash. Builder-made trees use `'mixed'` for property and constant nodes.

Literal values get literal types: the `18` in `$u->age >= 18` has the type `'18'`, and `1.5` has `'1.5'`. A string literal has the type `'string'`, and `true`, `false`, and `null` have the types `'true'`, `'false'`, and `'null'`. A captured variable gets its declared type (`'int'`). Inspect `ConstantExpression::$value` with PHP's type checks rather than parsing `$type`.
:::

:::member[readonly public string $nodeType]
A short identifier for the node class, such as `'binary'` or `'propertyAccess'`. It is the `nodeType` key in the [JSON format](#json-format). The table below lists every value.
:::

:::member[public function __construct(string $type, string $nodeType): void]
Called by each node class's constructor with its fixed `$nodeType`.
:::

:::member[public abstract function accept(ExpressionVisitor $visitor): mixed]
Calls the visitor method for this node class (for example `visitBinary($this)`) and returns its result. You rarely call this directly; `ExpressionVisitor::visit($node)` does.
:::

### Node summary

The "Produced by" column describes what the compiler emits for an `fn` passed to an `Expression<…>` parameter. The [language page](tyhp_3000_parsableLambdas.md#supported-expression-types) lists which constructs are allowed in a tree body.

| Class | `nodeType` | Produced by | Child nodes and data | Visitor method |
|---|---|---|---|---|
| `ParameterExpression` | `parameter` | each use of a lambda parameter | `name`, `paramType`, `index` | `visitParameter` |
| `PropertyAccessExpression` | `propertyAccess` | `$x->prop` | `object`, `property` | `visitPropertyAccess` |
| `NullSafeAccessExpression` | `nullSafeAccess` | `$x?->prop` | `object`, `property` | `visitNullSafeAccess` |
| `MethodCallExpression` | `methodCall` | `$x->method(...)` | `object`, `method`, `arguments` | `visitMethodCall` |
| `StaticMethodCallExpression` | `staticMethodCall` | `Cls::method(...)` | `class`, `method`, `arguments` | `visitStaticMethodCall` |
| `BinaryExpression` | `binary` | arithmetic, string, comparison, and logical operators | `left`, `operator`, `right` | `visitBinary` |
| `UnaryExpression` | `unary` | `!`, `-`, `+`, `~` | `operator`, `operand`, `isPrefix` | `visitUnary` |
| `ConstantExpression` | `constant` | literals, captured variables, `Cls::CONST`, `Cls::class`, magic constants | `value` | `visitConstant` |
| `TernaryExpression` | `ternary` | `$c ? $a : $b`, `$a ?: $b` | `condition`, `ifTrue`, `ifFalse` | `visitTernary` |
| `CoalesceExpression` | `coalesce` | `$a ?? $b` | `left`, `right` | `visitCoalesce` |
| `ArrayAccessExpression` | `arrayAccess` | `$x[$i]` | `array`, `index` | `visitArrayAccess` |
| `CastExpression` | `cast` | `(int)`, `(string)`, `(float)`, `(bool)`, `(array)`, `(object)`, `(decimal)` | `targetType`, `operand` | `visitCast` |
| `NewExpression` | `new` | `new Cls(...)` | `class`, `arguments` | `visitNew` |
| `InstanceofExpression` | `instanceof` | `$x instanceof T`, `$x is T` | `operand`, `targetType` | `visitInstanceof` |

Parentheses do not produce nodes. `($u->age + 1) * 2` is a `BinaryExpression` for `*` whose left child is the `BinaryExpression` for `+`.

### ParameterExpression

:::member[final class ParameterExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(string $name, string $paramType, int $index): void
readonly public string $name;
readonly public string $paramType;
readonly public int $index;
```

A use of a lambda parameter. `$name` is the parameter name without `$`, `$paramType` is its type as a string, and `$index` is its zero-based position. `$type` equals `$paramType`.

In compiler-built `Expression` trees, `$name` is the name you wrote (`u` for `fn ($u) => …`). In `PropertyPath` and builder trees it is always `source`. Each occurrence in the body is a separate object, so compare parameters by `$index`.
:::

### PropertyAccessExpression

:::member[final class PropertyAccessExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(ExpressionNode $object, string $property, string $type = 'mixed'): void
readonly public ExpressionNode $object;
readonly public string $property;
```

A property read, `$object->property`. `$object` is the node being read from — often a `ParameterExpression`, or another access node for a chain. For `$u->address->city`, the outer node has `property` `'city'` and its `object` is the node for `$u->address`.
:::

### NullSafeAccessExpression

:::member[final class NullSafeAccessExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(ExpressionNode $object, string $property, string $type = 'mixed'): void
readonly public ExpressionNode $object;
readonly public string $property;
```

A null-safe property read, `$object?->property`. Only the segment written with `?->` gets this class: `$u->address?->city` is a `NullSafeAccessExpression` for `city` whose `object` is a plain `PropertyAccessExpression` for `address`. A SQL translator typically treats it like a property read; an in-memory evaluator returns `null` when `$object` evaluates to `null`.
:::

### MethodCallExpression

:::member[final class MethodCallExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(ExpressionNode $object, string $method, array<ExpressionNode> $arguments, string $type = 'mixed'): void
readonly public ExpressionNode $object;
readonly public string $method;
readonly public array<ExpressionNode> $arguments;
```

An instance method call, `$object->method(...$arguments)`. `$arguments` holds one node per argument in the order written; argument names are not recorded. `$type` is the method's return type.
:::

### StaticMethodCallExpression

:::member[final class StaticMethodCallExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(string $class, string $method, array<ExpressionNode> $arguments, string $type = 'mixed'): void
readonly public string $class;
readonly public string $method;
readonly public array<ExpressionNode> $arguments;
```

A static method call, `Cls::method(...$arguments)`. `$class` is the fully qualified class name without a leading backslash (the value of `Cls::class`).
:::

### BinaryExpression

:::member[final class BinaryExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(ExpressionNode $left, string $operator, ExpressionNode $right, string $type = 'mixed'): void
readonly public ExpressionNode $left;
readonly public string $operator;
readonly public ExpressionNode $right;
```

A binary operation. `$operator` is the operator as written in the source: `'+'`, `'-'`, `'*'`, `'/'`, `'%'`, `'**'`, `'.'`, `'=='`, `'!='`, `'==='`, `'!=='`, `'<'`, `'>'`, `'<='`, `'>='`, `'<=>'`, `'&&'`, `'||'`, and so on. The keyword forms are kept as written, so `$a and $b` has the operator `'and'`, not `'&&'`. Handle both spellings in a translator.

`??` produces a `CoalesceExpression`, and `instanceof` / `is` produce an `InstanceofExpression`, not a `BinaryExpression`. The combinators `and()`, `or()`, `andAll()`, and `orAll()` produce `BinaryExpression` nodes with `'&&'` or `'||'`.
:::

### UnaryExpression

:::member[final class UnaryExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(string $operator, ExpressionNode $operand, bool $isPrefix, string $type = 'mixed'): void
readonly public string $operator;
readonly public ExpressionNode $operand;
readonly public bool $isPrefix;
```

A unary operation: `'!'`, `'-'`, `'+'`, or `'~'` applied to `$operand`. `$isPrefix` is `true` when the operator comes before the operand, which is the case for every unary operator a tree body can contain.
:::

### ConstantExpression

:::member[final class ConstantExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(mixed $value, string $type = 'mixed'): void
readonly public mixed $value;
```

A value that does not depend on the lambda parameters. The compiler produces it for:

- numeric literals (`18`, `1.5`), string literals without interpolation (`'Ada'`), and `true`, `false`, and `null` in any case;
- **captured variables** from the enclosing scope — `$value` is the variable's value at the moment the tree is built;
- class constants (`User::ADULT_AGE`) and `Cls::class`, evaluated when the tree is built;
- magic constants such as `__LINE__`.

Builder comparisons store their argument here with the type `'mixed'`. A query translator usually turns a `ConstantExpression` into a bound parameter rather than splicing `$value` into SQL text.

If the value is an object, the node holds a reference to it. Later changes to that object are visible through the tree.
:::

### TernaryExpression

:::member[final class TernaryExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(ExpressionNode $condition, ?ExpressionNode $ifTrue, ExpressionNode $ifFalse, string $type = 'mixed'): void
readonly public ExpressionNode $condition;
readonly public ?ExpressionNode $ifTrue;
readonly public ExpressionNode $ifFalse;
```

A conditional, `$condition ? $ifTrue : $ifFalse`. For the short form `$a ?: $b`, `$ifTrue` is `null`: the result is the condition's own value when it is truthy, otherwise `$ifFalse`.
:::

### CoalesceExpression

:::member[final class CoalesceExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(ExpressionNode $left, ExpressionNode $right, string $type = 'mixed'): void
readonly public ExpressionNode $left;
readonly public ExpressionNode $right;
```

Null coalescing, `$left ?? $right`. In SQL this usually maps to `COALESCE(left, right)`.
:::

### ArrayAccessExpression

:::member[final class ArrayAccessExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(ExpressionNode $array, ExpressionNode $index, string $type = 'mixed'): void
readonly public ExpressionNode $array;
readonly public ExpressionNode $index;
```

An index read, `$array[$index]`. Both parts are nodes: in `$u->tags[0]`, `$array` is the `PropertyAccessExpression` for `tags` and `$index` is a `ConstantExpression` holding `0`.
:::

### CastExpression

:::member[final class CastExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(string $targetType, ExpressionNode $operand): void
readonly public string $targetType;
readonly public ExpressionNode $operand;
```

A type cast. `$targetType` is one of `'int'`, `'float'`, `'string'`, `'bool'`, `'array'`, `'object'`, or `'decimal'`; alternative spellings such as `(integer)` and `(double)` are normalized. `$type` equals `$targetType`.
:::

### NewExpression

:::member[final class NewExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(string $class, array<ExpressionNode> $arguments): void
readonly public string $class;
readonly public array<ExpressionNode> $arguments;
```

Object creation, `new Cls(...$arguments)`. `$class` is the fully qualified class name without a leading backslash, and `$type` equals `$class`. Argument names are not recorded.
:::

### InstanceofExpression

:::member[final class InstanceofExpression extends ExpressionNode]
```tyhp
<?tyhp

public function __construct(ExpressionNode $operand, string $targetType, string $type = 'bool'): void
readonly public ExpressionNode $operand;
readonly public string $targetType;
```

A type test, `$operand instanceof T` or `$operand is T`; both spellings produce this node. `$targetType` is:

- a fully qualified class, interface, or enum name without a leading backslash (`'App\Address'`) for a class-like type;
- the type keyword (`'int'`, `'string'`, `'array'`, …) for a built-in type;
- the runtime value of the variable for `$x instanceof $className`.
:::

## Walking and translating trees

### ExpressionVisitor

`Tyhp\Expression\ExpressionVisitor` is an abstract base class for the visitor pattern. `visit($node)` calls `$node->accept($this)`, and each node class calls back into its own method — `visitBinary()` for a `BinaryExpression`, and so on. Override the methods for the nodes you handle.

Two rules matter when you extend it:

- **Every default method returns `null`.** A node type you did not override is silently translated to `null`. Check for `null` (or for the type you expect) and report unsupported nodes, as the SQL example below does.
- **The defaults do not recurse.** A `visitBinary()` override must call `$this->visit($node->left)` and `$this->visit($node->right)` itself.

:::member[public function visit(ExpressionNode $node): mixed]
Dispatches to the visitor method for `$node`'s class and returns that method's result.
:::

| Method | Called for |
|---|---|
| `visitParameter(ParameterExpression $node): mixed` | `ParameterExpression` |
| `visitPropertyAccess(PropertyAccessExpression $node): mixed` | `PropertyAccessExpression` |
| `visitNullSafeAccess(NullSafeAccessExpression $node): mixed` | `NullSafeAccessExpression` |
| `visitMethodCall(MethodCallExpression $node): mixed` | `MethodCallExpression` |
| `visitStaticMethodCall(StaticMethodCallExpression $node): mixed` | `StaticMethodCallExpression` |
| `visitBinary(BinaryExpression $node): mixed` | `BinaryExpression` |
| `visitUnary(UnaryExpression $node): mixed` | `UnaryExpression` |
| `visitConstant(ConstantExpression $node): mixed` | `ConstantExpression` |
| `visitTernary(TernaryExpression $node): mixed` | `TernaryExpression` |
| `visitCoalesce(CoalesceExpression $node): mixed` | `CoalesceExpression` |
| `visitArrayAccess(ArrayAccessExpression $node): mixed` | `ArrayAccessExpression` |
| `visitCast(CastExpression $node): mixed` | `CastExpression` |
| `visitNew(NewExpression $node): mixed` | `NewExpression` |
| `visitInstanceof(InstanceofExpression $node): mixed` | `InstanceofExpression` |

All visitor methods are `public` and return `mixed`, so a visitor can produce any kind of result: SQL strings, a new tree, a validation rule, a boolean.

### Walking every node

Sometimes you need every node rather than a translation: to collect the properties a predicate uses, to find captured values, or to print a tree while debugging. A small helper that lists each node's children, plus a recursive walk, covers all fourteen node types:

```tyhp
<?tyhp

namespace App;

use Tyhp\Expression;
use Tyhp\Expression\ArrayAccessExpression;
use Tyhp\Expression\BinaryExpression;
use Tyhp\Expression\CastExpression;
use Tyhp\Expression\CoalesceExpression;
use Tyhp\Expression\ExpressionNode;
use Tyhp\Expression\InstanceofExpression;
use Tyhp\Expression\MethodCallExpression;
use Tyhp\Expression\NewExpression;
use Tyhp\Expression\NullSafeAccessExpression;
use Tyhp\Expression\PropertyAccessExpression;
use Tyhp\Expression\StaticMethodCallExpression;
use Tyhp\Expression\TernaryExpression;
use Tyhp\Expression\UnaryExpression;

final class ExpressionTree {
    public static function children(ExpressionNode $node): array<ExpressionNode> {
        if ($node is BinaryExpression || $node is CoalesceExpression) {
            return [$node->left, $node->right];
        }
        if ($node is UnaryExpression || $node is CastExpression || $node is InstanceofExpression) {
            return [$node->operand];
        }
        if ($node is PropertyAccessExpression || $node is NullSafeAccessExpression) {
            return [$node->object];
        }
        if ($node is ArrayAccessExpression) {
            return [$node->array, $node->index];
        }
        if ($node is MethodCallExpression) {
            return [$node->object, ...$node->arguments];
        }
        if ($node is StaticMethodCallExpression || $node is NewExpression) {
            return $node->arguments;
        }
        if ($node is TernaryExpression) {
            array<ExpressionNode> $parts = [$node->condition];
            if ($node->ifTrue !== null) {
                $parts[] = $node->ifTrue;
            }
            $parts[] = $node->ifFalse;
            return $parts;
        }
        return [];   // ParameterExpression and ConstantExpression are leaves
    }

    public static function walk(ExpressionNode $node, callable(ExpressionNode, int): void $visit, int $depth = 0): void {
        $visit($node, $depth);
        foreach (self::children($node) as $child) {
            self::walk($child, $visit, $depth + 1);
        }
    }

    public static function referencedProperties(Expression $expression): array<string> {
        array<string> $names = [];
        self::walk($expression->body, function (ExpressionNode $node, int $depth) use (&$names): void {
            if ($node is PropertyAccessExpression || $node is NullSafeAccessExpression) {
                $names[] = $node->property;
            }
        });
        return \array_values(\array_unique($names));
    }
}
```

Printing a tree with `walk()`:

```tyhp
<?tyhp

function dump(Expression<callable(User): bool> $predicate): void {
    ExpressionTree::walk($predicate->body, function (ExpressionNode $node, int $depth): void {
        echo \str_repeat('  ', $depth), $node->nodeType, ' : ', $node->type, "\n";
    });
}

int $minAge = 18;
dump(fn ($u) => $u->age >= $minAge && ($u->nickname ?? $u->name) !== 'root');
```

```text
binary : bool
  binary : bool
    propertyAccess : int
      parameter : App\User
    constant : int
  binary : bool
    coalesce : string
      propertyAccess : ?string
        parameter : App\User
      propertyAccess : string
        parameter : App\User
    constant : string
```

### Worked example: a SQL query builder

This example turns `fn ($u) => $u->age >= $minAge && $u->isActive` into a parameterized SQL `WHERE` clause. It has two parts: a visitor that translates boolean trees, and a generic `Query<T>` class whose methods accept `Expression` and `PropertyPath` parameters.

The translator handles comparisons, `&&` / `||` (in both spellings), `!`, direct properties of the lambda parameter, and constants. Constants become `?` placeholders with their values collected in `$bindings`, so captured values never end up in the SQL text. Anything else makes `translate()` throw.

```tyhp
<?tyhp

namespace App\Query;

use Tyhp\Expression\BinaryExpression;
use Tyhp\Expression\ConstantExpression;
use Tyhp\Expression\ExpressionNode;
use Tyhp\Expression\ExpressionVisitor;
use Tyhp\Expression\ParameterExpression;
use Tyhp\Expression\PropertyAccessExpression;
use Tyhp\Expression\UnaryExpression;

final class SqlWhereTranslator extends ExpressionVisitor {
    public array<mixed> $bindings = [];

    public function translate(ExpressionNode $node): string {
        mixed $sql = $this->visit($node);
        if (!($sql is string)) {
            throw new \InvalidArgumentException("Cannot translate '{$node->nodeType}' nodes to SQL.");
        }
        return $sql;
    }

    public function visitBinary(BinaryExpression $node): mixed {
        string $operator = match ($node->operator) {
            '&&', 'and' => 'AND',
            '||', 'or' => 'OR',
            '===', '==' => '=',
            '!==', '!=' => '<>',
            '>', '>=', '<', '<=' => $node->operator,
            default => throw new \InvalidArgumentException("Unsupported operator '{$node->operator}'."),
        };
        string $left = $this->translate($node->left);
        string $right = $this->translate($node->right);
        return "({$left} {$operator} {$right})";
    }

    public function visitUnary(UnaryExpression $node): mixed {
        if ($node->operator !== '!') {
            return null;
        }
        return 'NOT ' . $this->translate($node->operand);
    }

    public function visitPropertyAccess(PropertyAccessExpression $node): mixed {
        // Only direct columns ($u->age); nested paths ($u->address->city) are rejected.
        if (!($node->object is ParameterExpression)) {
            return null;
        }
        return $node->property;
    }

    public function visitConstant(ConstantExpression $node): mixed {
        $this->bindings[] = $node->value;
        return '?';
    }
}
```

The query class only reads `->body` from the predicate and `getPropertyName()` from the sort column:

```tyhp
<?tyhp

namespace App\Query;

use Tyhp\Expression;
use Tyhp\PropertyPath;

final class Query<T extends object> {
    private array<string> $conditions = [];
    private array<mixed> $bindings = [];
    private array<string> $ordering = [];

    public function __construct(private string $table) {}

    public function where(Expression<callable(T): bool> $predicate): static {
        $translator = new SqlWhereTranslator();
        $this->conditions[] = $translator->translate($predicate->body);
        foreach ($translator->bindings as $value) {
            $this->bindings[] = $value;
        }
        return $this;
    }

    public function orderBy(PropertyPath<callable(T): mixed> $column, string $direction = 'ASC'): static {
        $this->ordering[] = $column->getPropertyName() . ' ' . $direction;
        return $this;
    }

    public function toSql(): string {
        string $sql = "SELECT * FROM {$this->table}";
        if ($this->conditions !== []) {
            $sql .= ' WHERE ' . \implode(' AND ', $this->conditions);
        }
        if ($this->ordering !== []) {
            $sql .= ' ORDER BY ' . \implode(', ', $this->ordering);
        }
        return $sql;
    }

    public function getBindings(): array<mixed> {
        return $this->bindings;
    }
}
```

Callers write ordinary, type-checked lambdas. A misspelled property is a compile error, and renaming `User::$age` in the IDE updates the query:

```tyhp
<?tyhp

use App\Query\Query;

int $minAge = 18;

$query = new Query<User>('users')
    ->where(fn ($u) => $u->age >= $minAge && $u->isActive)
    ->where(fn ($u) => $u->name !== 'root')
    ->orderBy(fn ($u) => $u->age, 'DESC');

echo $query->toSql();
// SELECT * FROM users WHERE ((age >= ?) AND isActive) AND (name <> ?) ORDER BY age DESC

$query->getBindings();
// [18, 'root']
```

PHP code can use the same compiled `Query` class by building the trees with the fluent builders. The builder trees have the same shape — a `BinaryExpression` over a property of the parameter and a `ConstantExpression` — so the translator needs no changes:

```php
<?php

use App\Query\Query;
use App\User;
use Tyhp\Expression;

$query = (new Query('users'))
    ->where(Expression::of(User::class)->age->gte(18)->and()->isActive->same(true))
    ->orderBy(Expression::of(User::class)->name);

echo $query->toSql();
// SELECT * FROM users WHERE ((age >= ?) AND (isActive = ?)) ORDER BY name ASC
```

To grow this into a real query builder, map property names to column names, translate `CoalesceExpression` to `COALESCE(...)`, turn a comparison with a `null` constant into `IS NULL`, and support nested paths through joins.

## Serialization

### ExpressionSerializer

`Tyhp\Expression\ExpressionSerializer` converts trees to JSON and compares trees structurally. Use it to log or debug a tree, to send a query description to another service, or to build a cache key for work derived from a tree (such as translated SQL).

:::member[public static function toJson(\Tyhp\Expression $expression): string]
Returns a pretty-printed JSON document describing `$expression`'s parameters, return type, and body. The closure is not included. The format is described in [JSON format](#json-format).

**Throws:**

- `\JsonException` when a `ConstantExpression` value cannot be encoded as JSON, for example a resource, `INF`, or `NAN`;
- `\RuntimeException` when the tree is nested more than 100 levels deep;
- `\InvalidArgumentException` when the tree contains a node class other than the fourteen built-in ones.

```tyhp
<?tyhp

use Tyhp\Expression\ExpressionSerializer;

function cacheKey(Expression<callable(User): bool> $predicate): string {
    return \hash('sha256', ExpressionSerializer::toJson($predicate));
}
```

Captured values are part of the JSON, so the key changes when a captured variable changes. That is what you want when the key identifies a translated query together with its bound values; if you cache only the SQL text, build the key from a version of the tree with the constants removed.
:::

:::member[public static function equals(\Tyhp\Expression $a, \Tyhp\Expression $b): bool]
Returns `true` when `toJson($a)` and `toJson($b)` are identical strings. `Expression::equals()` calls this method. The comparison includes parameter names and types, the return type, every node's `type`, and every constant value; it ignores the closures.

```tyhp
<?tyhp

function same(Expression<callable(User): bool> $a, Expression<callable(User): bool> $b): bool {
    return ExpressionSerializer::equals($a, $b);
}

int $minAge = 18;
same(fn ($u) => $u->age >= $minAge, fn ($u) => $u->age >= $minAge);   // true
same(fn ($u) => $u->age >= $minAge, fn ($x) => $x->age >= $minAge);   // false: parameter names differ
```

Because it encodes both trees, the same exceptions as `toJson()` can occur.
:::

### JSON format

The document has three top-level keys:

- `parameters` — an array with one object per parameter: `name`, `index`, and `type` (the parameter type).
- `returnType` — the `$returnType` string.
- `body` — the root node.

Every node object has `nodeType` and `type`, plus the fields for its class:

| `nodeType` | Additional fields |
|---|---|
| `parameter` | `name`, `index` |
| `propertyAccess` | `object` (node), `property` |
| `nullSafeAccess` | `object` (node), `property` |
| `methodCall` | `object` (node), `method`, `arguments` (array of nodes) |
| `staticMethodCall` | `class`, `method`, `arguments` (array of nodes) |
| `binary` | `left` (node), `operator`, `right` (node) |
| `unary` | `operator`, `operand` (node), `isPrefix` |
| `constant` | `value` (the JSON encoding of the value) |
| `ternary` | `condition` (node), `ifTrue` (node, or `null` for `?:`), `ifFalse` (node) |
| `coalesce` | `left` (node), `right` (node) |
| `arrayAccess` | `array` (node), `index` (node) |
| `cast` | `targetType`, `operand` (node) |
| `new` | `class`, `arguments` (array of nodes) |
| `instanceof` | `operand` (node), `targetType` |

Constant values are encoded by PHP's `\json_encode()`: scalars and `null` as JSON values, arrays as arrays or objects, and objects as an object of their public properties. Identify a node by its `nodeType`; the order of keys inside a node object is not significant.

This is the output for `fn ($u) => $u->age >= $minAge && $u->isActive` passed to `Expression<callable(User): bool>` with `$minAge = 18`:

```json
{
    "parameters": [
        {
            "name": "u",
            "index": 0,
            "type": "App\\User"
        }
    ],
    "returnType": "bool",
    "body": {
        "nodeType": "binary",
        "type": "bool",
        "operator": "&&",
        "left": {
            "nodeType": "binary",
            "type": "bool",
            "operator": ">=",
            "left": {
                "nodeType": "propertyAccess",
                "type": "int",
                "property": "age",
                "object": {
                    "nodeType": "parameter",
                    "type": "App\\User",
                    "name": "u",
                    "index": 0
                }
            },
            "right": {
                "nodeType": "constant",
                "type": "int",
                "value": 18
            }
        },
        "right": {
            "nodeType": "propertyAccess",
            "type": "bool",
            "property": "isActive",
            "object": {
                "nodeType": "parameter",
                "type": "App\\User",
                "name": "u",
                "index": 0
            }
        }
    }
}
```

The same predicate built with `Expression::of(User::class)->age->gte(18)` has the parameter name `source` and the type `"mixed"` on the property and constant nodes.

The JSON is a description for other programs to read. The receiving side decodes it as data (for example with `\json_decode()`) and interprets each `nodeType` itself.

### Serialized struct types

`Tyhp\Expression` also exports one struct type per node object in the JSON format. They describe the shape of the arrays the serializer builds before encoding. Every node object also carries the `nodeType` and `type` fields of `SerializedExpression`.

| Struct | Fields |
|---|---|
| `SerializedExpression` | `string $nodeType = ''`, `string $type = ''` |
| `SerializedParameterExpression` | `string $name = ''`, `int $index = 0` |
| `SerializedPropertyAccessExpression` | `SerializedExpression $object`, `string $property = ''` |
| `SerializedNullSafeAccessExpression` | `SerializedExpression $object`, `string $property = ''` |
| `SerializedMethodCallExpression` | `SerializedExpression $object`, `string $method = ''`, `array<SerializedExpression> $arguments = []` |
| `SerializedStaticMethodCallExpression` | `string $class = ''`, `string $method = ''`, `array<SerializedExpression> $arguments = []` |
| `SerializedBinaryExpression` | `SerializedExpression $left`, `string $operator = ''`, `SerializedExpression $right` |
| `SerializedUnaryExpression` | `string $operator = ''`, `SerializedExpression $operand`, `bool $isPrefix = true` |
| `SerializedConstantExpression` | `mixed $value = null` |
| `SerializedTernaryExpression` | `SerializedExpression $condition`, `?SerializedExpression $ifTrue = null`, `SerializedExpression $ifFalse` |
| `SerializedCoalesceExpression` | `SerializedExpression $left`, `SerializedExpression $right` |
| `SerializedArrayAccessExpression` | `SerializedExpression $array`, `SerializedExpression $index` |
| `SerializedCastExpression` | `string $targetType = ''`, `SerializedExpression $operand` |
| `SerializedNewExpression` | `string $class = ''`, `array<SerializedExpression> $arguments = []` |
| `SerializedInstanceofExpression` | `SerializedExpression $operand`, `string $targetType = ''` |

See [Structs](tyhp_0400_structs.md) for how struct types work.

### PathNode

:::member[type PathNode = struct { \Tyhp\Expression\ParameterExpression $parameterExpression; \Tyhp\Expression\ExpressionNode $body; }]
Declared in `Tyhp\Expression\Structs`. It pairs the `source` parameter of a property chain with the chain's body node. `PropertyPath` and the builders use it internally when they build their trees; application code does not normally need it.
:::

## Gotchas

:::warning
**Unhandled nodes become `null`.** `ExpressionVisitor`'s default methods return `null` and do not visit children. A translator that forgets a node type silently produces `null` for it. Check visitor results, as `SqlWhereTranslator::translate()` does, and recurse explicitly in your overrides.
:::

:::warning
**Captured values are read when the tree is built.** A captured variable becomes a `ConstantExpression` holding its value at the time of the call. If you store the tree and the variable changes later, the tree keeps the old value. Objects are held by reference, so changes to a captured object's properties are visible.
:::

:::warning
**Handle both spellings of logical operators.** `$a and $b` produces the operator `'and'` and `$a || $b` produces `'||'`. Translators should accept `'&&'`/`'and'` and `'||'`/`'or'`.
:::

:::note
**Compare parameters by index.** Each use of a parameter in the body is a new `ParameterExpression` object, separate from the objects in `$parameters`. `PropertyPath` and builder trees name their parameter `source`, and combined trees can contain two different names for the same position. `$index` is the reliable key.
:::

:::note
**`equals()` is literal.** Two trees are equal only if their JSON is identical: same parameter names, same node types, same constant values. `fn ($u) => …` and `fn ($x) => …` with identical bodies are not equal.
:::

:::note
**Node types are strings for display, not for parsing.** Literal constants carry literal types (`'18'`), builder nodes use `'mixed'`, and class names have no leading backslash. Check `ConstantExpression::$value` with PHP's type functions, and use `$nodeType` or the node class to decide what a node is.
:::

:::note
**Finish builder chains.** After `->and()` with no argument, the builder still looks like an `Expression`, but its body and closure describe only the left side until a comparison completes the right side.
:::

:::tip
**Accept `Expression` even when you sometimes only need to run the code.** Every tree carries its closure. You can call the expression like a function or pass it to a PHP `callable` parameter such as `\array_filter()`'s, so the same API serves both a database backend that translates the tree and an in-memory backend that just runs it.
:::

## Related pages

- [Parsable Lambdas and Expression Trees](tyhp_3000_parsableLambdas.md) — the language feature: which `fn` bodies become trees, type rules, `nameof`, and compiler errors.
- [Runtime Packages Overview](package_intro.md) — what each `tyhp/*` package provides.
- [Composer Runtime Packages](project_composerPackages.md) — version pins and installation.
- [The tyhp/core Package](package_core.md) — the runtime support package that `tyhp/lambda` depends on.
- [Generics](tyhp_0500_generics.md) — generic classes such as `Query<T>` and the `T extends object` bound used by the builders.
- [Structs](tyhp_0400_structs.md) — the struct types used for serialized nodes.
