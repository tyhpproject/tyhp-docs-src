---
title: Generics
status:
  tier: 0
  story: '08'
  state: complete
---

Tyhp adds generic type parameters to classes, interfaces, traits, enums, structs, functions, and methods. Generics provide compile-time type safety for reusable components. Type parameters are erased from PHP signatures. Tyhp generics support constraints via extends, default type parameters, and generic import aliases.

:::note
Generic type parameters, arguments, and constraints are erased from PHP signatures. A declaration that still needs those arguments at runtime is stamped `#[\Tyhp\GenericRuntime]`.

- An erased generic stays a plain method or a plain `new`, stamped `erased: true, layouts: [1]`.
- A non-erased method or function that is not `#[\Tyhp\InferGeneric]` is a binder under its declared name: `Json::decode($T)($json)`, stamped `layouts: [2]`. The binder is that name.
- `#[\Tyhp\InferGeneric]` keeps the value signature under the declared name and adds a `name__tyhpGeneric` companion stamped `layouts: [1]`. A call with explicit type arguments uses the companion. `\Tyhp\Generic::bind` binds layout 1 and layout 2 and takes `\Tyhp\TypeLike|string`.
- A generic class is stamped `layouts: [1]`. PHP calls `Box::new(T::int)(42)` and `Box::type(T::int)`. `new()` uses the constructor's visibility and is not `final`. A private constructor emits `private static function new`. Abstract classes get `type()` only. Interfaces and traits get neither.

PHP builtin and overlay tyhpdefs that omit the stamp stay erased. `#[\Tyhp\EraseGeneric]` opts a property, or every generic-typed property of a class, out of set checks.
:::

## Generic Classes

A class can declare one or more generic type parameters inside angle brackets after the class name. These type parameters can be used as types for properties, method parameters, and return types within the class.

```tyhp
<?tyhp

class Box<T> {
    private T $value;

    public function __construct(T $value): void {
        $this->value = $value;
    }

    public function getValue(): T {
        return $this->value;
    }
}

Box<int> $intBox = new Box<int>(42);
int $val = $intBox->getValue();  // Type-safe: returns int
```

When the expected type of a `new` expression is a unique instantiation of the same generic, the type-argument list may be omitted. `Box<int> $intBox = new Box(42);` and `function make(): Box<string> { return new Box("x"); }` infer `T` from the typed local / return type. Explicit arguments still win; a defaulted parameter still fills in when there is no unique expected instantiation.

## Compiled PHP Output

Generic type parameters are erased from PHP signatures. Unconstrained type parameters become `mixed`. Constrained type parameters use their constraint type as the PHP type hint.

A generic-typed **property** (including a promoted constructor property) opts the class into runtime tracking (Mechanism C: `HasGenerics`, factory, set checks) unless the property or class carries `#[\Tyhp\EraseGeneric]`. Runtime-use constructs (`typeof(T)`, `default(T)`, `is T`, `new T()`, forwarded type arguments) also force tracking. Mixed mode is allowed: the class stays tracked while opted-out properties skip set checks.

A tracked class is stamped `layouts: [1]` and keeps a generated factory. Same-compilation `new Box<int>(42)` calls that factory. The factory name is the class stamp's `factory` value; it is the layout-1 class factory, not the PHP call. PHP constructs and describes the class with `new()` and `type()`:

```php
<?php

use Tyhp\Type as T;

$intBox = \Vendor\Box::new(T::int)(42);
$boxType = \Vendor\Box::type(T::int);
```

`new()` returns a closure with the constructor's value signature. Its visibility matches the constructor: a private constructor emits `private static function new` without `final`. `type()` is public and returns `\Tyhp\Type`. A non-generic `IntBox extends Box<int>` inherits `Box::new`, and that closure builds an `IntBox`. A method named `new` or `type` on a generic class, or on an ancestor, is TYHP4406.

A Tyhp `new \Vendor\Box<int>(42)` of a class compiled in another library emits `\Tyhp\Generic::bind(\Vendor\Box::class, \Tyhp\Type::int())(42)`. `lazy new` of that class emits the same eager call. Defer it with `->ghost(42)`. See [Lazy Objects](tyhp_0152_lazyObjects.md). When the class name is chosen at runtime, PHP uses the same binder: `\Tyhp\Generic::bind($className, T::int)->new(42)`.

A non-erased method that is not `#[\Tyhp\InferGeneric]` is called types-first, under the declared name:

