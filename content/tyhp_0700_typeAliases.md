---
title: 'Type Aliases'
status:
  tier: 1
  story: '11'
  state: complete
---

Type aliases in Tyhp give a name to a type expression. Use the name in type position (hints, annotations, generic arguments). A source `.tyhp` alias also emits a PHP factory that returns `\Tyhp\Type` for that body, so PHP and Tyhp can name the alias at runtime. Type **hints** still expand to the underlying PHP type — the factory is never used as a PHP type hint.

Type aliases can be declared at the root level (within a namespace) or inside a class body with visibility modifiers.

## Type, `typeof`, and factory calls

`<>` is type-position syntax. `typeof(...)` takes a type and produces a `\Tyhp\Type` value. Calling the alias by name is the same factory PHP will call: arguments are `\Tyhp\Type` values, not type arguments.

| Intent | Write |
|---|---|
| The type (hints, annotations) | `UserId`, `Optional<int>` |
| The Type value, from a type | `typeof(UserId)`, `typeof(Optional<int>)` |
| The Type value, by calling the factory | `UserId()`, `Optional()`, `Optional(typeof(int))` |

`UserId()` in Tyhp is the same as `typeof(UserId)`: alias-name-as-call. The PHP function or static method exists for PHP interop. It is not autodetection of an existing method — `\Tyhp\Type::bool()` is an ordinary method; unqualified `bool` stays the builtin type.

:::danger
`Optional<int>()` is invalid. It mixes type-argument syntax into a value call. Write `typeof(Optional<int>)` or `Optional(typeof(int))` instead (`TYHP4186`).
:::

```tyhp
<?tyhp

namespace App\Types;

type UserId = int;
type Optional<T = mixed> = T|null;

function findUser(UserId $id): ?User {
    // ...
}

\Tyhp\Type $idType = typeof(UserId);
\Tyhp\Type $optInt = typeof(Optional<int>);
\Tyhp\Type $also = Optional(typeof(int));
\Tyhp\Type $defaulted = Optional();
```

PHP writes the same factory with `\Tyhp\Type` arguments — not `<int>()`:

```php
<?php
declare(strict_types=1);

namespace App\Types;

function UserId(): \Tyhp\Type
{
    return \Tyhp\Type::int();
}

function Optional(?\Tyhp\Type $T = null): \Tyhp\Type
{
    $T ??= \Tyhp\Type::mixed();
    return \Tyhp\Type::nullable($T);
}

function findUser(int $id): ?User {
    // ...
}

$idType = UserId();
$optInt = Optional(\Tyhp\Type::int());
$also = Optional(\Tyhp\Type::int());
$defaulted = Optional();
```

The factory is always emitted from a `.tyhp` alias, even when that file never writes `typeof`. Nested source aliases call inner factories (`type UserIds = array<UserId>` → `UserIds()` uses `UserId()`). `UserId()` returns the same structure `typeof` would build for the body (`Type::int()`), not a distinct alias identity — `Type::is($n, UserId())` matches ints.

## Root-Level Type Aliases

A root-level type alias is declared with the type keyword followed by a name, an equals sign, and a type expression. It can appear at the namespace level alongside class and function declarations.

```tyhp
<?tyhp

namespace App\Types;

type UserId = int;
type StringOrNull = string|null;
type Callback = callable(string, int): bool;

function findUser(UserId $id): ?User {
    // ...
}

function filter(array $items, Callback $predicate): array {
    return \array_filter($items, $predicate);
}
```

Hints erase; the factory lives next to other namespace functions in `_functions.php`:

```php
<?php
declare(strict_types=1);

namespace App\Types;

function UserId(): \Tyhp\Type
{
    return \Tyhp\Type::int();
}

function findUser(int $id): ?User {
    // ...
}

function filter(array $items, callable $predicate): array {
    return \array_filter($items, $predicate);
}
```

