---
title: 'The with Keyword'
status:
  tier: 1
  story: '11'
  state: complete
---

The with keyword in Tyhp provides a concise way to set properties on objects and structs. It is a binary operator that produces a fully initialized value in a single expression. Combined with `readonly` properties, `clone ... with` enables immutable update patterns.

Object `with` mutates identity. Struct `with` rebinds an array. That is the same distinction as passing an object vs passing an array into a PHP function: the callee can mutate the object instance; assignments to an array parameter do not change the caller's array unless the parameter is by-ref.

## The Three Forms of with

Tyhp supports three forms of the with keyword, distinguished by what appears on its left-hand side:

:::member[new X(...) with [...]]
Follows a new expression. Constructs a fresh instance and sets the listed properties on it. The result is the newly constructed object.
:::

:::member[clone $x with [...]]
Follows a clone expression. Copies the source object (shallow clone), sets the listed properties on the copy, and leaves the original unchanged. The result is the cloned object. This is the immutable-update form.
:::

:::member[$obj with [...]]
Operates in-place on an existing object instance. It MUTATES the same instance and RETURNS THE SAME instance — there is no clone and no new. Use this form when you want to set several properties on an object you already hold and keep working with that exact object.
:::

## Basic Syntax

The with keyword follows a new expression, a clone expression, or an existing object/struct value, and is followed by a `[...]` list where keys are property names and values are the values to assign.

```tyhp
<?tyhp

class User {
    public string $name;
    public int $age;
    public string $role = 'user';

    public function __construct(string $name, int $age): void {
        $this->name = $name;
        $this->age = $age;
    }
}

// Using with after new
$user = new User('Alice', 30) with [
    role => 'admin'
];

// Using with after clone
$updated = clone $user with [
    name => 'Bob',
    age => 25
];
```

## Compiled PHP Output

Emit depends on whether `with` is a **statement** or an **expression**, whether the properties are `readonly`, and the target PHP version.

**Statement** form (an assignment, or a bare `$obj with [...]`): non-readonly properties become direct assignments — no temp, no helper. `new ... with` assigns on the new instance, in-place `with` assigns on the object you already hold, and `clone ... with` clones first and then assigns on the clone. On PHP 8.5, `clone ... with` instead emits native `clone($x, [...])`, as in the expression form below.

```php
<?php

$user = new User('Alice', 30);
$user->role = 'admin';

// PHP 8.2–8.4
$updated = clone $user;
$updated->name = 'Bob';
$updated->age = 25;
```

**Expression** form (for example `return clone $x with [...]`, or a `with` used as a value):

- `clone ... with` on PHP 8.5: native `clone($x, [...])`
- `clone ... with` on PHP 8.2–8.4: `\Tyhp\ObjectHelper::with(clone $x, [...])`
- `new ... with` on non-`readonly` properties: `\Tyhp\ObjectHelper::with(new X(), [...])` on every PHP version
- `new ... with` that sets `readonly` properties: see below
- In-place `$obj with [...]` used as a value: `\Tyhp\ObjectHelper::with($obj, [...])`, which mutates and returns the same instance

```php
<?php

// PHP 8.5 expression clone with
return clone($cfg, ['enabled' => false]);

// PHP 8.2–8.4 expression clone/new with (non-readonly)
return \Tyhp\ObjectHelper::with(clone $cfg, ['enabled' => false]);
return \Tyhp\ObjectHelper::with(new Widget(), ['color' => "blue"]);
```

**Readonly `clone ... with` on PHP 8.3–8.4** (requires `build.experimentalReadonlyCloneWith: true`, and the class must not be `readonly`) emits a reflection IIFE: an anonymous subclass with an empty constructor, `ReflectionClass::newInstanceWithoutConstructor()`, a property copy via `ReflectionObject`, overrides on a static `$__tyhp_overrides` stack, then `clone $__wrapper`. Below 8.3 this is TYHP4400. On a `readonly class` below 8.5 it is TYHP4401.

**Readonly `new ... with`:**

