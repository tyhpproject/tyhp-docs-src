---
title: 'The Mixed Type'
status:
  tier: 0
  story: '08'
  state: complete
---

The mixed type is the top type in Tyhp's type system. It represents any value — int, string, object, array, null, or any other type. While PHP allows mixed to be used freely, Tyhp adds compile-time safeguards: you must narrow a mixed value through a type guard before performing type-specific operations on it. This prevents runtime type errors that would otherwise go undetected.

## What Mixed Means

In Tyhp's type system, mixed is the supertype of everything. Any value is assignable to mixed, and mixed is the default type used when a generic type parameter has no constraint and its type argument is erased.

- mixed accepts any value — int, string, float, bool, array, object, callable, null, and all user-defined types.
- mixed|T is simplified to mixed (mixed absorbs all union members).
- mixed&T is simplified to T (mixed is the identity for intersection).
- A variable typed as mixed can hold any value but cannot be used in type-specific operations without narrowing.

```tyhp
<?tyhp

// mixed accepts any value
mixed $value = 42;
$value = 'hello';
$value = [1, 2, 3];
$value = null;
$value = new SomeObject();
```

## Requiring Type Guards Before Use

Tyhp enforces that you narrow a mixed value to a specific type before performing type-specific operations. This is done through type guards: instanceof/is checks (`$x is string` emits `\is_string($x)` when that tyhpdef is marked `#[\Tyhp\NativeTypeTest]`; unmarked classes use `instanceof`; remaining forms use `\Tyhp\Type::is`), type-checking functions (`is_string`, `is_int`, etc.), null checks (`$item === null` / `$item !== null` / `$item is null`), and user-defined type guard functions.

```tyhp
<?tyhp

function processValue(mixed $value): string {
    // ERROR — cannot call string methods on mixed
    // return \strtoupper($value);

    // ERROR — cannot perform arithmetic on mixed
    // return $value + 1;

    // Correct — narrow first, then use
    if ($value is string) {
        return $value;  // $value is automatically narrowed to string
    }

    if (\is_int($value)) {
        return (string)$value;  // $value is narrowed to int
    }

    return '';
}
```

## What Needs Narrowing

Anything is assignable **to** `mixed`, but a `mixed` value is assignable only to `mixed` until it is narrowed: passing it to an `int` parameter or assigning it to an `int` variable is an error (TYHP4010, TYHP4008). These uses of a `mixed` value report TYHP4160 or a more specific diagnostic until the value is narrowed:

- member access and method calls (`$m->name`, `$m->run()`), calling the value (`$m()`), and `$m::class`;
- indexing (`$m[0]`);
- arithmetic and the relational operators `<`, `>`, `<=`, `>=`;
- string concatenation, interpolation, `echo`, and `print`;
- spreading it (`[...$m]`, `f(...$m)`);
- `$m->name ?? 1` and `$m->name ??= 1` on an instance member.

Comparison with `===`, `isset()`, `$m ?? 1`, `$m['key'] ?? 1`, and an explicit cast such as `(int) $m` are not narrowing errors. A class constant declared `const mixed X` reads as `mixed` at every use.

```tyhp
<?tyhp

function show(mixed $value): string {
    // $value + 1;        // ERROR (TYHP4160)
    // "v={$value}";      // ERROR (TYHP4120)
    // $value->name;      // ERROR (TYHP4160)
    $count = (int) $value;  // explicit cast
    return (string) $count;
}
```

Narrowing with `||` and `&&` combines the guards of variables: after `if ($m is int || $m is string)` the variable is `int|string`, and `if ($m is int && $m > 0)` narrows before the comparison runs. A guard on a property (`$h->p is int`) narrows on its own, but guards on properties and index keys are not combined across `||`. After `$m instanceof User`, `$m` is `User`; a guard that is redundant for a variable that already has a precise type keeps the precise type. When an assignment narrows a variable, its right-hand side is checked first with the variable's previous type, so `$m = $m + 1;` on a `mixed` `$m` is an error.

A null check alone does not narrow `mixed` to a specific type: after `$m !== null` the value is still `mixed`.