A file-level alias occupies the Tyhp function namespace as well as the type namespace. `type Foo` and `function Foo()` in the same namespace is an error (`TYHP3028`). Names that cannot be PHP functions (`echo`, `list`, `empty`, `int`, …) are an error at file level (`TYHP3030`). `type Foo` and `class Foo` still collide as class-likes.

## Generic Type Aliases

Type aliases can have generic type parameters, making them reusable templates for type expressions. Generic type alias parameters support the same syntax as class generics — including constraints and defaults.

```tyhp
<?tyhp

type Collection<T> = array<T>;
type EntityList<T extends Entity> = array<T>;
type Optional<T = mixed> = T|null;
type Map<TKey, TValue> = array<TKey, TValue>;

Collection<string> $names = ['Alice', 'Bob'];
Optional<int> $age = null;
Optional $unknown = null;
Map<string, User> $users = [];

\Tyhp\Type $t = typeof(Optional<int>);
\Tyhp\Type $m = typeof(Map<string, User>);
```

```php
<?php
declare(strict_types=1);

$names = ['Alice', 'Bob'];
$age = null;
$unknown = null;
$users = [];

$t = Optional(\Tyhp\Type::int());
$m = Map(\Tyhp\Type::string(), \Tyhp\Type::fromClassName(User::class));
```

The PHP factory takes optional `?\Tyhp\Type` parameters named after the alias’s generic parameters. Defaults match the alias’s generic defaults (or `Type::mixed()`). Constraints are checked at Tyhp use sites; the PHP factory does not re-check them at runtime.

## Object-shape aliases

A `type` alias whose right-hand side is `object { … }` is an **object shape**: a structural instance type. Use the alias name in every other type position (parameters, properties, returns, generic bounds, unions). See [Object Shapes and `__New<T>`](tyhp_3400_newTypeConstraint.md).

```tyhp
<?tyhp

type ClockShape = object {
    public function now(): \DateTimeImmutable;
};

function formatNow(ClockShape $c): string {
    return $c->now()->format('c');
}
```

A source-alias factory for a shape returns `\Tyhp\Type::objectShape(...)`. Hints erase to `object`, or to a nominal conjunct from an intersection (`LoggerInterface & object { … }` → `LoggerInterface`). Recursive shapes that mention their own name are allowed (`type Node = object { public function parent(): ?Node; }`).

## Callable-shape aliases

A `type` alias whose right-hand side is `callable(…): R` names a callable shape. Use the alias in every type position. Values come from `fn`, `function`, first-class callables, or a matching `__invoke` object — `new Mapper` is illegal.

```tyhp
<?tyhp

type Predicate<T> = callable(T $value): bool;
type Mapper<T, U> = callable(T $in): U;

function allMatch<T>(array<T> $items, Predicate<T> $p): bool {
    foreach ($items as $item) {
        if (!$p($item)) {
            return false;
        }
    }
    return true;
}
```

Inline `callable(T $x): U` is also legal in every type position. Object shapes stay alias-only.

## Struct-shape aliases

A `type` alias whose right-hand side is `struct { … }` is a named struct. `new Point() with […]` constructs the array. Inline `struct { … }` is legal in type position.

```tyhp
<?tyhp

type Point = struct {
    float $x;
    float $y;
};

Point $p = new Point() with [x => 1.0, y => 2.0];
```

See [Structs](tyhp_0400_structs.md) and [Object Shapes and `__New<T>`](tyhp_3400_newTypeConstraint.md).

## Template String Types

Type aliases can name template (encaps) string types — double-quoted patterns in type position with `${T}` holes and quantifiers after `}` (`?`, `+`, `*`). They erase to `string`. The factory returns `\Tyhp\Type::string()`.

```tyhp
<?tyhp

type AnyString = "${string}*";
type ApiPath = "api/${string}/items";
type OptionalPrefix = "${string}?id";
```

## Class-Level Type Aliases