- Below PHP 8.3: TYHP4400 (the `__clone()` wrapper cannot assign a readonly property, and `new readonly class` does not parse)
- PHP 8.3–8.4: `clone (new class(...) extends \Color { public function __clone(): void { ... } })`, or `new readonly class(...) extends` when the class is `readonly`
- PHP 8.5: `clone(new Color(), ['alpha' => 128])`

## In-Place with on an Existing Instance

When with is applied directly to an existing object instance (not preceded by new or clone), it mutates that instance in place and evaluates to the SAME instance. No clone is made and no new object is constructed — any other reference to the object sees the updated values. This is the form to use when you want to batch-assign several properties on an object you already hold.

```tyhp
<?tyhp

class User {
    public string $name;
    public int $age;
    public string $role = 'user';

    public function __construct(string $name, int $age): void {
        $this->name = $name;
        $this->age = $age;
    }
}

$user = new User('Alice', 30);

// In-place with: mutates $user and returns the same instance
$same = $user with [
    age => 31,
    role => 'admin'
];

// $same and $user are the SAME object
// $user->age is now 31 and $user->role is now 'admin'
// ($same === $user) is true
```

## Compiled PHP Output for In-Place with

For an object instance, the in-place form compiles to direct property-assignment statements. The expression's value is the object itself, so it can be assigned without a clone or a constructor call. Used as a value inside a larger expression (for example `return $user with [...]`), it emits `\Tyhp\ObjectHelper::with($user, [...])`.

```php
<?php

$user = new User('Alice', 30);

// $same = $user with [...] aliases the object, then assigns properties
$same = $user;
$same->age = 31;
$same->role = 'admin';

// No clone, no new — $same and $user reference the same object
```

A struct is always a PHP associative array. As a statement, the in-place form reassigns the target variable (or property) with `\array_replace`.

```tyhp
<?tyhp

type Coordinates = struct {
    float $lat;
    float $lng;
    float $alt = 0.0;
};

$coords = new Coordinates[lat => 40.7, lng => -74.0];

// In-place with on an existing struct value
$coords with [alt => 100.0];
```

```php
<?php

$coords = ['alt' => 0.0, 'lat' => 40.7, 'lng' => -74.0];

// In-place struct with reassigns the same variable
$coords = \array_replace($coords, ['alt' => 100.0]);
```

A property target is reassigned the same way: `$this->coords with [alt => 100.0];` emits `$this->coords = \array_replace($this->coords, ['alt' => 100.0]);`.

When an in-place struct `with` is used as a value (`$b = $a with [...]`, `return $a with [...]`), it emits `\array_replace($a, [...])` and leaves `$a` unchanged.
:::note
Choose the form by intent: use new ... with or clone ... with when you want a brand-new value (the clone form preserves immutability of the source), and use $obj with [...] when you want to update the object you already hold and keep the same identity. Because the in-place form mutates the existing instance, it cannot assign `readonly` properties after construction — use `clone $obj with [...]` (or `new ... with`) for those. A struct in-place `with` rebinds the local array (PHP array semantics); an object in-place `with` mutates the same instance (PHP object semantics).
:::

## Nested with Expressions

The with keyword supports nesting. Inner with expressions are processed before outer ones.

```tyhp
<?tyhp

class Config {
    public bool $debug = false;
    public string $env = 'dev';
}

class App {
    public Config $config;
    public string $name;
}

$app = new App() with [
    name => 'MyApp',
    config => clone $defaultConfig with [
        debug => true,
        env => 'production'
    ]
];
```

```php
<?php

// PHP 8.2–8.4
$app = new App();
$app->name = 'MyApp';
$app->config = \Tyhp\ObjectHelper::with(clone $defaultConfig, ['debug' => true, 'env' => 'production']);
```

## with and readonly Properties

`readonly` properties cannot be assigned after construction. `new ... with` and `clone ... with` are allowed to set them on the new or cloned instance. Direct assignment and in-place `$obj with [...]` after construction are not. Every instance property of a `readonly class`, including promoted constructor parameters, follows these rules whether or not it repeats `readonly`.

