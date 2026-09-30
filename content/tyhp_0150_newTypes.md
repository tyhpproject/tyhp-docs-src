---
title: 'New and Changed Types in Tyhp'
status:
  tier: 0
  story: '04'
  state: complete
---

Tyhp introduces several new types and enhances existing PHP types with generic support. This page covers generic PHP types, new Tyhp-specific types, and internal compiler types. Built-in types are registered in the compiler; runtime types such as `\Tyhp\Type` and `Promise<T>` come from the `tyhp/core` and `tyhp/async` packages.

## Generic PHP Types

Tyhp adds generic type parameters to many built-in PHP types. The non-generic versions remain available for backward compatibility, but the generic versions are preferred for maximum type safety.

## The `array<TKey, TValue>` and `iterable<TKey, TValue>` Types

The `array` and `iterable` types from PHP now have additional generic signatures that allow for precise element type control.

:::member[array<TKey extends string|int, TValue>]
A typed array with 2 generic parameters. The first is the key type (must be `string`, `int`, or `string|int`), and the second is the value type.
:::

:::member[array<TValue>]
A typed array with 1 generic parameter (the value type). This is list shorthand for `array<int|string, TValue>` — keys are `int|string`, not int-only.
:::

:::member[array]
The non-generic version, equivalent to `array<int|string, mixed>`.
:::

:::member[iterable<TKey, TValue>]
A typed iterable with 2 generic parameters. `iterable` is a built-in type equivalent to `array|Traversable` (with matching generic arguments when given). It is not a type alias.
:::

:::member[iterable<TValue>]
Single-parameter version. Like `array<TValue>`, this is shorthand for `iterable<int|string, TValue>`.
:::

:::member[iterable]
The non-generic version, equivalent to `iterable<mixed, mixed>`.
:::

```tyhp
<?tyhp

array<string> $names = ["Alice", "Bob"];
array<string, int> $ages = ["Alice" => 30, "Bob" => 25];

function processItems(iterable<string> $items): void {
    foreach ($items as $item) {
        echo $item;
    }
}
```

## The `\Traversable<TKey, TValue>` Type

The `\Traversable` interface from PHP gains optional generic parameters for the key and value types.

:::member[\Traversable<TKey, TValue>]
A typed traversable with 2 generic parameters. The `iterable<TKey, TValue>` built-in is equivalent to `array<TKey, TValue>|\Traversable<TKey, TValue>`.
:::

`\Traversable` is an engine interface. Only `\Iterator` and `\IteratorAggregate` (in `tyhpdef/php`) may `extends \Traversable`. User classes, enums, interfaces, and traits must not list `\Traversable` in `implements` or `extends` — implement `\Iterator` or `\IteratorAggregate` instead (Traversable is inherited). Listing both (`implements \Iterator, \Traversable`) is **TYHP4326**. Harvested `.tyhpdef` stubs may still list both; the checker does not flag those shells.

## The `\Iterator<TKey, TValue>` Type

The `\Iterator` interface extends `\Traversable` and gains generic parameters. `current()` returns `TValue` and `key()` returns `TKey` instead of `mixed`.

:::member[\Iterator<TKey, TValue>]
A generic iterator where `current()` returns `TValue` and `key()` returns `TKey`. Extends `\Traversable<TKey, TValue>`.
:::

## The `\IteratorAggregate<TKey, TValue>` Type

The `\IteratorAggregate` interface extends `\Traversable` and gains generic parameters. The `getIterator()` method returns `\Traversable<TKey, TValue>`.

:::member[\IteratorAggregate<TKey, TValue>]
A generic iterable aggregate where `getIterator()` returns `\Traversable<TKey, TValue>`. Extends `\Traversable<TKey, TValue>`.
:::

## The `\ArrayAccess<TKey, TValue>` Type

The `\ArrayAccess` interface gains generic parameters for homogeneous array-like access: every offset has the same value type.

:::member[\ArrayAccess<TKey, TValue>]
`$obj[$k]` is `TValue` when `$k` is assignable to `TKey`. `$obj[$k] = $v` writes a `TValue`. `$obj[] = $v` is `offsetSet(null, $v)` (`null|TKey` on `offsetSet`). `isset` / `empty` / `unset` on offsets use `offsetExists` / `offsetUnset`. `list()` / `[]` destructure (positional and named keys) is the same `offsetGet` read as `$obj[$k]`: each bound key is `TValue` when the key is assignable to `TKey`. A receiver that is not an array, string, or `ArrayAccess` cannot be destructured (**TYHP4094**).
:::