## Mixed and Generic Arguments

A `mixed` argument binds a type parameter to `mixed`. A parameter declared `T extends int|string` therefore rejects it (TYHP4035), while an unconstrained `T` binds to `mixed`. A nullable argument binds an unconstrained `T` to the nullable type: passing an `?int` to `T $v` gives `T = ?int`.

```tyhp
<?tyhp

function bounded<T extends int|string>(T $v): T { return $v; }
function bare<T>(T $v): T { return $v; }

function demo(mixed $m, ?int $n): void {
    // bounded($m);          // ERROR (TYHP4035): `mixed` does not satisfy `int|string`
    mixed $a = bare($m);     // T = mixed
    ?int $b = bare($n);      // T = ?int
}
```

A spread argument must be iterable, and its elements are checked against the parameters they fill: `f(...[1, 2])` for `f(string ...$s)` is rejected. A non-array argument to a generic builtin such as `\array_values(5)` is rejected rather than accepted as `mixed`.

## Members That Do Not Exist

Reading or calling a member that is not declared on a class, interface, or `object` type reports TYHP4101. A guard such as `\property_exists($f, 'name')` or `\method_exists($f, 'run')` makes the member available inside the guarded branch. A bare `object` has no members, so every access on it needs a narrowing check first.

## Mixed and Generic Types Without Type Arguments

