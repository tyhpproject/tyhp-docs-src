---
title: 'Function and Method Overloads'
status:
  tier: 1
  story: '11'
  state: complete
---

Tyhp lets you declare several signatures for one function or method, so the type checker can give each call the return type that matches its arguments. A signature without a body is an **overload signature**; the declaration with a body that follows the signatures is the **implementation**. Callers see only the overload signatures. In the PHP output the overload signatures are removed and the single implementation remains, so overloading creates no extra PHP functions and has no runtime cost.

## Basic Function Overloads

An overload signature is a `function` declaration that ends with a semicolon instead of a body. Write the signatures one after another, then the implementation directly after them. The implementation must accept every call the signatures describe.

```tyhp
<?tyhp

namespace App;

// Overload: when $asInt is true, returns int
function convertNumber(string|int|float $value, true $asInt): int;

// Overload: when $asInt is false, returns float
function convertNumber(string|int|float $value, false $asInt): float;

// Implementation
function convertNumber(string|int|float $value, bool $asInt = false): int|float
{
    return $asInt ? \intval($value) : \floatval($value);
}

int $asInt = convertNumber("42", true);      // int
float $asFloat = convertNumber("42", false); // float
```

The implementation's own signature is not callable. `convertNumber("42")` and `convertNumber("42", $flag)` with a `bool` variable `$flag` match neither overload, so they report TYHP4374 even though the implementation accepts them. Add an overload for them if callers need them:

```tyhp
function convertNumber(string|int|float $value, bool $asInt = false): int|float;
```

## Compiled PHP Output

Only the implementation is emitted:

```php
<?php

declare(strict_types=1);

namespace App;

function convertNumber(string|int|float $value, bool $asInt = false): int|float
{
    return $asInt ? \intval($value) : \floatval($value);
}
```

## Static Value Type Overloads

A [static value type](tyhp_0800_staticValueTypes.md) constrains a parameter to a specific literal value (`true`, `false`, an integer, a string). Combined with overloads it lets the return type depend on the exact value passed.

```tyhp
<?tyhp

namespace App;

function transform(string $input, 'list' $mode): array<int, string>;
function transform(string $input, 'upper' $mode): string;
function transform(string $input, 'raw' $mode): string;
function transform(string $input, string $mode): array<int, string>|string
{
    return match ($mode) {
        'list' => \explode(',', $input),
        'upper' => \strtoupper($input),
        default => $input,
    };
}

string $upper = transform('a,b', 'upper');
array<int, string> $items = transform('a,b', 'list');
```

## Method Overloads

Method overloads work like function overloads. Every signature and the implementation must use the same modifiers (visibility, `static`, `final`, `async`, `abstract`).

```tyhp
<?tyhp

namespace App;

final class Repository
{
    public function find(int $id): string;
    public function find(string $email): ?string;
    public function find(int|string $criteria): ?string
    {
        return null;
    }

    public static function create(int $id): self;
    public static function create(string $name): self;
    public static function create(int|string $arg): self
    {
        return new self();
    }
}

function lookup(Repository $repository): void
{
    string $byId = $repository->find(1);
    ?string $byEmail = $repository->find('ann@example.com');
    Repository $created = Repository::create('ann');
}
```

```php
<?php

declare(strict_types=1);

namespace App;

final class Repository
{
    public function find(int|string $criteria): ?string
    {
        return null;
    }

    public static function create(int|string $arg): self
    {
        return new self();
    }
}
```

Constructors and destructors cannot be overloaded (TYHP3036). Declare factory methods, or optional parameters, instead.

## Interface and Abstract Method Overloads

An interface method or an `abstract` method has no body, so a run of signatures for the same name forms the whole set. Callers of the interface or abstract class can use every signature; an implementing class provides one method that accepts them all. An override of an `abstract` set is checked against every signature, so its parameter types must accept each signature's parameters and its return type must be assignable to each signature's return type (TYHP4118).

```tyhp
<?tyhp

namespace App;

interface Store
{
    public function get(int $id): string;
    public function get(string $name): ?string;
}

final class MemoryStore implements Store
{
    public function get(int|string $key): ?string
    {
        return null;
    }
}

function load(Store $store): void
{
    string $a = $store->get(1);
    ?string $b = $store->get('config');
}
```

PHP receives one method per set: the last signature. That is the signature PHP checks the implementing method against.

```php
<?php

declare(strict_types=1);

namespace App;

interface Store
{
    public function get(string $name): ?string;
}
```

## Async Overloads

Async functions and methods can be overloaded. Every signature and the implementation must be marked `async`. As for any `async` declaration, each signature's return type `R` is read as the settled type `__Awaited<R>`, so a call returns `Promise<R>` and `await` produces `R` (see [Async and Await](tyhp_2600_asyncAndAwait.md)).

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

final class ApiClient
{
    async public function fetch(int $id): string;
    async public function fetch(string $url): string;
    async public function fetch(int|string $target): string
    {
        await Promise::delay(1);
        return \is_int($target) ? "/items/{$target}" : $target;
    }
}

