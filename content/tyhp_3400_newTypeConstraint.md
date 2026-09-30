---
title: 'Object Shapes and `__New<T>`'
status:
  tier: 2
  story: '27'
  state: complete
---

An **object shape** is a structural object type: a named predicate on an instance. It is the object counterpart of a struct (an array shape). Two values may match the same shape and still be different PHP classes.

A shape is declared only as the right-hand side of a `type` alias, using `object { … }`. Use the alias name everywhere else (parameters, properties, returns, generic bounds, unions). `new class { … }` remains the anonymous-class **expression**.

`__New<T>` marks a shape as **constructable**: a concrete class with a public constructor that can be invoked as the shape’s `__construct` (or the PHP default zero-argument constructor when the shape has no `__construct`). Values of a shape and of `__New<Shape>` are **instances**. Class-name strings use `__ClassName<Shape>` and `__ClassName<__New<Shape>>`.

## Object shapes

```tyhp
<?tyhp

type ClockShape = object {
    public function now(): \DateTimeImmutable;
};

class WallClock {
    public function now(): \DateTimeImmutable {
        return new \DateTimeImmutable();
    }
}

function formatNow(ClockShape $c): string {
    return $c->now()->format('c');
}

formatNow(new WallClock());
```

```tyhp
<?tyhpdef

type FallbackConstraint = object {
    public function getPrettyString(): string;
    public function __toString(): string;
};

function parseConstraint(string $pretty): \Composer\Semver\Constraint\ConstraintInterface | FallbackConstraint;
```

`ClockShape` in type position means `object` refined by that shape. You do not write `object & ClockShape`.

### What a shape matches

A nominal object type (or another shape) assigns to a shape when:

- Every **public** member of the shape exists on the source (extra source members are allowed).
- Methods match by callable compatibility (parameter contravariance, return covariance).
- Properties match with readonly / hook variance (a writable shape property must be writable on the source).
- `protected` / `private` members on the source do not satisfy the shape.
- `__get` / `__call` / other magic satisfy a shape member only when the shape lists **that** magic method.

`object` and `mixed` do not assign to a shape. Narrow with `$x is ClockShape` or declare the value as the shape (including tyhpdef returns).

Empty `type X = object {};` is illegal; write `object`.

### What a shape cannot do

A shape alias is not a PHP class. These are errors:

- `new ClockShape`
- `ClockShape::foo()` / `ClockShape::class`
- `extends ClockShape` / `implements ClockShape`
- `$x->__construct(...)` when `$x` is shape-typed (`__construct` on a shape is only for `__New` / `new T()`)

`object { … }` is illegal except as the alias right-hand side.

### Nominal parents plus extra members

There is no `extends` / `implements` on the `object { }` header. Nominal parents are intersections:

```tyhp
type TimestampedLogger = \Psr\Log\LoggerInterface & object {
    public function getLastLogAt(): \DateTimeImmutable;
};
```

That type is `\Psr\Log\LoggerInterface` plus `getLastLogAt()`.

## `__New<T>`

`T` must be an object-shape alias. `T extends ClockShape` is an instance bound. `T extends __New<ClockShape>` is the same instance API **and** `new T(...)` is allowed.

```tyhp
<?tyhp

type Named = object {
    public function __construct(string $name): void;
    public function ping(): void;
};

function makeNamed<T extends __New<Named>>(string $name): T {
    return new T($name);
}
```

If the shape has **no** `__construct`, `__New<Shape>` requires the PHP default **zero-argument** public constructor (no constructor in source, or every constructor parameter has a default). That is not “any constructor.” A type can match `HasQuery` as an instance and still fail `__New<HasQuery>` if its constructor needs arguments.

`public function __construct(): void;` on a shape is the explicit zero-argument form (same matching rule). `__construct` on a shape is never an instance method.

Abstract classes, interfaces, traits, enums, and non-public constructors do not satisfy `__New<T>`. They may still satisfy the shape as instance types when the public members match.

## Class-name strings

| Type | Meaning |
|------|---------|
| `Shape` / `__New<Shape>` | Object **instance** |
| `__ClassName<Shape>` | Name of some class whose instances match `Shape` (may be abstract or non-`new`-able) |
| `__ClassName<__New<Shape>>` | Name of a concrete, public-`new`-able class matching `Shape` |

```tyhp
function spinUp(__ClassName<__New<Named>> $cls, string $name): Named {
    return new $cls($name);
}

string $raw = \getClassName();
if (\class_exists<__New<Named>>($raw)) {
    Named $obj = spinUp($raw, 'x');
}
```

`new $cls(...)` is an error when `$cls` is `__ClassName<Shape>` without `__New`. Bare `__ClassName` / `__ClassName<object>` / `__ClassName<SomeClass>` keep their existing dynamic-`new` rules.

`\class_exists<ClockShape>($name)` narrows to `__ClassName<ClockShape>`. `\class_exists<__New<ClockShape>>($name)` narrows to `__ClassName<__New<ClockShape>>`. A string literal that already names a matching class can assign without a guard.

## `is` and `instanceof`

`is` and `instanceof` are the same operator in Tyhp. Prefer `is` in examples.

`$x is ClockShape` is a **shape guard**, not PHP `instanceof` of a class. It emits `\Tyhp\Type::is(...)`. After a pass, `$x` is narrowed to the shape. `$x is User` when `User` is a real class still emits native `instanceof`.

```tyhp
function fromObject(object $obj): void {
    if ($obj is ClockShape) {
        formatNow($obj);
    }
}
```

## Compiled PHP

Shapes and `__New<Shape>` erase to `object`, or to nominal conjuncts from an intersection when those are legal PHP hints (`LoggerInterface & ClockShape` → `LoggerInterface`). Generic bounds erase with other generics. The compiler never emits a PHP class for the alias. `$x is ClockShape` emits `\Tyhp\Type::is`. `typeof(ClockShape)` / a source-alias factory produces a `\Tyhp\Type` descriptor for matching; it does not construct instances.

## Recovering an unnamed return

If a tyhpdef function returns a shape without a hand-written alias name, `__FunctionReturnType<'fn'>` / `__MethodReturnType<T, 'method'>` is that return type. Harvest of PHP `return new class { … }` writes a generated shape alias so the return is not `object`.

## Related

The three gradual PHP bases and their refinements:

| Base (untyped) | Shape | `new Alias` |
|---|---|---|
| `object` | `object { … }` — alias-only | illegal |
| `callable` | `callable(…): R` — alias or inline | illegal |
| `struct` / `array` | `struct { … }` — named as `type`, inline in type position | legal (array construction) |

- [Type Aliases](tyhp_0700_typeAliases.md)
- [New and Changed Types](tyhp_0150_newTypes.md) (`__ClassName`, `__New`, `__FunctionReturnType`, callable shapes)
- [Type Narrowing and Guards](tyhp_0200_typeNarrowingAndGuards.md)
- [Dynamic Language Features](tyhp_2400_dynamicLanguageFeatures.md)
- [Tyhpdef Generation](cli_tyhpdefGeneration.md) (anonymous-class harvest)
- [Structs](tyhp_0400_structs.md)