On PHP 8.5+, `clone ... with` uses native `clone($obj, [...])`. On PHP 8.3–8.4, `clone ... with` on `readonly` properties of a class that is not `readonly` requires `build.experimentalReadonlyCloneWith: true` in `tyhp.json` (the compiler emits a reflection IIFE: an empty subclass constructor, `newInstanceWithoutConstructor`, a static `$__tyhp_overrides` stack, then `clone $__wrapper`). Below 8.3 that form reports TYHP4400. `clone ... with` on a `readonly class` below 8.5 reports TYHP4401. `new ... with` on `readonly` does not need the flag; below 8.3 it reports TYHP4400, and on 8.3–8.4 it emits an anonymous class with `__clone()` (`new readonly class` when the class is `readonly`). PHP 8.5 uses `clone(new Color(), [...])`. `readonly` plus `with` is the immutable-update pattern.

:::member[(no modifier)]
Set in constructor: Yes. Set after construction: Yes. Set via `new`/`clone` with: Yes. Set via in-place with: Yes.
:::

:::member[readonly]
Set in constructor: Yes. Set after construction: No. Set via `new`/`clone` with: Yes. Set via in-place with: No.
:::

```tyhp
<?tyhp

class Point {
    public function __construct(
        public readonly float $x,
        public readonly float $y,
        public readonly float $z = 0.0
    ): void {}
}

$p = new Point(1.0, 2.0);

$q = clone $p with [z => 5.0];
// $p is still Point(1.0, 2.0, 0.0)
// $q is Point(1.0, 2.0, 5.0)

// $p->z = 3.0;  // ERROR: readonly
// $p with [z => 3.0];  // ERROR after construction: in-place with cannot set readonly
```

## with on Structs

A struct is constructed with a bracket list: `new Coordinates[lat => 40.7, lng => -74.0]`. That is the same as `new Coordinates() with [lat => 40.7, lng => -74.0]`, and `new Coordinates[]` is the same as `new Coordinates()`. `clone $coords with [...]` copies a value and then updates it. `$coords with [...]` rebinds the variable you already hold.

Structs are always PHP associative arrays, so `with` on a struct compiles to `\array_replace` (not `\array_merge`). That rebinds the array the same way a PHP function rebinds an array parameter — it does not mutate a shared object identity. Named, generic, and anonymous struct types support the same operations: property access and writes, `with`, `clone ... with`, `isset`, `??`, and array key aliases. With no spread, a bracket initializer emits the same array literal as `with`.

```tyhp
<?tyhp

type Coordinates = struct {
    float $lat;
    float $lng;
    float $alt = 0.0;
};

$coords = new Coordinates[lat => 40.7, lng => -74.0];
$elevated = clone $coords with [alt => 100.0];
```

```php
<?php

$coords = ['alt' => 0.0, 'lat' => 40.7, 'lng' => -74.0];
$elevated = \array_replace($coords, ['alt' => 100.0]);
```

An anonymous struct type behaves the same way. The bracket list follows the closing `}`:

```tyhp
<?tyhp

struct { string $name; int $age; } $person = new struct {
    string $name;
    int $age;
}[name => 'Alice', age => 30];

$person->age = 31;
$person with [age => 32];
$renamed = clone $person with [name => 'Bob'];
```

```php
<?php

$person = ['name' => 'Alice', 'age' => 30];
$person['age'] = 31;
$person = \array_replace($person, ['age' => 32]);
$renamed = \array_replace($person, ['name' => 'Bob']);
```

### Spread

A spread in a struct `with` list, or in a bracket initializer, copies every field of a struct value. The source has to be a named struct, a generic struct instance, or an anonymous struct. An array, `mixed`, a nullable struct, or a union is **TYHP4414**. A field the target does not declare, including through `extends`, is **TYHP4415**. Field types must be assignable (**TYHP4008**). Array keys must match, including aliases; a spread cannot rename a key (**TYHP4416**). An entry with no key is **TYHP4413**.