Type aliases can be declared inside a class body. Class-level type aliases support visibility modifiers (public, protected, private), controlling whether the alias is accessible outside the class. The factory is a static method on the owning class with that visibility.

```tyhp
<?tyhp

class UserService {
    public type UserIdType = int;
    protected type UserData = array<string, string>;
    private type InternalState = array<string, mixed>;

    private InternalState $state;

    public function findUser(self\UserIdType $id): ?User {
        return null;
    }

    public function idType(): \Tyhp\Type {
        return self::UserIdType();
    }
}

\Tyhp\Type $t = typeof(UserService\UserIdType);
\Tyhp\Type $also = UserService::UserIdType();
```

```php
<?php
declare(strict_types=1);

class UserService {
    private array $state;

    public static function UserIdType(): \Tyhp\Type
    {
        return \Tyhp\Type::int();
    }

    public function findUser(int $id): ?User {
        return null;
    }

    public function idType(): \Tyhp\Type {
        return self::UserIdType();
    }
}

$t = \UserService::UserIdType();
$also = \UserService::UserIdType();
```

Class-level aliases collide with methods of the same name — the static method *is* the factory. PHP has no `use function ClassName\method` for that; keep `use App\UserService;` as a class import when the class is referenced.

## Imports

Import a type alias with a plain `use`, the same as a class:

```tyhp
<?tyhp

use App\Types\UserId;
use App\Types\Optional;

function f(UserId $id): void { }

\Tyhp\Type $t = typeof(UserId);
Optional(typeof(int));
```

When emitted PHP references the factory by short name (`UserId()`, `typeof(UserId)`, `$x is UserId`, `default(UserId)`), that import becomes `use function App\Types\UserId;`. Hints-only usage still drops the import. A fully-qualified `\App\Types\UserId()` does not need `use`. Mixed groups split: `use App\Types\{ User, UserId }` emits `use App\Types\User;` plus `use function App\Types\UserId;` when the factory is used.

Same-namespace aliases need no import. Tyhp does not require a second `use function` in source — the class-kind import already binds `UserId()` as the factory.

## Self, Static, and Parent Scoping

Class-level type aliases can be referenced using `self`, `static`, and `parent`, just like class constants and methods. Prefer `self\Alias` (and `parent\Alias`) inside the class. From outside the class, `ClassName\Alias` is the type and `ClassName::Alias()` is the factory. PHP allows a class and a nested namespace to share a prefix (`class \App\Renderer` plus `\App\Renderer\AbstractRenderer`). In type position — including `is` / `instanceof` — `ClassName\Name` is the class-level alias when that member exists on the prefix class; otherwise it is the nested type. Inherited members still resolve from a parent declared under that shared prefix.

```tyhp
<?tyhp

class Base {
    public type IdType = int;

    public function getId(): self\IdType {
        return 1;
    }
}

class Child extends Base {
    public type IdType = string;

    public function getParentIdType(): parent\IdType {
        return 1;
    }

    public function getOwnIdType(): self\IdType {
        return 'abc';
    }
}
```

```php
<?php
declare(strict_types=1);

class Base {
    public static function IdType(): \Tyhp\Type
    {
        return \Tyhp\Type::int();
    }

    public function getId(): int {
        return 1;
    }
}

class Child extends Base {
    public static function IdType(): \Tyhp\Type
    {
        return \Tyhp\Type::string();
    }

    public function getParentIdType(): int {
        return 1;
    }

    public function getOwnIdType(): string {
        return 'abc';
    }
}
```

A helper that aliases `self` / `?self` emits `Type::fromClassName(self::class)` / `Type::nullable(...)`. `typeof(self\NameType)` emits `self::NameType()`. `typeof(C\NameType)` emits `C::NameType()`.

## `is`, `instanceof`, and `default`