```php
$user = \Tyhp\Json::decode(T::struct([
    'id' => T::int,
    'name' => T::string,
]))($json);
```

`#[\Tyhp\InferGeneric]` is a plain call. Explicit type arguments use the `name__tyhpGeneric` companion (`layouts: [1]`). `\Tyhp\Generic::bind` on that callable binds the companion the same way, and it also binds a layout-2 method. An erased method, with or without the attribute, stays a plain call with no companion, `layouts: [1]`.

A first-class callable of a generic function (`identity(...)` or `identity<string>(...)`) keeps its type-binding identity, also when it needs [implicit conversions](tyhp_1600_operatorOverloads.md#conversions-on-first-class-callables) for a parameter. The compiler wraps it with `\Tyhp\Generic::wrapCallable`, and `\Tyhp\Generic::bind` on that value binds the type arguments while the conversions still apply.

PHP builtin and overlay generics that omit the stamp stay erased. Same-compilation erased classes emit a plain `new` or a plain call, still stamped `erased: true, layouts: [1]`.

A magic method cannot declare type parameters (TYHP4404). A generic method cannot override or implement a non-generic method (TYHP4405). `\Tyhp\Contracts\ArrayAccessShape::offsetGet` and `offsetSet` are not generic. `#[\Tyhp\InferGeneric]` on a type parameter no argument can supply is TYHP4407. A by-reference parameter such as `T &$out` is not a source, so `Json::tryDecode` is binder-first. The attribute on a declaration with no type parameters is warning TYHP4408.

`#[\Tyhp\EraseGeneric]` is compile-only (`#[\Tyhp\NoEmit]`). It is legal on a class, a property, or a promoted constructor parameter. On a method or function it is an error. The attribute is not inherited; a tracked child of an erased generic parent does not call `parent::__initGenerics__`.

### Declared property types at runtime

When a property's PHP type hint loses part of its Tyhp type (type arguments, a struct type, or a source type alias), the compiler adds `#[\Tyhp\PropertyType]` with the full type. Promoted constructor parameters get the same attribute.

```tyhp
<?tyhp
namespace App;

class Blog {
    public array<Post> $posts = [];
    public ?Table<Blog> $related = null;
    public function __construct(public array<string, int> $counts = []) {}
}
```

```php
// PHP output
class Blog
{
    #[\Tyhp\PropertyType('array<App\\Post>')]
    public array $posts = [];
    #[\Tyhp\PropertyType('?App\\Table<App\\Blog>')]
    public ?\App\Table $related = null;
    public function __construct(#[\Tyhp\PropertyType('array<string, int>')] public array $counts = []) {}
}
```

`\Tyhp\Type::fromProperty()` reads the declared type, and falls back to the reflected PHP type when there is no attribute:

```php
$posts = \Tyhp\Type::fromProperty(\App\Blog::class, 'posts');
(string)$posts;                    // 'array<App\Post>'
(string)$posts->elementType();     // 'App\Post'
\Tyhp\Type::fromProperty(\App\Blog::class, 'related')->typeArguments();   // [Type for App\Blog]
```

The spelling is the format `\Tyhp\Type::parse()` reads: class names are fully qualified, structs are `struct App\Address`, and source type aliases use their registered name. A property whose type mentions a type parameter of its class (`array<T>`) has no attribute. When `fromProperty()` is called on an object of a generic class, a `T`-typed property returns the type argument bound for that object. The compiler writes the attribute; one written in source is replaced.

## Generic Interfaces

Interfaces can declare generic type parameters. Classes that implement a generic interface must specify concrete type arguments, and the compiler validates that the implementing methods match the parameterized signatures.

```tyhp
<?tyhp

interface Repository<TEntity, TId> {
    public function find(TId $id): ?TEntity;
    public function save(TEntity $entity): void;
    public function delete(TId $id): void;
}

class UserRepository implements Repository<User, int> {
    public function find(int $id): ?User {
        // ...
    }

    public function save(User $entity): void {
        // ...
    }

    public function delete(int $id): void {
        // ...
    }
}
```

```php
<?php
// PHP output — generic arguments on implements are erased
declare(strict_types=1);

interface Repository {
    public function find(mixed $id): mixed;
    public function save(mixed $entity): void;
    public function delete(mixed $id): void;
}

class UserRepository implements Repository {
    public function find(int $id): ?User {
        // ...
    }

    public function save(User $entity): void {
        // ...
    }

    public function delete(int $id): void {
        // ...
    }
}
```

## Generic Traits

```tyhp
<?tyhp

trait Cacheable<T> {
    private ?T $cached = null;

    public function getCached(): ?T {
        return $this->cached;
    }

    public function setCached(T $value): void {
        $this->cached = $value;
    }
}

class UserService {
    use Cacheable<User>;
}
```

## Generic Enums

```tyhp
<?tyhp

enum Result<T> {
    case Ok;
    case Error;

    public function map<U>(callable(T): U $fn): Result<U> {
        // ...
    }
}
```

## Generic Functions and Methods

Standalone functions and class methods can declare their own generic type parameters. When calling a generic function, type arguments can be provided explicitly or inferred from the arguments. A literal argument infers the widened type, so `boxOf('plain')` where `boxOf<T>(T $x): Box<T>` is `Box<string>`. Elements of `array<Cell<T>>` or a variadic `Cell<T> ...` are merged, so a `Cell<int>` and a `Cell<string>` infer `T` as `int|string`. When the arguments do not determine a type parameter, the type expected at the call is used, then the parameter's default. If none of those apply, the call is an error and the type argument must be written explicitly.

```tyhp
<?tyhp

// Generic standalone function
function firstOrNull<T>(array<T> $items): ?T {
    return $items[0] ?? null;
}

// Type argument inferred from the array type
?string $first = firstOrNull(['a', 'b', 'c']);  // T inferred as string

// Explicit type argument
?int $val = firstOrNull<int>([1, 2, 3]);

// Generic method on a class
class Transformer {
    public function transform<TIn, TOut>(TIn $input, callable(TIn): TOut $fn): TOut {
        return $fn($input);
    }
}
```

```php
<?php
// PHP output — generic parameters and arguments are erased
declare(strict_types=1);

function firstOrNull(array $items): mixed {
    return $items[0] ?? null;
}

$first = firstOrNull(['a', 'b', 'c']);
$val = firstOrNull([1, 2, 3]);

class Transformer {
    public function transform(mixed $input, callable $fn): mixed {
        return $fn($input);
    }
}
```

## Constraints with extends

Type parameters can be constrained with the extends keyword. A constraint limits which types can be used as a type argument. The constraint can be a class, interface, or a union of types. When a type parameter has a constraint, the constraint type is used as the PHP type hint instead of mixed.

```tyhp
<?tyhp

// Single constraint
class SortedList<T extends Comparable> {
    public function add(T $item): void {
        // T is guaranteed to implement Comparable
    }
}

// Union constraint
function toNumber<T extends int|float|string>(T $value): float {
    return (float)$value;
}

// Multiple type parameters with constraints
class Mapper<TSource extends Entity, TTarget extends DTO> {
    public function map(TSource $source): TTarget {
        // ...
    }
}
```

```php
<?php
// PHP output — constrained generics use the constraint as the type hint
declare(strict_types=1);

class SortedList {
    public function add(Comparable $item): void {
        // ...
    }
}

function toNumber(int|float|string $value): float {
    return (float)$value;
}
```

## Generic Type Parameter Defaults

Generic type parameters can have default types, specified with = after the optional constraint. When a consumer does not provide a type argument for a defaulted parameter, the default is used. This enables cleaner APIs where the common case requires no explicit parameterization. Defaults are supported on classes, interfaces, traits, enums, type aliases, functions, and methods.

```tyhp
<?tyhp

// Promise defaults TReturn to mixed (runtime: tyhp/async)
class Promise<TReturn extends __Awaited<void|mixed> = __Awaited<mixed>> {
    // ...
}

Promise $p1 = new Promise();            // TReturn = mixed
Promise<void> $p2 = new Promise<void>();

// Override the default
Promise<int> $p3 = new Promise<int>();

// Multiple defaults — trailing parameters only
class MyMap<TKey = string, TValue = mixed> {
    // ...
}

MyMap $m1 = new MyMap();               // TKey = string, TValue = mixed
MyMap<int> $m2 = new MyMap<int>();      // TKey = int, TValue = mixed
MyMap<int, User> $m3 = new MyMap<int, User>();  // TKey = int, TValue = User

// Type alias with default
type Collection<T = mixed> = array<T>;

// Function with default
function wrap<T = string>(T $value): array<T> {
    return [$value];
}

// Interface with default
interface Repository<TEntity, TId = int> {
    public function find(TId $id): ?TEntity;
}
```

## Default Must Satisfy Constraint

When a type parameter has both a constraint and a default, the default type must satisfy the constraint. The compiler reports an error if the default type is not assignable to the constraint.

```tyhp
<?tyhp

// Valid — array implements Countable
class Counter<T extends Countable = array> {
    // ...
}

// ERROR: TYHP4310 — string does not implement Countable
// class BadCounter<T extends Countable = string> {
//     ...
// }
```

:::warning
Error TYHP4310 (CheckerGenericDefaultDoesNotSatisfyConstraint): "Default type 'string' does not satisfy constraint 'Countable' on generic parameter 'T'"
:::

## Trailing Rule for Defaults

Defaulted type parameters must be trailing — a non-defaulted parameter cannot follow a defaulted one. This mirrors PHP function parameter defaults and prevents ambiguity in partial type argument application.

```tyhp
<?tyhp

// Valid — non-defaulted parameters first, then defaulted
class Valid<T, U = int> {}
class AlsoValid<T, U = int, V = string> {}
class AllDefaults<T = mixed> {}

// ERROR: TYHP4311 — U has no default but follows T which has one
// class Invalid<T = int, U> {}
```

:::danger
Error TYHP4311 (CheckerGenericNonDefaultAfterDefault): "Generic parameter 'U' without a default cannot follow parameter 'T' which has a default"
:::

## Type Inference Priority Over Defaults

When calling a generic function or method, type inference from arguments always takes priority over defaults. Defaults are only used when a type parameter cannot be inferred and is not explicitly provided. The resolution order is: explicit type arguments first, then type inference from arguments, then defaults as a last resort.

```tyhp
<?tyhp

function wrap<T = string>(T $value): array<T> {
    return [$value];
}

wrap(42);         // T = int (inferred from argument, NOT string)
wrap('hello');    // T = string (inferred, coincidentally matches default)
wrap<bool>(true); // T = bool (explicit overrides everything)
```

:::note
Defaults primarily benefit class-level generics where there are no constructor arguments to infer from, or when a type parameter is not used in any parameter position.
:::

## Defaults Referencing Earlier Parameters

A default type can reference type parameters declared earlier in the same parameter list. This enables patterns where one parameter's default depends on another parameter's resolved type.

```tyhp
<?tyhp

// U defaults to T — Pair<int> is equivalent to Pair<int, int>
class Pair<T, U = T> {
    public T $first;
    public U $second;
}

Pair<int> $p = new Pair<int>();  // U = int (from T's value)
```

## Generic Extends and Implements

Generic arguments on extends and implements clauses provide compile-time type checking but are erased in PHP output.

```tyhp
<?tyhp

class StringCollection extends Collection<string> {
    // Inherits Collection's methods typed to string
}

class UserRepo implements Repository<User, int> {
    // Must implement Repository methods with User and int
}
```

```php
<?php
// PHP output — generic arguments on extends/implements are erased
declare(strict_types=1);

class StringCollection extends Collection {
}

class UserRepo implements Repository {
}
```

## Generic Import Aliases

You can create a use import alias with bound generic arguments. This creates a typed shortcut for a specific generic instantiation.

```tyhp
<?tyhp

use App\Collections\TypedList as IntList<int>;

IntList $numbers = new IntList();
$numbers->add(42);
```

## Constraint Violation Errors

The compiler reports an error when a type argument does not satisfy the constraint specified on the generic parameter.

```tyhp
<?tyhp

class SortedList<T extends Comparable> {
    public function add(T $item): void { }
}

// ERROR — int does not implement Comparable
// SortedList<int> $list = new SortedList<int>();

// OK — User implements Comparable
SortedList<User> $list = new SortedList<User>();
```

## Generic Types Without Type Arguments

A generic class written without type arguments, such as `Box` for `class Box<T>`, is the same type as `Box<mixed>` when it is the **source** of an assignment (a variable assignment, an argument, or a return) to an instantiation of the same class. Each type parameter widens to its declared `extends` bound, or to `mixed` when it has none. Members read through that raw receiver use the same widened types (`$raw->value` is `mixed` for an unbounded `T`, or `int|string` when `T extends int|string`). Inside the class, `$this` still sees the class's own type parameters. The result is one-directional:

- `Box` is **not** assignable to `Box<int>`, because its value could be anything.
- `Box<int>` is assignable to `Box`.
- `Box` is assignable to `Box<mixed>` and to `Box`.

```tyhp
<?tyhp

namespace App;

class Box<T> {
    public function __construct(public T $value) {}
}

function rawToMixed(Box $raw): Box<mixed> {
    return $raw;                 // OK
}

function instantiationToRaw(Box<int> $box): Box {
    return $box;                 // OK
}

function rawToInt(Box $raw): Box<int> {
    return $raw;                 // Error: Box is not assignable to Box<int>
}

function takesInt(Box<int> $box): void {}

function passRaw(Box $raw): void {
    takesInt($raw);              // Error: Box is not assignable to Box<int>
}
```

To get a `Box<int>`, construct one with the type argument (`new Box<int>(5)`) or let the constructor arguments infer it (`new Box(5)` in a `Box<int>` context).

A parameter with a bound widens to that bound instead of `mixed`. The bound applies wherever the class is declared: later in the same file, in another file, or in a PHP stub or tyhpdef. A bound that refers to the parameter itself, such as `T extends Node<T>`, is valid.

```tyhp
<?tyhp

namespace App;

class Counter<T extends int|string> {
    public function __construct(public T $value) {}
}

function rawToBound(Counter $raw): Counter<int|string> {
    return $raw;                 // OK: T widens to int|string
}

function rawToNarrower(Counter $raw): Counter<int> {
    return $raw;                 // Error
}

class Node<T extends Node<T>> {
    public ?T $next = null;
}

function keep(Node $n): Node {
    return $n;                   // OK
}
```

Two cases behave differently:

- A redundant `instanceof` check keeps the more precise type. After `$box instanceof Box` on a value declared `Box<int>|null`, the variable is still `Box<int>`. An `instanceof Box` check on a `mixed` value yields the raw `Box`, which is not assignable to `Box<int>`.
- A bare `\Closure` stays assignable to any `\Closure<…>` instantiation.

## Type Argument Count Errors

A type argument list must supply every type parameter that has no default. Supplying only some of them is an error (TYHP4036). Writing the class name with no argument list at all is the raw form described above.

```tyhp
<?tyhp

class Pair<T, U> {
    public T $first;
    public U $second;
}

// ERROR — Pair expects 2 type arguments, 1 provided
// Pair<int> $p = new Pair<int>();

// OK — all type arguments provided
Pair<int, string> $p = new Pair<int, string>();
```

## Best Practices

:::tip
Use generics to write reusable, type-safe classes, interfaces, and functions. Generics preserve type information through calls, unlike mixed.
:::

:::tip
Use constraints (extends) to limit type parameters to types that support the operations you need. This also produces better PHP type hints in the compiled output.
:::

:::tip
Use defaults on type parameters when there is a sensible common case (e.g., `Promise<TReturn extends __Awaited<void|mixed> = __Awaited<mixed>>`, where an omitted `TReturn` is `mixed`). This reduces boilerplate for callers.
:::

:::tip
Let the compiler infer type arguments when calling generic functions — explicit type arguments are often unnecessary. The compiler infers types from the arguments you pass.
:::

:::tip
Use meaningful generic parameter names: T for a single general type, TKey/TValue for key-value pairs, TEntity/TId for domain-specific parameters.
:::

## Common Mistakes

:::danger
Don't treat erased type parameters as a PHP runtime API — they are stripped from signatures. PHP calls a concrete generic class with `Box::new(T::int)(42)` and `Box::type(T::int)`, a layout-2 method with `name(types)(args)`, and an `#[\Tyhp\InferGeneric]` method as a plain call. `\Tyhp\Generic::bind` is for a class or callable chosen at runtime, and it also binds layout 1 and layout 2 when the type arguments are supplied from PHP. Same-compilation Tyhp `new` still calls the class factory; a layout-2 Tyhp call emits `name(types)(args)`.
:::

:::danger
Don't place a non-defaulted type parameter after a defaulted one — this produces error TYHP4311.
:::

:::danger
Don't specify a default type that does not satisfy the constraint — this produces error TYHP4310.
:::

:::danger
Don't over-use generics for types that are naturally a single concrete type — generics add complexity. Use them when genuine type parameterization is needed.
:::

:::danger
Don't create self-referencing defaults (e.g., <T = T>) — this is circular-reference error TYHP4312.
:::