A required field is satisfied by a keyed entry, or by a spread whose source requires that field or gives it a default. A nullable source field without a default does not satisfy it. Later entries override earlier ones. The compiler emits `\array_replace`, which keeps integer keys.

```tyhp
<?tyhp

type Opts = struct {
    string $name;
    int $retries = 3;
    ?string $nick;
};

Opts $base = new Opts[name => 'ann'];
Opts $extra = new Opts[name => 'ann', nick => 'a'];
Opts $copy = clone $base with [...$extra, name => 'bob'];
$base with [...$copy];
```

```php
<?php

$base = ['retries' => 3, 'name' => 'ann'];
$extra = ['retries' => 3, 'name' => 'ann', 'nick' => 'a'];
$copy = \array_replace($base, $extra, ['name' => 'bob']);
$base = \array_replace($base, $copy);
```

`new Opts[name => 'a'] with [retries => 5]` is **TYHP4417**. Put every entry in the brackets: `new Opts[name => 'a', retries => 5]`. See [Structs](tyhp_0400_structs.md#spread).

## Best Practices

:::tip
Use with after new or clone to set properties concisely in a single expression.
:::

:::tip
Use `readonly` properties with `clone ... with` for immutable update patterns — the original object is never mutated.
:::

:::tip
Nest with expressions for deep property initialization instead of using multiple intermediate variables.
:::

:::tip
Use with on structs for functional-style updates — since structs are value types, this is both clean and efficient.
:::

:::tip
Prefer `readonly` over leaving properties mutable when you want immutability but still need functional updates via `new`/`clone` with.
:::

## Common Mistakes

:::danger
Do not use in-place `$obj with [...]` on readonly properties — they cannot be mutated after construction. Use `new ... with` or `clone ... with` instead.
:::

:::danger
Do not assume $obj with [...] returns a copy — the in-place form mutates and returns the SAME instance. Use clone $obj with [...] when you need an independent copy that leaves the original unchanged.
:::

:::danger
Do not set private or protected properties via with from outside the class.
:::

```tyhp
<?tyhp

class Example {
    public readonly string $id;
    public readonly string $name;

    public function __construct(string $id, string $name): void {
        $this->id = $id;
        $this->name = $name;
    }
}

$a = new Example('1', 'Alice');

// OK: clone ... with may set readonly properties on the copy
$c = clone $a with [name => 'Bob'];

// ERROR: in-place with cannot set readonly after construction
// $a with [name => 'Bob'];

// ERROR: 'nonExistent' is not a property of Example
// $d = clone $a with [nonExistent => 'value'];
```

:::warning
On PHP 8.3–8.4, `clone ... with` on `readonly` properties of a class that is not `readonly` requires `build.experimentalReadonlyCloneWith: true` in `tyhp.json`. Below 8.3 it reports TYHP4400. `clone ... with` on a `readonly class` below 8.5 reports TYHP4401. PHP 8.5+ supports `clone ... with` natively. `new ... with` on readonly does not need the flag; below 8.3 it reports TYHP4400.
:::

## Compiler Errors

- Setting a readonly property via in-place `$obj with [...]` after construction.
- `clone ... with` on a readonly property on PHP 8.3–8.4 without `build.experimentalReadonlyCloneWith`.
- Readonly `new ... with` or `clone ... with` when `output.phpVersion` is below 8.3 (TYHP4400).
- `clone ... with` on a `readonly class` when `output.phpVersion` is below 8.5 (TYHP4401).
- Setting a non-existent property via with (**TYHP4031**).
- Setting a private or protected property via with from outside the class.
- Applying with to an expression that is not a new expression, a clone expression, or an addressable object/struct instance.
- An unkeyed entry in a struct `with` list (**TYHP4413**).
- Spreading a non-struct into a struct (**TYHP4414**), a source field the target does not declare (**TYHP4415**), or a field whose array key differs (**TYHP4416**).
- A bracket initializer followed by `with` (**TYHP4417**).