async function show(ApiClient $client): string
{
    return await $client->fetch(1);
}
```

## Overloads with Short Function Syntax

The implementation can use [short function syntax](tyhp_1100_shortFunctionSyntax.md). The overload signatures stay `function` declarations that end with `;`.

```tyhp
<?tyhp

namespace App;

function negate(int $value): int;
function negate(float $value): float;
fn negate(int|float $value): int|float => -$value;
```

```php
<?php

declare(strict_types=1);

namespace App;

function negate(int|float $value): int|float
{
    return -$value;
}
```

## How a Call Picks an Overload

The checker tries the declared signatures **in declaration order** and uses the **first** one that accepts the call as written, so declare narrower signatures before broader ones.

1. A signature accepts a call when the arguments (positional, named, spread, and variadic) cover its required parameters and each argument is assignable to its parameter type as written.
2. Generic signatures infer their type arguments per signature.
3. An inline closure is checked against a `callable` parameter by parameter count and by any explicit parameter and return type annotations; an unannotated closure is checked against the selected signature. A closure also matches an `Expression<callable(…)>` or `PropertyPath<…>` parameter by its callable shape.
4. If no signature accepts the call as written, the signatures are tried again allowing the implicit conversions an ordinary call applies (see [Overloads and Implicit Conversions](#overloads-and-implicit-conversions)).
5. If no signature accepts the call even with conversions, the checker reports TYHP4374 and lists the candidates.

```tyhp
<?tyhp

namespace App;

function describe(int $x): string;
function describe(mixed $x): int;
function describe(mixed $x): string|int
{
    return 1;
}

string $a = describe(1);   // first signature accepts an int
int $b = describe('a');    // only the second accepts a string
```

Reversing the two signatures would make `describe(1)` return `int`, because `mixed` would then accept the call first.

In the editor, hover and signature help list the declared signatures. Completion shows the first signature and the number of further overloads.

## Overloads and Implicit Conversions

An ordinary call to a function accepts an argument that reaches the parameter through an implicit [`operator convert`](tyhp_1600_operatorOverloads.md). A call to an overloaded function does too, but only after no signature accepts the call as written, so a signature that needs a conversion never beats one that accepts the arguments directly, even when it is declared first.

```tyhp
<?tyhp

namespace App;

final class Money
{
    public function __construct(public int $cents) {}

    operator convert(int $value)
    {
        return new self($value);
    }
}

function takeMoney(Money $amount): string;
function takeMoney(string $label, int $cents): string;
function takeMoney(Money|string $first, int $cents = 0): string
{
    return $first instanceof Money ? "money:{$first->cents}" : "label:{$first}:{$cents}";
}

function run(): void
{
    echo takeMoney(new Money(5)), "\n";   // accepted as written
    echo takeMoney(5), "\n";              // only the first signature accepts it, through the conversion
    echo takeMoney('tip', 3), "\n";       // accepted as written
}
```

The compiled call applies the conversion, and PHP still receives the one `takeMoney` function:

```php
echo takeMoney(\App\Money::__from(5)), "\n";
```

The conversions considered are the ones an ordinary call applies: conversions declared on a class or in an extension, and conversion of an object to a scalar parameter (for example passing a `Celsius` object to an `int` parameter when `Celsius` declares `operator convert(self $value): int`). A conversion removed with `operator convert hide` is not considered.

When several signatures accept the call only through conversions, the compiler chooses between them:

1. A signature that converts only some of the arguments another signature converts, and converts those to the same types, is preferred.
2. If the remaining signatures convert the arguments to the same types, the first declared is used.
3. If they convert the arguments to different types, the call is ambiguous and reports TYHP4375. Convert an argument yourself (for example `new Money(5)`) so that one signature accepts the call as written.

A first-class callable of an overload set (`$fn = takeMoney(...)`) applies the same conversions when it is called, so `$fn(5)` works and `\array_map($fn, [5, 6])` works. See [Overloaded Functions as Values](#overloaded-functions-as-values). A call through `__invoke` (`$object->__invoke(5)` or `$object(5)`) is an ordinary method call and follows the rules above.

## Overloaded Functions as Values

A reference to an overload set, such as `describe(...)`, `$object->find(...)`, `Repository::create(...)`, or an object whose `__invoke` is overloaded, is a callable value that carries one callable form per declared signature, in declaration order. The implementation signature is not part of it.

- Calling the value uses the first form that accepts the arguments, and reports TYHP4374 when none does.
- The value also accepts every type that converts implicitly to a signature's parameter (see below), so `$describe(5)` works when `Money` has `operator convert(int $value)`.
- Assigning the value to a `callable(…)` type succeeds when at least one declared signature satisfies that type. A variable declared with a `callable(…)` type keeps exactly that type, so it does not accept the converting types.

```tyhp
<?tyhp

namespace App;