`TKey` must be a legal PHP offset (`int`, `string`, `int|string`, or an object key such as `\WeakMap`). A struct or `array` as `TKey` is **TYHP4330** — structs erase to arrays, and PHP cannot use arrays as offsets. Per-key maps over a struct are [`ArrayAccessShape`](#the-tyhpcontractsarrayaccessshapetstruct-type), not `ArrayAccess<SomeStruct>`.

A receiver that is not an `array`, `string`, or `ArrayAccess` cannot be indexed (**TYHP4093**). `foreach` does not use ArrayAccess; it needs `\Traversable` / `\Iterator` / `\IteratorAggregate`.

PHP’s `ArrayAccess` methods are `mixed` (contravariant parameters). Implementors emit `offsetExists` / `offsetGet` / `offsetSet` / `offsetUnset` with PHP `mixed` parameters, and `offsetGet` with a PHP `mixed` return, as if `#[\Tyhp\PhpType('mixed')]` were present. Checker types stay `TKey` / `TValue`.

## The `\Tyhp\Contracts\ArrayAccessShape<TStruct>` Type

Per-key indexing over a struct schema. `$obj['host']` is that field’s type; `$obj['port']` can be a different type. Canonical source: `tyhp/core` (`\Tyhp\Contracts\ArrayAccessShape`).

:::member[\Tyhp\Contracts\ArrayAccessShape<TStruct extends struct>]
Extends `\ArrayAccess<__IndexKeys<TStruct>, __IndexValueTypes<TStruct>>`. `offsetGet` / `offsetSet` use a method generic `TKey extends __IndexKeys<T>` so the value type is `__IndexValueType<T, TKey>`.
:::

```tyhp
<?tyhp

type ConfigMap = struct {
    string $host = '';
    int $port = 0;
};

function read(\Tyhp\Contracts\ArrayAccessShape<ConfigMap> $o): string {
    return $o['host'];  // string
}

function hostOf(\Tyhp\Contracts\ArrayAccessShape<ConfigMap> $o): string {
    ['host' => $h] = $o;  // same type as $o['host']
    return $h;
}
```

A wide `string` / `int` / `mixed` key at the call site is **TYHP4331** — use a key literal or assert with `as` (`$o[$s as 'host']`). Append (`$obj[] =`) is **TYHP4332**. `offsetExists` on a schema key is `bool` (the map may be sparse).

For `offsetGet` / `offsetSet` bodies, when `TKey` is a finite literal union the checker instantiates once per key. A key is covered only by a reachable value `return` (`offsetGet`) or a typed write of `$value` (`offsetSet`). `throw` / `never` does not cover a key (**TYHP4333**). `match` is sufficient, not required. Infinite key types (`string`) get one envelope check against `__IndexValueTypes<T>`.

`TStruct` is invariant. A value typed only as `ArrayAccess<…>` is the homogeneous envelope (key union, value union). `#[\Tyhp\PhpType('mixed')]` on the interface members is inherited by implementors.

## The `\Closure<TCallableShape, TThis, TScope>` Type

`\Closure` is PHP’s closure **class**. It is generic over the callable shape plus bound `$this` and visibility scope. It is not a second `callable` spelling: argument and return types go on `callable(…): R`, then that shape is the first type argument of `\Closure`.

:::member[\Closure<TCallableShape extends callable, TThis extends __ClosureThis = __ClosureThis, TScope extends __ClosureScope<TThis> = __ClosureScope<TThis>>]
`TCallableShape` is the `__invoke` signature. `TThis` is the bound `$this` (`object|null`; default `__ClosureThis`). `TScope` is the stored visibility scope (an object type, a class-name string of that type or a parent, or `null`; default `__ClosureScope<TThis>`). Bare `\Closure` stays gradual. `\Closure<callable(int): string>` fills `TThis` / `TScope` from the defaults.
:::

Instances come from `function` / `fn` literals, first-class callables (`foo(...)`), or `\Closure::fromCallable` — generics are inferred. Do not write `new \Closure<…>()`.

```tyhp
<?tyhp

// Takes int, returns string
\Closure<callable(int): string> $parser;

callable(int): string $also = $parser;  // Closure is callable via __invoke

// Zero-parameter void callback
\Closure<callable(): void> $ping;
```

### `callable` vs `\Closure`

| Write | When |
|---|---|
| `callable` / `callable(TArgs …): TReturn` | Any invokable: closures, functions, methods, `__invoke` objects. |
| `\Closure` / `\Closure<callable(...)>` | A Closure **object** (`bind` / `bindTo` / `call` / `fromCallable`, or you need the class). |

Every Closure is callable. Not every callable is a Closure — wrap the rest with `fromCallable`. An invokable class is not a `\Closure`; `fromCallable` stores the `__invoke` arity intersection as `TCallableShape` and drops the class type. Untyped `callable` is not assignable to a parameterized `\Closure<…>`.

`TThis` and `TScope` are **invariant**. Callable variance applies to `TCallableShape` (and thus to assigning a Closure to `callable` / that facet). Optional parameters on `__invoke` still produce an intersection of arity facets on the object (see [Optional parameters](#optional-parameters-and-arity-facets)).

### Inference

| Producer | `TCallableShape` | `TThis` | `TScope` |
|---|---|---|---|
| `function` / `fn` literal | signature of the literal | enclosing `$this`, or `null` for `static fn` | enclosing class, or `null` |
| FCC `$obj->m(...)` | method signature | `typeof($obj)` | the method’s class |
| FCC `Foo::m(...)` | method signature | `null` | `Foo` |
| FCC `foo(...)` | function signature | `null` | `null` |
| `fromCallable($cb)` | inferred from `$cb` | `__CallableThis<typeof($cb)>` | `__CallableScope<typeof($cb)>` |

`fromCallable` copies `$this` and scope from **`$callback`**, not from the caller. If the checker can see that `$callback` is not callable from `__CurrentScope` (for example another class’s `private` method), that is a compile error.

### `bind` / `bindTo` / `call` and `'static'`

`'static'` on `bind` / `bindTo` means “keep the old stored `TScope`”. It is not a class-name string and must not appear as a Closure type argument (**TYHP4335**). Omitting `$newScope` is the same keep-old-scope overload. After `'static'` / omitted scope, `$newThis` must still be an instance of the leftover scope (**TYHP4334**). An explicit object `$newScope` requires `TNewThis` to be a subtype of that object’s type; a string `$newScope` must be `__SuperTypeName<TNewThis>` (an ancestor name).

`call($newThis, …)` is a temporary bind: `$newThis` must be a non-null object (`TNewThis extends object`) compatible the same way. Arrow functions, some first-class callables, and internal-class `$newThis` / `$newScope` cannot be rebound (**TYHP4336**). Gradual `TThis` (`object|null` / bare `\Closure`) does not prove a bind error.

### Generic shapes and `as`

Generic arguments are compile-time. Assert a specific Closure (or Fiber) shape with `as`, for example `$fn as \Closure<callable(int): string>`. `instanceof` / `is` test the PHP class (`\Closure` / `\Fiber`).

## The `\Generator<TKey, TValue, TSend, TReturn>` Type

A function that contains `yield` is a generator. The **declared** return type is what a **call** returns — a Generator object — not the value of `return` inside the body. That inner `return` is `TReturn`, available as `$g->getReturn()` after the generator is exhausted.

:::member[\Generator<TKey, TValue, TSend, TReturn>]
`TKey` is the yield key type, `TValue` is the yield value type, `TSend` is the type accepted by `send()` (the value of a `yield` **expression**), and `TReturn` is `getReturn()`.
:::

| Written return type | Checker |
|---|---|
| `\Generator` | Infer all four arguments from the body; callers see that inferred type |
| `\Generator<TKey, TValue>` | Pin key/value; infer `TSend` / `TReturn` (default `mixed` until the body fills them) |
| `\Generator<K, V, S, R>` | Fully explicit; the body must match |
| `iterable` / `\Iterator` / `\Traversable` (and generic forms) | Legal weaker export. Callers do not get `send` / `getReturn`. Inside the body, yield is still checked against an inferred Generator shape |

`function foo(): string { yield 1; }` is **TYHP4087**. Async functions must not return Generator.

**Body inference:** `TValue` is the union of `yield $v` / `yield $k => $v` values. `TKey` is the union of explicit keys; a key-less `yield $v` contributes `int`. `TReturn` is the union of `return $x` values, plus `null` if any path falls off without `return`. Unused `yield $v;` leaves `TSend` as `mixed`. A typed target (`int $x = yield`, or `foo(yield)` with `foo(int $x)`) constrains `TSend`. Several typed targets are **intersected**; an empty intersection is **TYHP4328**. Untyped `$x = yield` keeps `TSend` and `$x` as `mixed` — narrow before use.

`yield from $inner` must be iterable or a Generator (**TYHP4089**). Inner `TKey` / `TValue` merge; outer `TSend` must be a legal `send()` into the inner. The `yield from` expression is the inner `TReturn` (arrays and non-Generator Traversables evaluate to `null`).

## The `\Fiber<TResume, TCallableShape>` Type

`\Fiber` is generic over the resume protocol and the callback shape.

:::member[\Fiber<TResume = mixed, TCallableShape extends callable = callable>]
`TResume` types the argument of `$fiber->resume($value)` only. `TCallableShape` is the callback passed to `new Fiber`. `start(…)`, `throw(…)`, and `Fiber::suspend()` **return** `mixed|null`. `getReturn()` is `__CallableReturnType<TCallableShape>`. `Fiber::getCurrent()` is `?\Fiber<mixed, callable>`.
:::

`Fiber::suspend()` is static: it suspends whichever fiber is running, including helpers shared by many fibers. Its argument and return are `mixed` at every call site. Narrow from `mixed` before use. Assert a tighter Fiber shape with `as` (same rule as Closure).

## The `#[\Tyhp\PhpType]` Attribute

`#[\Tyhp\PhpType('mixed')]` (constructor argument: a PHP type-hint spelling) replaces the **emitted PHP type** of the declaration it sits on. Checker types are unchanged. Usages and the `PhpType` class itself are omitted from emitted PHP because the class is tagged `#[\Tyhp\NoEmit]`.

Legal sites: parameter (function, method, closure, property-hook `set`), function or method **return** (attribute on the function/method), property (including hooked and constructor-promoted), typed constant (class / interface / trait / enum). Constructor promotion: one attribute covers both the parameter and the property.

Implementing a method or property **inherits** `PhpType` from the interface or abstract member it satisfies.

Invalid spelling (`int[]`, `?mixed`, missing argument) is **TYHP4329**. Illegal targets — class / interface / trait / enum (including enum backing type), enum cases, catch types, local variables, property `get`/`set` hooks — are **TYHP4327**. Put the attribute on the property or on the `set` parameter instead of on the hook.

This is not `#[\Tyhp\Php(">=8.4")]` (that is a [PHP version gate](tyhp_0320_phpVersionGating.md)).

```tyhp
<?tyhp

#[\Tyhp\PhpType('mixed')]
function offsetGet(#[\Tyhp\PhpType('mixed')] string $offset): User {
    return $this->users[$offset];
}
```

The checker still sees `string` / `User`. The emitted PHP is `function offsetGet(mixed $offset): mixed`.

## The `\WeakReference<T>` Type

The `\WeakReference` class gains a generic parameter for the referenced object type. The `get()` method returns `?T` instead of `?object`.

:::member[\WeakReference<T>]
A weak reference to an object of type `T`. `get()` returns `?T`.
:::

## The `\WeakMap<TKey extends object, TValue>` Type

The `\WeakMap` class gains generic parameters for the key type (constrained to `object`) and value type.

:::member[\WeakMap<TKey extends object, TValue>]
A type-safe weak object-keyed map. Keys are weakly referenced and do not prevent garbage collection.
:::

## The `\UnitEnum` and `\BackedEnum<TValue>` Types

The `\UnitEnum` interface remains as-is. `\BackedEnum` gains a generic parameter `TValue extends string|int` for the backing value type. The `from()` and `tryFrom()` methods use `TValue` for their parameter and return types.

:::member[\BackedEnum<TValue extends string|int>]
A backed enum where `from(TValue): static` and `tryFrom(TValue): ?static` use the backing type parameter.
:::

Every enumeration is `\UnitEnum` without a written `implements`. A backed enumeration is also `\BackedEnum`. `cases()` resolves on every enum; backed enums also have `from()` / `tryFrom()`. User classes, interfaces, and traits must not list `\UnitEnum` or `\BackedEnum` in `implements` or `extends` (**TYHP4337**). User enums must not list those interfaces either, and must not redeclare `cases`, `from`, or `tryFrom` (**TYHP4338**). Only the engine `\BackedEnum` declaration may extend `\UnitEnum`. Harvested `.tyhpdef` stubs may still list `\UnitEnum` / `\BackedEnum`; the checker does not flag those shells.

## The `\SensitiveParameterValue<T>` Type

The `\SensitiveParameterValue` class gains a generic parameter `T` so `getValue()` returns `T` instead of `mixed`.

:::member[\SensitiveParameterValue<T>]
Wraps a sensitive parameter value. `getValue()` returns `T`.
:::

## Generic SPL Types

Many SPL (Standard PHP Library) classes and interfaces gain generic type parameters in Tyhp. The following is a comprehensive list of SPL types with generic support:

- `\OuterIterator<TKey, TValue>` -- extends `\Iterator<TKey, TValue>`
- `\RecursiveIterator<TKey, TValue>` -- extends `\Iterator<TKey, TValue>`
- `\SeekableIterator<TKey, TValue>` -- extends `\Iterator<TKey, TValue>`
- `\SplObserver<TSubject>` -- typed observer pattern
- `\SplSubject<TObserver>` -- typed subject pattern
- `\SplDoublyLinkedList<TValue>` -- typed doubly linked list
- `\SplStack<TValue>` -- extends `\SplDoublyLinkedList<TValue>`
- `\SplQueue<TValue>` -- extends `\SplDoublyLinkedList<TValue>`
- `\SplHeap<TValue>` -- typed heap
- `\SplMaxHeap<TValue>` -- extends `\SplHeap<TValue>`
- `\SplMinHeap<TValue>` -- extends `\SplHeap<TValue>`
- `\SplPriorityQueue<TValue, TPriority>` -- typed priority queue
- `\SplFixedArray<TValue>` -- typed fixed-size array
- `\ArrayObject<TKey, TValue>` -- typed array object wrapper
- `\SplObjectStorage<TObject extends object, TInfo>` -- typed object storage
- `\IteratorIterator<TKey, TValue>` -- extends `\OuterIterator<TKey, TValue>`
- `\AppendIterator<TKey, TValue>` -- extends `\IteratorIterator<TKey, TValue>`
- `\ArrayIterator<TKey, TValue>` -- extends `\SeekableIterator<TKey, TValue>`
- `\CachingIterator<TKey, TValue>` -- extends `\IteratorIterator<TKey, TValue>`
- `\FilterIterator<TKey, TValue>` -- extends `\IteratorIterator<TKey, TValue>`
- `\CallbackFilterIterator<TKey, TValue>` -- extends `\FilterIterator<TKey, TValue>`
- `\InfiniteIterator<TKey, TValue>` -- extends `\IteratorIterator<TKey, TValue>`
- `\LimitIterator<TKey, TValue>` -- extends `\IteratorIterator<TKey, TValue>`
- `\NoRewindIterator<TKey, TValue>` -- extends `\IteratorIterator<TKey, TValue>`
- `\RegexIterator<TKey, TValue>` -- extends `\FilterIterator<TKey, TValue>`
- All `Recursive*` variants of the above iterators also gain the same generic parameters

## The `callable(…): R` Type

Bare `callable` is “invokable, signature unknown.” A **callable shape** adds a PHP-style parameter list and a return type. Names are optional. `=` marks a parameter as optional; a written default expression is parsed and discarded, so `bool $b = false` and `bool $b =` are the same shape.

```tyhp
<?tyhp

callable(string $s): int $parser;
callable(int, int): bool $comparator;
callable(): void $callback;
callable(int $i, bool $b =): string $greet;

function apply<T, U>(callable(T $item): U $fn, T $value): U {
    return $fn($value);
}
```

A shape is assignable to bare `callable`. Bare `callable` and `mixed` are not assignable to a shape without a guard or a tyhpdef assertion. Parentheses group a function type as an arm of `|` / `&`. Prefix `?` binds to the whole shape; `?` on the return binds inside:

```tyhp
<?tyhp

(callable(int $x): int) | null $maybe;
?callable(int $x): string $orNull;   // null | (int → string)
callable(int $x): ?string $nullRet;  // int → string|null
```

:::note
The `void` and `never` types are restricted types -- they cannot be used as generic type arguments unless the generic parameter's constraint explicitly allows them. The `callable` type's return parameter uses `TReturn extends void|never|mixed`, which opts in to both restricted types, making `callable(): void` and `callable(): never` valid.
:::

### Optional parameters and arity facets

Trailing parameters with default values expand into an **intersection of arity siblings** (not a subtype chain). The same model applies to a Closure’s `__invoke` facet (`TCallableShape`), not to `\Closure`’s class type arguments.

```tyhp
<?tyhp

// Inferred type: (callable(string, int): void) & (callable(string): void)
function greet(string $name, int $times = 1): void { ... }

callable(string): void $oneArg = greet(...);           // OK
callable(string, int): void $twoArg = greet(...);      // OK

// Explicit intersection is also allowed (prefer a type alias so each callable's
// generics close before `&`):
type Greeter = (callable(string, int): void) & (callable(string): void);
Greeter $either;
```

Each facet is an independent arity: `callable(string, int): void` does **not** imply `callable(string): void` by itself — only the intersection (or a value inferred with defaults) is assignable to both. A one-argument `callable(int): bool` is not assignable to the zero-argument facet `callable(): bool`. A function whose parameters all have defaults still assigns to `callable(): bool`, because inference includes a zero-argument arity sibling.

A trailing variadic never produces infinite facets. `function joinAll(string ...$parts): void` is typed `(callable(): void) & (callable(string): void)` — the prefix facets plus one that accepts a single variadic argument. Calls with more arguments than any facet are left unchecked rather than rejected.

### Any-arity `callable(...): TReturn`

`callable(...): TReturn` pins the return type without pinning the parameter list. The ellipsis is the **only** thing in the parameter list — a wildcard arity, not a rest parameter.

It is a generic bound, not a value type. Constrain a type parameter and take that parameter:

```tyhp
<?tyhp

function pin<TCallable extends callable(...): bool>(TCallable $callback): void {}

function demo(): void {
    pin(fn(int $n): bool => true);
    pin(fn(string $s, int $n): bool => true);
}
```

Do not write `callable(...): bool $callback` as a parameter, property, or return type, and do not call a value of that type. A concrete `callable(int): bool` or `callable(string, int): bool` is assignable to the bound when the return type is assignable to `bool`. The any-arity bound is not assignable to a known-arity facet such as `callable(): bool` or `callable(int): bool`.

`callable(): bool` remains a zero-parameter callable that returns bool. `callable(...): bool` is a different type.

### Parameter packs in callable shapes

A **pack** is an ordered list of types, not a union and not `array`. `__CallableParametersRest<TCallable>` is a pack of that callable’s parameters. Inside a callable-shape parameter list, a pack **splices** into ordinary parameters — no extra punctuation:

```tyhp
<?tyhp

// Pack = [int, string]
callable(__CallableParametersRest<callable(int, string): bool> ...): mixed
    // same shape as callable(int, string): mixed

callable(string, __CallableParametersRest<callable(int): bool> ...): mixed
    // callable(string, int): mixed

callable(__Nullable<__CallableParametersRest<callable(int, string): mixed>> ...): mixed
    // callable(?int, ?string): mixed
```

`__Nullable<int>` stays `int|null`. `__Nullable` on a pack maps each member (`?P0, ?P1, …`). `__NonNullable` maps a pack by stripping `null` from each member.

Value position is unchanged: `Rest<T> ...$args` unpacks at the call. `Rest<T> $x` (non-variadic) stays one wrapper.

Postfix `...` on a pack is an error (`callable(Rest<T> ...): R`). Packs splice automatically. Prefix `...Pack` is also an error.

### Trailing `T...` (PHP variadic)

`callable(P1, …, Pk, T ...): R` is a trailing PHP variadic: prefix parameters, then `T ...$values`, then return. Homogeneous `T ...` is only valid as the **last parameter** on a callable shape.

```tyhp
<?tyhp

// Exact: function (int $num, bool $flag, string ...$values): int
callable(int, bool, string ...): int $join;

$join(1, true, 'a', 'b');
```

Exact `callable(string ...): int` is a PHP variadic. A non-variadic `fn(string $a, string $b): int` is not that type.

As an **`extends` bound**, `TCallable extends callable(int ...): TReturn`:

- When this function does not feed Rest/Slice arguments into `TCallable`, the callback **must** be a PHP variadic whose last parameter accepts `int` (contravariance). Extra required parameters after the prefix are rejected.
- When Rest or Slice supplies a concrete argument list, `TCallable` must be invocable with that list (fixed arity matching N, trailing defaults, or a trailing variadic).

`callable(mixed ...): R` is not the any-arity wildcard: every used slot must accept `mixed`. Keep `callable(...): R` for unknown arity.

Reject `callable(): int...` (missing return), `callable(string ..., int): bool` (`...` not last before return), and postfix `...` on `array<>`, `\Closure<>`, or user generics.

### `__CallableParametersSlice`

```text
__CallableParametersSlice<TCallable extends callable, TStart extends int = 0, TMin extends int = 0>
```

`TStart` / `TMin` are non-negative int literal types.

| Use | Meaning |
|---|---|
| Non-variadic `Slice<T, 0> $x` | Exactly parameter `TStart`. `TMin` must not be written. |
| Variadic `Slice<T, 1> ...$xs` | Parameters from `TStart`, length = number of arguments passed, `N ≥ TMin` (default `0`). |
| `array<Slice<T, 0>> $a` | An array of `P_0`. |

Rest is Slice-from-0 as a single `...$args` covering the remainder. Same-function slices of one `TCallable` must be disjoint, ordered by `TStart`, with at most one open rest and no holes in required parameters (`TYHP4189` overlap, `TYHP4190` hole, `TYHP4191` `TMin` on a fixed slice).

Zip padding (`array_map` with two or more arrays) invents `null` at the call. Slice does not imply `?P_i`. The nullable callback view is a spliced pack:

```tyhp
<?tyhp

function array_map<TZip extends callable>(
    callable(__Nullable<__CallableParametersRest<TZip>> ...): __CallableReturnType<TZip> $callback,
    array<__CallableParametersSlice<TZip, 0>> $array,
    array<__CallableParametersSlice<TZip, 1, 1>> ...$arrays
): array<int, __CallableReturnType<TZip>>;
```

`TZip` is the non-null schema (array element types), not the callback’s type. `__Nullable<Rest<TZip>>` splices to `?P0, ?P1, …`. Extra arrays use `TMin = 1` so a one-array call stays on the key-preserving overload.

## New Tyhp-Specific Types

## The `decimal` Type

Tyhp introduces a `decimal` type for precise arithmetic calculations. In the compiled PHP, a `decimal` value is an instance of the `\Tyhp\Decimal` wrapper class that handles all arithmetic operations using bcmath, gmp, or a pure-PHP fallback (configurable in `tyhp.json`). There is no `19.99d` suffix. Construct decimals with `\Tyhp\decimal('19.99')` or `new \Tyhp\Decimal(...)`.

```tyhp
<?tyhp

decimal $price = \Tyhp\decimal('19.99');
decimal $tax = \Tyhp\decimal('2.00');
decimal $total = $price + $tax;  // Precise arithmetic

class Invoice {
    public decimal $amount;
    public decimal $taxRate;

    public function calculateTotal(): decimal {
        return $this->amount * (\Tyhp\decimal('1') + $this->taxRate);
    }
}
```

The `decimal` type supports all standard arithmetic operators (`+`, `-`, `*`, `/`, `%`, `**`), comparison operators (`==`, `<`, `>`, `<=`, `>=`, `<=>`), unary negation (`-$val`), and casts to `int`, `float`, and `string`. These compile to static method calls on `\Tyhp\Decimal` (for example `\Tyhp\Decimal::__add($a, $b)`).

## The `(decimal)` Cast

Tyhp provides a `(decimal)` cast operator for converting values to the `decimal` type, similar to PHP's built-in casts like `(int)` and `(float)`.

```tyhp
<?tyhp

float $price = 19.99;
decimal $precisePrice = (decimal) $price;

string $amount = "99.95";
decimal $parsed = (decimal) $amount;
```

## Compiled PHP Output for `decimal`

The `decimal` type compiles to `\Tyhp\Decimal` instances. Arithmetic operations become static method calls:

```tyhp
<?tyhp

decimal $a = \Tyhp\decimal('10.5');
decimal $b = \Tyhp\decimal('3.2');
decimal $result = $a + $b;
```

Compiles to:

```php
<?php
declare(strict_types=1);

$a = \Tyhp\decimal('10.5');
$b = \Tyhp\decimal('3.2');
$result = \Tyhp\Decimal::__add($a, $b);
```

## The `struct` Base Type

The `struct` base type is the parent of every struct shape: named aliases (`type Point = struct { … };`) and inline `struct { … }` in type position. At the PHP level a struct compiles to an associative `array`, with typed properties, schema-based typing, and value-type semantics. See the Structs documentation page for aliases, inline types, and the `with` keyword.

## The `void` Type

The `void` type in Tyhp is treated as a first-class keyword with its own lexer token (`T_TYHP_VOID`). It can be used in more type expression contexts than in PHP, including in type alias definitions, generic type arguments (where the generic parameter opts in via its constraint), and as part of callable/closure return types.

## The `never` Type

The `never` type from PHP is retained in Tyhp with the same semantics: it indicates that a function never returns (it always throws, calls `exit()`, or enters an infinite loop). Like `void`, it is a restricted type that can only appear as a generic type argument when the constraint explicitly allows it.

## The `mixed` Type

The `mixed` type from PHP is available in Tyhp but is discouraged. Prefer specific types or union types instead. There is no compiler setting that disallows `mixed`. See the dedicated Mixed Type documentation page for more details.

## Template String Types

Tyhp supports template (encaps) string types in type position: a double-quoted pattern with `${T}` holes and optional quantifiers right after `}` (`?` = 0–1, `+` = 1+, `*` = 0+). Examples: `"${string}*"`, `"api/${string}/items"`. They erase to `string`. See Type Aliases for a short usage note.

## The `self` / `static` / `parent` Relative Class Types

Tyhp supports relative class types with and without generic type arguments. The rules differ for
bare vs parameterized forms, and for instance vs static methods.

### Bare `self` / bare `static` (no type-argument list)

| Context | Bare `self` | Bare `static` |
|--------|-------------|---------------|
| Instance method | Declaring class with **this receiver’s** type args | Late-bound class of `$this`, with **that** instance’s type args (polymorphic “same as `$this`”) |
| Static method | Declaring class — under-specified args follow the bare-class-name rule | Class of the **call-site receiver** (`Child` in `Child::foo()` / `Child<string>::foo()`), with that reference’s type args |

Bare forms **inherit** receiver / call-site type arguments. They do **not** mean “fill class
defaults.” Defaults apply only when the class reference is under-specified the same way a bare
`Foo` / `Foo::` would elsewhere: if every omitted parameter has a default, apply them; otherwise
error. Inside the open generic’s own body, `$this` / bare `self` stay in terms of the class’s own
parameters (do not silently default to `mixed`).

### Parameterized `self<…>` / `parent<…>`

Allowed — explicit instantiation of a declaration whose arity is known at the spelling site:

```tyhp
<?tyhp

class Collection<T> {
    public function merge(self<T> $other): self<T> {
        // self<T> refers to Collection<T> with the written generic args
        // ...
    }
}

class TypedList<T> extends Collection<T> {
    public function concat(parent<T> $other): self<T> {
        // parent<T> refers to Collection<T>
        // ...
    }
}
```

### Parameterized `static<…>` — forbidden

`static<…>` is **not allowed** in any scope (including `final` classes). Late-static binding must
not invent or rebind type arguments. Prefer bare `static`, or explicit `DeclaringClass<…>` /
`self<…>` / `parent<…>` when an instantiation must be written. The checker reports
**TYHP4168** (`CheckerParameterizedStaticForbidden`).

### Factories that stamp a method generic onto the class

Use `: self<T>` or the declaring class name (`: Promise<T>`), **not** `: static<T>`:

```tyhp
<?tyhp

final class Promise<TReturn extends void|mixed = mixed> {
    public static function _async<T extends void|mixed>(callable(): T $fn): self<T> {
        return new self<T>($fn);
    }
}
```

On a `final` class, bare `self` and bare `static` remain interchangeable for *non-parameterized*
returns; parameterized returns use `self<…>` or the class name.

### Fluent inheritance

A non-generic parent may return bare `static` without knowing whether a child is generic. Call
sites with `GenericBuilder<int> $b` get `GenericBuilder<int>` back from inherited fluent methods —
parent declaration sites never name the child’s type parameters:

```tyhp
<?tyhp

class Builder {
    public function tap(): static {
        return $this;
    }
}

class GenericBuilder<T> extends Builder {
    public function __construct(public T $value): void {}
}

function demo(GenericBuilder<int> $b): GenericBuilder<int> {
    return $b->tap();
}
```

### `static` as a checked type (return / assignability)

Bare `static` is a first-class late-bound type. A value is valid where `static` is expected only
when it is **verifiably** that late-bound type, for example:

- `return $this;` (instance methods — `$this` is typed as `static`)
- the result of another call whose return type is (or resolves to) `static`
- a generic method/function / member whose substituted return type is `static`
- a value narrowed by `if ($var instanceof static) { … }` (or equivalent guards targeting `static`)

Ordinary `self` / declaring-class instances (including `new self()`) are **not** assignable to
`static` without such a proof. At call sites, a `: static` return expands to the receiver /
call-site class reference (including its type arguments).

## The `Promise<T>` Type

Tyhp provides a `Promise<T>` type for async/await support. The `Promise` class is defined as `Promise<TReturn extends void|mixed = mixed>` where `TReturn` is the fulfillment value type (default `mixed`). The constraint allows `Promise<void>` for async functions that do not return a value. A bare `Promise` is `Promise<mixed>`, not `Promise<void>`.

```tyhp
<?tyhp

// An async function returns a Promise
async function fetchUser(int $id): User {
    // The actual return type is Promise<User>
    $response = await \httpGet("/users/{$id}");
    return User::fromJson($response);
}

// Using the promise
Promise<User> $userPromise = fetchUser(42);
User $user = await $userPromise;
```

Key `Promise` methods include static combinators (`all<T>`, `race<T>`, `resolved<T>`, `rejected<T>`, `delay`, `timeout<T>`, `batch<TItem, TResult>`, `run<T>`), instance methods (`then<TResult>`, `catch<TResult>`, `finally`), and the internal `_async`/`_await` methods that the `async`/`await` keywords desugar to. `async { ... }` is a block expression that evaluates to `Promise<T>` (not a callable). See the Async/Await documentation for full details.

## Internal Compiler Types

The following types are part of Tyhp's internal type system. They are used by the compiler for type checking and type manipulation. Most are prefixed with `__` to indicate they are internal.

## The `__TyhpInternal<TType>` Type

The foundational internal wrapper type. A variable with a `__TyhpInternal<T>` type resolves to `T` but cannot be directly assigned by the developer. It can only be set via the return value of a function/method or via a type guard. Nearly all `__`-prefixed types are defined in terms of `__TyhpInternal<>`.

## Symbol Name Types

These types represent string values that the compiler knows refer to specific symbols in scope. They enable Tyhp's type-safe dynamic language features. Each is obtained by using the corresponding type guard function (e.g., `\class_exists()` narrows a string to `__ClassName`).

:::member[__VarName]
A `string` representing a variable name valid in the current scope. Obtained via `variable_exists($count)` or `variable_exists('count')` — the argument is the variable itself or a string literal. Alias for `__TypedVarName<mixed>`. (`$$var` is prohibited: TYHP4133.)
:::

:::member[__TypedVarName<T>]
Like `__VarName` but the compiler also knows the type of the referenced variable. If the string value can be resolved at compile time, the generic parameter `T` is the variable's declared type.
:::

:::member[__FunctionName]
A `string` representing a function name in scope. Obtained via `\function_exists()` as a type guard.
:::

:::member[__ClassName]
A `string` representing a class name in scope. Obtained via `\class_exists()` as a type guard.
Bare `__ClassName` is equivalent to `__ClassName<object>`; `\class_exists<T>($n)` narrows to `__ClassName<T>`.
Parametric `__ClassName<T>` is invariant in `T` when `T` is a nominal class (exact class name). When `T` is an object-shape alias, `__ClassName<Shape>` is a string naming some class whose instances match `Shape` (not an exact-name brand). `__ClassName<__New<Shape>>` names a concrete, public-`new`-able class matching that shape; `new $cls(...)` is allowed with the shape’s constructor arguments. See [Object Shapes and `__New<T>`](tyhp_3400_newTypeConstraint.md).
For "name of `T` or a descendant", use `__CompatibleTypeName<T>`. For "name of `T` or a parent", use `__SuperTypeName<T>`.
:::

:::member[__InterfaceName]
A `string` representing an interface name in scope. Obtained via `\interface_exists()` as a type guard.
Bare form ≡ `__InterfaceName<object>`; parametric form mirrors `__ClassName<T>`.
:::

:::member[__EnumName]
A `string` representing an enum name in scope. Obtained via `\enum_exists()` as a type guard. Alias of `__ClassName`.
Bare form ≡ `__EnumName<object>`.
:::

:::member[__TraitName]
A `string` representing a trait name in scope. Obtained via `\trait_exists()` as a type guard.
Bare form ≡ `__TraitName<object>`.
:::

:::member[__StructName]
A `string` representing the name of a struct type in scope.
:::

:::member[__UsedTraitName<T>]
A `__TraitName` that is specifically a trait used by the class or enum specified by `T`.
:::

:::member[__CompatibleTypeName<T>]
A class, enum, or interface name that is compatible with (same as or descendant of) `T`. Used with the `is` / `instanceof` keyword and with `\is_subclass_of()`.
Accepts string literals naming a subtype of `T`, and branded `__ClassName<S>` / `__EnumName<S>` / `__InterfaceName<S>` / `__CompatibleTypeName<S>` when `S` is the same as or a subtype of `T`. The ancestor counterpart is `__SuperTypeName<T>`.
:::

:::member[__SuperType<T>]
The object type `T` together with every parent class of `T`. Resolves to a union of those object types. When `T` is `object` or `null`, the result is `object`.
:::

:::member[__SuperTypeName<T>]
Class-name strings of `T` and its parent classes, branded like `__ClassName`. Inverse of `__CompatibleTypeName<T>` (which names descendants). When `T` is `object` or `null`, the result is `__ClassName`. Erases to `string`.
:::

:::member[__CurrentScope]
The lexical enclosing class or enum at the use site. Inside an instance method and inside a static method this is that class or enum type. At top-level (no enclosing type) this is `null`. Erases to `?object`.
:::

:::member[__PropertyName<T>]
A `string` representing a property name on the type `T`. Obtained via `\property_exists()` as a type guard.
:::

:::member[__MethodName<T>]
A `string` representing a method name on the type `T`. Obtained via `\method_exists()` as a type guard.
:::

:::member[__ConstName]
A `string` representing a constant name in scope.
:::

:::member[__ObjectConstName<T>]
A constant name scoped to a specific class or enum `T`.
:::

:::member[__EnumCaseName<T>]
The name of a specific enum case on the given enum `T`. Extends `__ObjectConstName`.
:::

## Type Name String Types

These types represent string representations of types themselves, used for dynamic type reflection and compile-time type manipulation.

:::member[__BaseTypeName]
A string literal union of all single type names: `'int'`, `'float'`, `'bool'`, `'array'`, `'string'`, `'null'`, `'mixed'`, `'self'`, `'parent'`, `'static'`, `'callable'`, `'iterable'`, `'object'`, plus `__StructName`, `__ClassName`, `__EnumName`, and `__InterfaceName`.
:::

:::member[__NullableBaseTypeName]
A nullable type name string, like `'?int'` or `'?MyClass'`. Defined as a `?`-prefixed `__BaseTypeName`.
:::

:::member[__UnionTypeName]
A full union type string like `'int|string|null'`. Built from `__BaseTypeName` segments joined by `|`.
:::

:::member[__IntersectTypeName]
A full intersection type string like `'MyClass&MyInterface'`. Built from base type segments joined by `&`.
:::

:::member[__NotNullableTypeName]
Any type name string (base, union, or intersection) that is guaranteed not to be nullable.
:::

:::member[__TypeName]
The universal type name string type. Can represent any type expressed as a string: base, nullable, union, intersection, or non-nullable variants.
:::

:::member[__NonMatchingStringType]
A special string type with a constant value that is un-matchable except to itself. Acts as a bottom/never-matching string type, used as a fallback in type computations.
:::

## Struct Utility Types

These types provide compile-time operations on struct types.

:::member[__StructRecord<TStructType, TKey>]
Represents a single record (key-value pair) within a struct type.
:::

:::member[__StructRecords<TStructType, TValueType>]
Represents the collection of all records in a struct as an array of `__StructRecord`.
:::

:::member[__StructDef<TRecordSet>]
Defines a struct type from its record set. Used for programmatic struct type construction.
:::

:::member[__StructPartial<TStructType, TIncludeKeys, TExcludeKeys>]
Represents a subset of a struct by including or excluding specific keys. If `TIncludeKeys` is null, `TExcludeKeys` is used for exclusion (and vice versa). Both null produces an empty struct.
:::

:::member[__StructKey<TStructType>]
The key type (property name type) of a struct's records.
:::

:::member[__IndexKeys<T>]
Union of struct `T`'s PHP array keys as literal types: each property name and each `as` alias (quoted string or integer). Used as the key type of per-key maps over a struct. Erases to `string`, `int`, or `string | int`.
:::

:::member[__IndexValueType<T, K>]
The field type of struct `T` at key `K`. Distributes over a union `K`, so `__IndexValueType<T, 'a' | 'b'>` is the union of those two field types. Erases to `mixed`.
:::

:::member[__IndexValueTypes<T>]
Union of every field type of struct `T`. Used as the value envelope when indexing `T` without a specific key. Erases to `mixed`.
:::

## Type Utility Types

These types provide compile-time type manipulation capabilities, similar to utility types in TypeScript.

:::member[__Partial<T>]
Object/struct patch type: every property becomes optional and nullable. Distinct from `__StructPartial`, which selects keys of a struct.
:::

:::member[__Required<T>]
Inverse of `__Partial<T>`: every property is required and non-nullable.
:::

:::member[__Pick<T, K>]
Keeps only the properties of `T` named in string-literal union `K`.
:::

:::member[__Omit<T, K>]
Drops the properties of `T` named in string-literal union `K`.
:::

:::member[__Record<K, V>]
Equivalent to `array<K, V>`. Distinct from `__StructRecord`, which is a struct-key carrier.
:::

:::member[__Exclude<T, U>]
Removes members of union `T` that are assignable to `U`.
:::

:::member[__Extract<T, U>]
Keeps only members of union `T` that are assignable to `U`.
:::

:::member[__Awaited<T>]
Recursively unwraps `Promise<T>` (and nested promises) to the resolved type.
:::

:::member[__New<T>]
Constructability constraint on an object-shape alias `T`. Values are instances that match `T` whose class is concrete and public-`new`-able as the shape’s `__construct` (or the PHP default zero-argument constructor when the shape has no `__construct`). `T` must be an object-shape alias. `new T(...)` is allowed when a type parameter is bounded by `__New<Shape>`. Erases like the shape (`object`, or nominal conjuncts from an intersection). See [Object Shapes and `__New<T>`](tyhp_3400_newTypeConstraint.md).
:::

:::member[__Properties<T>]
A synthetic struct whose keys are the instance property names of object type `T`, or the record keys of struct type `T`, and whose values are those members’ types. Every member is optional (same as a struct field with a default), so `[]` is a valid value and a literal may supply any subset of keys. Extra keys and value-type mismatches are errors. `T` must be an object type (class, interface, struct, or a type parameter bounded by `object`). Erases to `array`. An unbound type parameter stays deferred until it is inferred at a call site (for example `clone($object, $withProperties)`).
:::

:::member[__FunctionReturnType<T>]
Extracts the return type of a function given its name string. When harvest wrote a generated object-shape alias for a `return new class { … }` site, this utility recovers that shape.
:::

:::member[__MethodReturnType<T, M>]
Extracts the return type of a method given the owning type `T` and method name string `M`.
:::

:::member[__CallableReturnType<TCallable>]
Extracts the return type of a callable type `TCallable` — a `callable(...)` / `\Closure<…>` facet, a first-class function or method, or a type parameter inferred from a callback argument. Complements `__FunctionReturnType` / `__MethodReturnType`, which key off name strings rather than the callable type. Erases to that return type, or to `mixed` while `TCallable` is still unbound.
:::

:::member[__CallableParametersStruct<TCallable>]
Named-argument bag for a callable type `TCallable`. Resolves to a synthetic struct with one property per non-variadic named parameter (key `$name`, type = parameter type). Parameters with defaults are optional fields and may be omitted from a literal; required parameters must be present (TYHP4325). Facets without names (`callable(string): int`) degrade to an empty struct. Variadic parameters are omitted (extra keys stay unknown-property errors). Erases to `array`. An unbound `TCallable` stays deferred until the callable is inferred at a call site.
:::

:::member[__CallableParametersTuple<TCallable>]
Positional-argument bag for a callable type `TCallable`. Resolves to a synthetic struct with int key aliases `0 as $_1`, `1 as $_2`, … matching the hand-written `CallableArgs*` convention. Unlike the named bag, parameter names are not required — a bare `callable(string): int` facet still produces `$_1: string`. Defaulted trailing parameters are optional indexes and may be omitted from a list literal; required indexes must be present. Variadic parameters are omitted. Erases to `array`. An unbound `TCallable` stays deferred until the callable is inferred at a call site. List literals (`['Ada', 36]`) and explicit int keys (`[0 => 'Ada', 1 => 36]`) assign when types match.
:::

:::member[__CallableParametersRest<TCallable>]
Rest-unpack of a callable type `TCallable`'s parameter list (TypeScript `...args: Parameters<T>`). Used as a trailing variadic: `function invoke<TCallable extends callable>(TCallable $cb, __CallableParametersRest<TCallable> ...$args): __CallableReturnType<TCallable>`. After `TCallable` is inferred from `$cb`, each remaining positional argument is checked 1:1 against the callable's parameters (TYHP4010 / TYHP4142 / TYHP4143). Defaulted parameters may be omitted; a trailing variadic on the callable accepts extra arguments at that element type. Bare opaque `callable` stays gradual (unknown arity). Unions of same-arity callables merge parameter types; mismatched arities stay gradual. A trailing spread (`...$packed`) or a named pack into the rest parameter is not treated as an empty argument list. Positionals after a rest-region spread are not typed as the first inner parameter. The wrapper is kept at check time (it does not collapse to a Tuple struct). It is a **pack**: inside a callable-shape parameter list it auto-splices into ordinary parameters. Erases to `mixed` so PHP does not demand each unpacked argument be an array.
:::

:::member[__CallableParametersSlice<TCallable, TStart, TMin>]
Slice of a callable type `TCallable`'s parameter list. `TStart` / `TMin` are non-negative int literal types (defaults `0`). A non-variadic `Slice<T, N> $x` is exactly parameter N (`TMin` must not be written). A variadic `Slice<T, N> ...$xs` covers parameters from N for as many arguments as are passed (`N ≥ TMin`). `array<Slice<T, 0>>` is an array of `P_0`. Same-function slices of one `TCallable` must be disjoint, ordered by `TStart`, with at most one open rest and no holes (`TYHP4189`–`TYHP4191`). Erases like Rest (`mixed` when used as a rest unpack).
:::

:::member[__CallableThis<TCallable>]
The `$this` bound on a callable type `TCallable`. For `\Closure<C, TThis, TScope>` this is `TThis`. An invokable object (`__invoke`) is that class. Bare `callable` is `object | null`. Distributes over unions and intersections. Erases to `?object`.
:::

:::member[__CallableScope<TCallable>]
The visibility-scope class of a callable type `TCallable`. For `\Closure<C, TThis, TScope>` this is `TScope`. An invokable object is that class. Bare `callable` is `object | __ClassName | null`. Distributes over unions and intersections. Erases to `object|string|null`.
:::

:::member[__ClosureThis]
Overlay alias in `tyhpdef/php`: `object|null`. Default `TThis` on `\Closure` so static closures still match when `TThis` is omitted.
:::

:::member[__ClosureScope<TThis>]
Overlay alias: `__SuperType<TThis> | __SuperTypeName<TThis> | null`. Default stored `TScope`. `'static'` is not part of this union.
:::

`\call_user_func` and `\call_user_func_array` in ExtStandard use these utilities:

```tyhp
function call_user_func<TCallable extends callable>(
    TCallable $callback,
    __CallableParametersRest<TCallable> ...$args
): __CallableReturnType<TCallable>;

function call_user_func_array<TCallable extends callable>(
    TCallable $callback,
    __CallableParametersStruct<TCallable> $args
): __CallableReturnType<TCallable>;

function call_user_func_array<TCallable extends callable>(
    TCallable $callback,
    __CallableParametersTuple<TCallable> $args
): __CallableReturnType<TCallable>;
```

`TCallable` is inferred from `$callback` (no `typeof` in type position). Named assoc arrays select the Struct overload; list / int-keyed arrays select the Tuple overload. Untyped `array` bags still use `\call_user_func_array_unsafe`. Hand-written `CallableArgs*` structs remain as examples; builtins no longer use the arity ladder. Peers (`forward_static_call*`, `register_shutdown_function`, `iterator_apply`, `\Closure::call`) follow the same pattern when retyped.

Locked decisions: utilities are keyed by the callable type, not a name string; optional parameters are modeled as optional struct fields (required-key assignability), not a power-set of subset bags; positional bags are first-class via Tuple (int keys `0..n-1`, `$_N` aliases).

:::member[__TypeDiff<T, U>]
Type subtraction: produces `T` with `U` removed. If nothing remains, resolves to `void`.
:::

:::member[__NonNullable<T>]
Strips `null` from a type. Returns `void` if the input was just `null`. On a pack, maps each member.
:::

:::member[__Nullable<T>]
Makes a type nullable (`T|null`). On a pack, maps each member (`?P0, ?P1, …`) so the result splices inside a callable-shape parameter list.
:::

:::member[__AsReadOnly<T>]
Marks a type as readonly. The compiler errors if you try to modify a variable or property of this type.
:::

:::member[__AsTypeName<T>]
Converts a type to its string name representation. The inverse of `__AsType`.
:::

:::member[__AsType<T>]
Converts a type name string back to the actual type. The inverse of `__AsTypeName`.
:::

:::member[__AsNotNullableTypeName<T>]
Converts a type name string to its non-nullable version. Returns `__NonMatchingStringType` if the input was `'null'`.
:::

:::member[__AsNullableTypeName<T>]
Converts a type name string to its nullable version.
:::

## Compiled PHP Output for Generic Types

All generic type parameters are erased in the compiled PHP output. The base type is preserved, but the generic arguments are stripped:

```tyhp
<?tyhp

function getNames(array<string> $items): array<string> {
    return \array_filter($items, fn(string $s): bool => \strlen($s) > 0);
}

\WeakMap<object, string> $cache = new \WeakMap();
```

Compiles to:

```php
<?php
declare(strict_types=1);

function getNames(array $items): array {
    return \array_filter($items, fn(string $s): bool => \strlen($s) > 0);
}

$cache = new \WeakMap();
```

## Best Practices

:::tip
Use generic array types (`array<string>`, `array<string, int>`) instead of plain `array` for element-level type safety. `array<string>` is shorthand for `array<int|string, string>`. The compiler can then catch type mismatches when adding or retrieving elements.
:::

:::tip
Use `callable(TArgs …): TReturn` for “any invokable” parameters. Use `\Closure<callable(TArgs …): TReturn>` when you need a Closure object (`bind` / `bindTo` / `call` / `fromCallable`) or the class type. Do not put argument types as `\Closure`’s own type arguments.
:::

:::tip
Prefer specific types over `mixed`. Use union types when a value can legitimately be one of several types, and reserve `mixed` for truly unknown types like deserialized data.
:::

:::tip
Use `decimal` for financial calculations and any domain where floating-point precision errors are unacceptable.
:::

## Common Mistakes

:::danger
Don't use plain `array` when you can specify `array<string>` or `array<string, int>`. The unparameterized form provides no element type safety.
:::

:::danger
Don't ignore generic type parameters on built-in types. Using `\Iterator` instead of `\Iterator<string, User>` loses type information for `current()` and `key()`.
:::

:::danger
Don't use `float` for financial calculations. Use `decimal` instead -- `float` is subject to IEEE 754 precision errors that can accumulate in arithmetic.
:::

:::danger
Don't try to use `void` or `never` as generic type arguments unless the generic parameter's constraint explicitly allows them (e.g., `T extends void|mixed`).
:::

:::danger
Don't write `\Closure<int, string>` for “takes int, returns string”. Write `\Closure<callable(int): string>`. The same callable-shape spelling is the type argument of `Expression` / `PropertyPath` (`Expression<callable(User $u): string>`).
:::

:::danger
Don't list `\Traversable` on a user class, enum, interface, or trait. Implement `\Iterator` or `\IteratorAggregate`. Don't treat `ArrayAccess<SomeStruct>` as a per-key map — that is `TKey` plus default `TValue`. Use `\Tyhp\Contracts\ArrayAccessShape<SomeStruct>`.
:::

:::danger
Don't list `\UnitEnum` or `\BackedEnum` on a user class, interface, trait, or enum. Don't redeclare `cases`, `from`, or `tryFrom` on a user enum. Enumerations already are those engine interfaces.
:::

:::danger
Don't declare a generator as returning the body's `return` type (`function foo(): string { yield 1; return "done"; }`). The declared return is `\Generator` (or `\Generator<K, V>` / the four-arg form). `TReturn` is `$g->getReturn()`.
:::
