---
title: 'Type Aliases in Tyhpdef'
status:
  tier: 0
  story: '02'
  state: complete
---

Tyhpdef supports declaring type aliases using the type keyword. Type aliases give a name to a complex type expression, making declarations more readable and reusable. They can be declared at the root level, inside a namespace block, or in a class body with a visibility modifier.

A tyhpdef alias is check-only unless it carries `#[\Tyhp\GenericRuntime(aliasFactory: …)]`. Check-only aliases (PHP overlays, harvested stubs) expand in hints and `typeof` inlines the body. A compiled Tyhp library stamps `aliasFactory` when it actually emitted a `\Tyhp\Type` factory; consumers then call that factory (`DecimalCoercible()`, `UserService::NameType()`) instead of inlining. Class and method `GenericRuntime` stamps are independent and do not require helpers (`erased: true` is still written).

## Basic Type Aliases

A type alias is declared with the type keyword, followed by the alias name, an equals sign, the underlying type expression, and a semicolon.

```tyhp
<?tyhpdef

type UserId = int;

type Email = string;

type Scalar = int|float|string|bool;

type OptionalString = ?string;

type StatusCode = 200|301|302|404|500;
```

## Object-shape aliases

The right-hand side of a tyhpdef `type` alias may be `object { … }` (or a nominal type intersected with a shape). That alias is a structural instance type. Use the name in signatures; see [Object Shapes and `__New<T>`](tyhp_3400_newTypeConstraint.md).

```tyhp
<?tyhpdef

type ClockShape = object {
    public function now(): \DateTimeImmutable;
};

type FallbackConstraint = object {
    public function getPrettyString(): string;
    public function __toString(): string;
};

type TimestampedLogger = \Psr\Log\LoggerInterface & object {
    public function getLastLogAt(): \DateTimeImmutable;
};

function createClock(): ClockShape;
function parseConstraint(string $pretty): \Composer\Semver\Constraint\ConstraintInterface | FallbackConstraint;
```

Recursive shapes that mention their own name are allowed. Empty `type X = object {};` is illegal; write `object`.

## Callable-shape and struct-shape aliases

A tyhpdef alias may also name a callable shape or a struct shape. Inline `callable(…): R` and `struct { … }` are legal in signatures. `new` of a callable-shape alias is illegal; `new` of a struct-shape alias constructs the array.

```tyhp
<?tyhpdef

type Predicate<T> = callable(T $value): bool;
type Mapper<TIn, TOut> = callable(TIn): TOut;
type Point = struct {
    float $x;
    float $y;
};

function allMatch<T>(array<T> $items, Predicate<T> $p): bool;
function origin(): struct { float $lat; float $lng; };
```

## Union and Intersection Type Aliases

Type aliases can represent union types (using the pipe operator) and intersection types (using the ampersand operator). These are especially useful for describing PHP functions that accept or return multiple types.

```tyhp
<?tyhpdef

type Stringable = string|\Stringable;

type ArrayKey = int|string;

type JsonValue = string|int|float|bool|null|array<JsonValue>;

type Countable = \Countable&\Traversable;

type TagLine = string|(callable(): string)|CheesyTagLineGeneratorInterface;
```

## Generic Type Aliases

Type aliases can have generic type parameters, making them reusable across different concrete types. Generic parameters are declared in angle brackets after the alias name and can include constraints.

```tyhp
<?tyhpdef

type Collection<T> = array<T>;

type Dictionary<TValue> = array<string, TValue>;

type Pair<TFirst, TSecond> = array{TFirst, TSecond};

type Result<T, TError extends \Throwable> = T|TError;

type Predicate<T> = callable(T): bool;

type Mapper<TIn, TOut> = callable(TIn): TOut;

type Callback<TReturn extends void|never|mixed> = callable(string): TReturn;
```

:::note
When a generic type alias wraps a callable, the constraint extends void|never|mixed on the return type parameter allows the alias to accept void and never as return types. Without this constraint, restricted types like void and never would be rejected as generic arguments.
:::

## Type Aliases in Namespaces

Type aliases can be declared inside namespace blocks to organize them logically.

```tyhp
<?tyhpdef

namespace App\Types {
    type Collection<T> = array<T>;
    type UserMap = Dictionary<User>;

    function first<T>(Collection<T> $items): ?T;
    function last<T>(Collection<T> $items): ?T;
}

namespace App\Http {
    type StatusCode = 200|301|302|404|500;
    type Headers = array<string, string|array<string>>;
    type ResponseBody = string|null;
}
```

## Using Type Aliases in Declarations

Once declared, type aliases can be used anywhere a type is expected — in function signatures, class member declarations, and other type aliases.

```tyhp
<?tyhpdef

type UserId = int;
type UserMap = array<UserId, User>;

function findUser(UserId $id): ?User;

function getAllUsers(): UserMap;

class UserService {
    public function getActive(): UserMap;
    public function findById(UserId $id): ?User;
}
```

:::tip
DO: Use type aliases for complex union or intersection types that are repeated across multiple function declarations. This keeps your tyhpdef files readable and consistent.
:::

:::tip
DO: Use generic type aliases with constraints to create reusable callable and collection type patterns.
:::

:::tip
DO: Use class-body `type` with a visibility modifier when the alias belongs to that class. Compiled libraries copy public and protected class-level aliases into `package.tyhpdef`.
:::

:::danger
DON'T: Create circular type aliases where alias A references alias B and alias B references alias A, unless every participant is an object-shape alias (recursive `type Node = object { public function parent(): ?Node; }` is allowed).
:::

## Summary

- Type aliases use the syntax: `type Name = TypeExpr;` (the RHS may also be `object { … }` or a nominal type `& object { … }`)
- Generic type parameters are supported: `type Name<T> = TypeExpr;`
- Generic parameters can have constraints: `type Name<T extends SomeType> = TypeExpr;`
- Union and intersection types are fully supported in type alias definitions
- Type aliases may appear at file/namespace scope or in a class body (`public` / `protected` / `private type`)
- Hints always expand to the underlying type
- Check-only tyhpdef aliases (no `#[\Tyhp\GenericRuntime(aliasFactory: …)]`) inline in `typeof`
- Compiled-library aliases stamped with `aliasFactory` call the library's factory
- Type aliases can reference other type aliases; keep non-shape aliases acyclic. Recursive object-shape aliases that mention their own name are allowed.