function run(): void
{
    $describe = describe(...);
    int $n = $describe('a');                          // picks the second signature
    callable(int): string $asString = describe(...);  // the first signature satisfies it
}
```

### Implicit conversions on the value

When a signature has a parameter that other types convert to through [`operator convert`](tyhp_1600_operatorOverloads.md), the first-class callable is compiled to a small wrapper closure that accepts those types too and applies the conversion before it calls the function. The value is typed with the widened parameters, so it works with the `takeMoney` set above:

```tyhp
<?tyhp

namespace App;

function run(): void
{
    $fn = takeMoney(...);
    echo $fn(5), "\n";             // money:5, converted to a Money
    echo $fn('tip', 3), "\n";      // label:tip:3
    echo $fn(new Money(6)), "\n";  // money:6
}
```

```php
$fn = (static fn(\App\Money|string|int $first, int $cents = 0): string => takeMoney((\is_int($first) ? \App\Money::__from($first) : $first), $cents));
```

With several signatures, conversion is decided one parameter position at a time:

1. A type that some signature accepts as written at that position is never converted. With `pick(Money $m)` and `pick(int $n)`, an `int` argument goes to `pick(int $n)`.
2. Any other type that converts to a signature's parameter at that position is converted to it, and the value accepts that type.
3. A type that would convert to different types in different signatures is ambiguous. The compiler reports TYHP4376 at the `(...)`, and that position keeps its declared types. If `Money` and `Meters` both declare `operator convert(int $value)`, `measure(Money $m)` and `measure(Meters $m)` give `$fn = measure(...)` an `int` position that cannot be resolved. Call `measure(...)` directly, or give the signatures the same type at that position.

Only a first-class callable value is widened. A variable declared `callable(Money): string` and a closure written with `fn` or `function` keep exactly the types they declare, so `$fn(5)` on either reports TYHP4010. By-reference, variadic, and generic-typed parameters are not widened. When no parameter of the function has a conversion, `f(...)` is the plain native first-class callable.

The wrapper costs one extra call frame and appears as an anonymous closure in reflection and stack traces. It keeps the function's return type. The conversion test runs when the value is called: an argument that matches none of the convertible types is passed on unchanged, and PHP reports a `\TypeError` if the function does not accept it.

## Rules

1. Write the overload signatures first and the implementation directly after them; nothing else may be declared between them (TYHP3032). The implementation has a body. A set without one reports TYHP3031, except in an interface or an `abstract` method, where the signatures are the whole set.
2. Declare at least two overload signatures. A single one reports warning TYHP3033; use the implementation's own signature instead.
3. Two signatures with the same parameters and return type report TYHP3034.
4. All signatures and the implementation share the same modifiers: `static`, visibility, `async`, `abstract`, `final` (TYHP3035).
5. The implementation must be compatible with every signature (TYHP4118): each signature's parameter types must be assignable to the implementation's, and the return types must be assignable in at least one direction. The implementation's return type may be narrower or broader than a signature's, but not unrelated to it.
6. Constructors and destructors cannot have overloads (TYHP3036).
7. Only the implementation is emitted to PHP (for an interface or an `abstract` set, the last signature).

## Compiler Errors

| Code | Meaning |
|---|---|
| TYHP3031 | An overload signature has no implementation. |
| TYHP3032 | An overload signature is not directly before its implementation. |
| TYHP3033 | Warning: only one overload signature was declared. |
| TYHP3034 | A signature repeats the parameters and return type of an earlier one. |
| TYHP3035 | Signatures in a set use different modifiers. |
| TYHP3036 | Constructors and destructors cannot be overloaded. |
| TYHP4118 | An overload signature is not compatible with the implementation. |
| TYHP4374 | No overload accepts the call, even with implicit conversions. |
| TYHP4375 | The call needs implicit conversions to different types in more than one overload, so the choice is ambiguous. |
| TYHP4376 | A first-class callable of an overload set cannot convert an argument at one position, because the overloads convert it to different types. |

See the [diagnostics reference](diagnostics_reference.md) for the full messages.

## Best Practices

:::tip
Use overloads when the return type depends on the argument types. A union return type plus a type guard at the call site is often enough when it does not.
:::

:::tip
Combine overloads with static value types to give each literal value its own precise return type.
:::

:::tip
Put the narrowest signature first and the catch-all last; the first signature that accepts the call as written wins.
:::

## Common Mistakes

```tyhp
<?tyhp

// ERROR (TYHP3031): signatures without an implementation
// function doSomething(int $a): void;
// function doSomething(string $a): void;

// ERROR (TYHP3035): different visibility across the set
// class BadService {
//     public function process(int $id): void;
//     private function process(string $name): void;
//     public function process(int|string $arg): void { /* ... */ }
// }

// ERROR (TYHP4118): the implementation does not accept the string signature
// function narrow(int $a): int;
// function narrow(string $a): string;
// function narrow(int $a): int { return $a; }
```