`$x is UserId` expands the alias, then follows NativeTypeTest: `type UserId = string` emits `\is_string($x)` when `is_string` is marked. An unmarked alias still lowers to `\Tyhp\Type::is($x, UserId())` (including an alias of a class — never native `instanceof` of the underlying class). `$x is User` when `User` is a real class stays native `instanceof`. `default(UserId)` emits `UserId()->defaultValue()`; generic: `Optional(\Tyhp\Type::int())->defaultValue()`.

## Type Alias Expansion

The compiler resolves type aliases by recursively expanding them to their underlying types. Nested aliases (an alias that references another alias) are fully expanded for checking and hints. Circular aliases — where alias A references alias B which references alias A — are detected on source `.tyhp` declarations and produce a compile error (`TYHP3029`), except when every participant in the cycle is an object-shape alias (directly, or via a rename / generic instantiation of a shape).

```tyhp
<?tyhp

type StringOrNull = string|null;
type Name = StringOrNull;

// Circular alias — compile error
// type A = B;
// type B = A;  // Error: circular type alias

type Node = object {
    public function parent(): ?Node;
};
```

## Tyhpdef aliases

Aliases in `.tyhpdef` files are check-only unless they carry `#[\Tyhp\GenericRuntime(aliasFactory: …)]`. Overlay and harvested aliases inline in `typeof`. A compiled Tyhp library stamps `aliasFactory` when it emitted the factory; consumers then call `DecimalCoercible()` / `UserService::NameType()` rather than inlining. Hints still expand. Class and method `GenericRuntime` stamps are independent and do not require helpers.

## Traits and Interfaces Cannot Have Type Aliases

Type aliases are only allowed in class and enum declarations. Traits and interfaces cannot define type aliases because they represent contracts and mixins, not concrete type definitions.

```tyhp
<?tyhp

// ERROR — traits cannot have type aliases
// trait MyTrait {
//     type MyType = int;  // Compile error
// }

// ERROR — interfaces cannot have type aliases
// interface MyInterface {
//     type MyType = int;  // Compile error
// }

// OK — classes can have type aliases
class MyClass {
    public type MyType = int;
}

// OK — enums can have type aliases
enum Status {
    case Active;
    case Inactive;
    public type StatusOrNull = self|null;
}
```

## Error: Alias Referencing Undefined Type

The compiler reports an error if a type alias references a type that does not exist.

```tyhp
<?tyhp

// ERROR — UndefinedClass does not exist
// type MyAlias = UndefinedClass;  // Compile error: symbol not found
```

## Best Practices

:::tip
Use type aliases to give meaningful names to complex type expressions — this improves code readability. For example, type Callback = callable(string, int): bool is clearer than repeating the callable signature everywhere.
:::

:::tip
Use generic type aliases to create reusable type templates. For example, type Optional<T> = T|null provides a concise nullable wrapper. Spell a Type value as `typeof(Optional<int>)` or `Optional(typeof(int))`.
:::

:::tip
Use class-level type aliases with visibility modifiers to scope types to their owning class. Call the factory as `self::NameType()` or `UserService::NameType()`.
:::

:::tip
Use type aliases for domain-specific types (e.g., type UserId = int) to make code self-documenting. PHP interop names the same alias as `UserId()`.
:::

## Common Mistakes

:::danger
Don't define type aliases in traits or interfaces — they are not allowed and produce a compile error.
:::

:::danger
Don't create circular type aliases of non-shape types — the compiler detects and reports those as errors on source `.tyhp` declarations. Recursive object-shape aliases that mention their own name are allowed.
:::

:::danger
Don't write `Optional<int>()`. Type arguments belong in type position and inside `typeof(...)`. The factory takes `\Tyhp\Type` values: `Optional(typeof(int))` or, in PHP, `Optional(\Tyhp\Type::int())`.
:::

:::danger
Don't use type aliases when a simple union type inline would be clearer — aliases add indirection that may hurt readability for trivial cases.
:::