`mixed` is also what an unspecified type argument means. A generic class written without type arguments (`Box` for `class Box<T>`) is `Box<mixed>` when it is assigned to an instantiation of the same class, and each type parameter widens to its declared `extends` bound when it has one. Like a `mixed` value, it is not assignable to a more specific target: `Box` is not assignable to `Box<int>`, while `Box<int>` is assignable to `Box` and `Box` is assignable to `Box<mixed>`. See [Generic Types Without Type Arguments](tyhp_0500_generics.md#generic-types-without-type-arguments).

An `instanceof` check on a `mixed` value narrows it to the raw class, so it is assignable to `Box<mixed>` but not to `Box<int>`:

```tyhp
<?tyhp

namespace App;

class Box<T> {
    public function __construct(public T $value) {}
}

function unwrap(mixed $candidate): Box<mixed> {
    if ($candidate instanceof Box) {
        return $candidate;       // OK: Box is Box<mixed>
    }
    return new Box<mixed>(null);
}
```

## Automatic Smart Casts

After a type guard narrows the type, the compiler automatically tracks the narrower type within the guard's scope. No explicit casts or re-declarations are needed. This works with instanceof/is checks, null checks, built-in type-checking functions, and user-defined type guard functions.

```tyhp
<?tyhp

function describe(mixed $item): string {
    if ($item === null) {
        return 'null';
    }
    // After the null check, $item is non-null mixed

    if ($item instanceof User) {
        // $item is automatically User here
        return 'User: ' . $item->name;
    }

    if (\is_array($item)) {
        // $item is automatically array here
        return 'Array with ' . \count($item) . ' elements';
    }

    if (\is_string($item)) {
        // $item is automatically string here
        return 'String: ' . \strtoupper($item);
    }

    return 'Unknown type';
}
```

:::note
Negative narrowing also works: in the else-branch of a type guard, the type is narrowed to exclude the checked type. Multiple checks in sequence further narrow the type.
:::

## When Mixed Is Acceptable

There are legitimate use cases for mixed:

- Deserialization functions that return data of unknown shape (e.g., JSON decoding).
- Generic container implementations where the type parameter has no constraint.
- Wrapper functions that accept any value and pass it through (e.g., logging, caching).
- Interop with untyped PHP libraries where the return type is genuinely unknown.
- Event systems or message buses where the payload type varies.

```tyhp
<?tyhp

// Acceptable — JSON decoding returns unknown structure
function decodePayload(string $json): mixed {
    return \json_decode($json, true);
}

// Acceptable — logging wrapper that accepts any value
function logValue(string $label, mixed $value): void {
    echo $label . ': ' . \var_export($value, true);
}
```

## Compiler Errors with Mixed

The compiler produces errors when mixed values are used in type-specific operations without narrowing.

```tyhp
<?tyhp

function badExample(mixed $value): void {
    // ERROR — cannot call methods on mixed without narrowing
    // $value->doSomething();

    // ERROR — cannot perform arithmetic on mixed
    // int $result = $value + 1;

    // ERROR — cannot access properties on mixed
    // string $name = $value->name;

    // ERROR — cannot index mixed as array
    // $item = $value[0];
}
```

## There Is No Escape Hatch, By Design

Narrowing is not optional and there is no compiler setting that relaxes it. Tyhp has exactly one top type, and it is always strict: a mixed value must be narrowed to a specific type before you can do anything type-specific with it. There is no second, permissive top type to fall back on.

If you know TypeScript, mixed behaves like TypeScript's unknown, and Tyhp deliberately has no equivalent of TypeScript's any. TypeScript ships both only for historical reasons — any predates unknown and could not be made strict without breaking existing code, so unknown was added alongside it as the safe alternative. Tyhp starts from the strict semantics instead, so the unsafe variant never needs to exist.

:::note
A project-wide toggle would also break down across package boundaries: a library compiled with relaxed rules and consumed by a strict project would leave the meaning of its published signatures ambiguous. Keeping one unconditional rule keeps a type's meaning identical in every project that consumes it.
:::

When narrowing feels impossible, that is a signal the type is wrong rather than a reason for an escape hatch. Prefer a union type when you know the accepted types, generics when the type varies with a caller, or a user-defined type guard when the check is genuinely a runtime one.

## Mixed in Generic Erasure

When generics are erased for PHP output, unconstrained type parameters become mixed. Constrained type parameters use their constraint type instead. This means generic code in PHP output uses mixed where the original Tyhp code was type-safe through generics.

```tyhp
<?tyhp

// Unconstrained — T becomes mixed in PHP output
function identity<T>(T $value): T {
    return $value;
}

// Constrained — T becomes Countable in PHP output
function countItems<T extends Countable>(T $items): int {
    return \count($items);
}
```

```php
<?php
// PHP output — unconstrained generics become mixed,
// constrained generics use the constraint type
declare(strict_types=1);

function identity(mixed $value): mixed {
    return $value;
}

function countItems(Countable $items): int {
    return \count($items);
}
```

## Prefer Generics or Union Types Over Mixed

When you know the range of types a value can hold, use generics or union types instead of mixed. Generics preserve type information across calls, and union types make the accepted types explicit.

```tyhp
<?tyhp

// Bad — using mixed when the types are known
function formatValue(mixed $value): string {
    // Must narrow before using
    if (\is_int($value)) { return (string)$value; }
    if (\is_float($value)) { return \number_format($value, 2); }
    return '';
}

// Better — use a union type
function formatValue(int|float $value): string {
    if (\is_int($value)) { return (string)$value; }
    return \number_format($value, 2);
}

// Better — use generics for type preservation
function wrap<T>(T $value): array<T> {
    return [$value];
}
```

## Best Practices

:::tip
Use mixed only when the type is genuinely unknown at compile time — JSON data, untyped library interop, or truly polymorphic APIs.
:::

:::tip
Always narrow mixed values with type guards (is, instanceof, is_string(), etc.) before performing type-specific operations. The compiler automatically tracks the narrowed type.
:::

:::tip
Prefer specific types, union types, or generics over mixed whenever the accepted types are known. This provides better type safety and IDE support.
:::

:::tip
Use generics instead of mixed for function parameters and return types when the type should be preserved through the call — generics maintain type information that mixed discards.
:::

## Common Mistakes

:::danger
Don't use mixed as a lazy alternative to union types — if a value can be int or string, use int|string, not mixed.
:::

:::danger
Don't perform operations on mixed values without narrowing — calling methods, accessing properties, or performing arithmetic on mixed produces a compile error.
:::

:::danger
Don't use mixed as a function parameter type when generics would be more appropriate — generics preserve type information through calls, while mixed discards it.
:::

:::danger
Don't use mixed for return types when the return type is deterministic — the caller loses all type information and must narrow the result.
:::
