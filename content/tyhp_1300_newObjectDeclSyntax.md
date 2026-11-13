---
title: 'New Object Declaration Syntax'
status:
  tier: 0
  story: '06'
  state: complete
---

Tyhp adds new syntax to class declarations that does not exist in PHP. This includes constructor return types for explicit constructor chaining, promoted constructor parameters, and property accessors. These features make class declarations more expressive and self-documenting.

## Constructor Return Types

In PHP, constructors never have a return type. Tyhp constructors may declare `: void` when the constructor does not chain to a parent, or `: parent(args...)` when it does. Omitting the return type is equivalent to `: void`: no `parent::__construct(...)` call is inserted. Use `: parent(args...)` when you want the parent constructor called first.

## Explicit Void Constructor

A constructor that does not use `: parent(...)` may be declared `: void`, or the return type may be omitted entirely — the two forms are equivalent. Both mean this constructor does not insert a `parent::__construct(...)` call.

```tyhp
<?tyhp

class SimpleClass
{
    public function __construct(
        public string $name,
        public int $age
    ): void {}
}

// Equivalent: the return type may be omitted.
class AnotherClass
{
    public function __construct(
        public string $name,
        public int $age
    ) {}
}
```

## Compiled PHP Output

The : void annotation is stripped from the PHP output. The constructor is emitted as a standard PHP constructor with no return type.

```php
<?php

class SimpleClass
{
    public function __construct(
        public string $name,
        public int $age
    ) {}
}
```

## Constructor Chaining with : parent(args...)

The : parent(args...) syntax calls the parent constructor at the START of the child constructor body. The arguments in the parent(...) call are passed to parent::__construct(). This replaces the manual parent::__construct(...) call that PHP developers write by hand and guarantees it always runs first.

```tyhp
<?tyhp

class BaseModel
{
    public function __construct(
        protected bool $isActive,
        protected int $priority,
        protected string $label
    ): void {}
}

class UserModel extends BaseModel
{
    public string $displayName;

    public function __construct(string $name): parent(false, 19, $name)
    {
        $this->displayName = \strtoupper($name);
    }
}
```

## Compiled PHP Output

The : parent(args...) annotation compiles to a parent::__construct(args...) call inserted at the very beginning of the constructor body. The return type annotation is removed.

```php
<?php

class BaseModel
{
    public function __construct(
        protected bool $isActive,
        protected int $priority,
        protected string $label
    ) {}
}

class UserModel extends BaseModel
{
    public string $displayName;

    public function __construct(string $name)
    {
        parent::__construct(false, 19, $name);
        $this->displayName = \strtoupper($name);
    }
}
```

## Original Incoming Values

An important detail: the arguments passed to parent(...) use the original incoming parameter values, not values modified within the constructor body. Even if a parameter is reassigned inside the constructor, the parent receives the value as it was when the constructor was called.

```tyhp
<?tyhp

class Child extends BaseModel
{
    public string $processed;

    public function __construct(string $input): parent(true, 5, $input)
    {
        $input = \strtolower($input);
        $this->processed = $input;
    }
}
```

```php
<?php

class Child extends BaseModel
{
    public string $processed;

    public function __construct(string $input)
    {
        parent::__construct(true, 5, $input);
        $input = \strtolower($input);
        $this->processed = $input;
    }
}
```

:::tip
Because parent(...) is called before the constructor body executes, the parent always receives the original parameter values. This prevents subtle bugs where a developer modifies a parameter before calling parent::__construct().
:::

## Passing Static Values and Parameters

Because parent(...) is inserted at the start of the constructor body, prefer literals, constants, and incoming parameters. Avoid `$this` and method calls in those arguments — the instance is not fully constructed yet. The compiler does not currently reject those expressions; treat this as guidance, not a hard check.

```tyhp
<?tyhp

class Vehicle extends BaseModel
{
    public function __construct(
        string $type,
        int $year
    ): parent(true, $year, $type) {}
}

class DefaultVehicle extends BaseModel
{
    public function __construct(): parent(false, 0, 'unknown') {}
}
```

```php
<?php

class Vehicle extends BaseModel
{
    public function __construct(
        string $type,
        int $year
    ) {
        parent::__construct(true, $year, $type);
    }
}

class DefaultVehicle extends BaseModel
{
    public function __construct()
    {
        parent::__construct(false, 0, 'unknown');
    }
}
```

## Constructor Property Promotion

Constructor property promotion works as in PHP 8. Constructor parameters may be promoted with visibility and `readonly`. Use `readonly` when a property should be set only during construction. `clone $obj with [...]` can still update `readonly` properties on the copy; see the `with` keyword page.

```tyhp
<?tyhp

class Point
{
    public function __construct(
        public readonly float $x,
        public readonly float $y,
        public readonly float $z = 0.0
    ): void {}
}

$p = new Point(1.0, 2.0);
$q = clone $p with [z => 5.0];
```

## Property initialization

A typed property stores a value. Absence is a nullable type set to null (`?string $name = null`), or another empty value the domain uses.

`unset` of a local, a typed instance property, or a static property is an error (TYHP4158). Assign `null` on a nullable declaration to drop the value. Unsetting an array element stays legal (`unset($items[$i])`, `unset($obj->items[$key])`). Unsetting an optional struct field stays legal because a struct is an array.

### Static properties

Every typed static property on a class, trait, or anonymous class needs an initializer (TYHP4418), including `?T` and `mixed`:

```tyhp
<?tyhp

class Settings
{
    public static string $name = '';
    public static ?string $cache = null;
    public static mixed $box = null;
}
```

A `.tyhpdef` may document a PHP static property that has no default. An interface property cannot take an initializer, an enum cannot declare a property, and a readonly class cannot declare a static property, so those declarations are not asked for one.

### Instance properties

After construction, every typed instance storage property is initialized (TYHP4419). Reading one that is not initialized is TYHP4157. Hooked properties are not this check. Static properties are TYHP4418.

Any of these initializes a property:

- A declaration initializer (`public string $name = ''`). That value is applied when the object is created, including when a subclass replaces `__construct`.
- A promoted constructor parameter, only when the constructor that declares it runs. An inherited promoted parameter, even one with a default, does not count when a child replaces `__construct` and does not run the parent constructor.
- A direct `$this->prop = …` in the constructor. An assignment inside a helper or a closure does not count.

A subclass that declares `__construct` does not run the parent constructor unless `parent::__construct(...)` or `: parent(...)` runs on every path that reaches the end of the child constructor and on every `return` that leaves it. A call on only one arm of an `if` does not cover the other. A `throw` abandons the object. `: parent(...)` is that call before the body.

A class that does not declare `__construct` runs the nearest ancestor constructor, including a constructor a trait contributes. A further descendant that also declares none runs that same constructor. A gap is reported on the class whose constructor leaves a property uninitialized.

A private property of an ancestor is not assigned from the child. When skipping the parent constructor would leave that property uninitialized, TYHP4419 names it on the child constructor. A private property with a declaration initializer does not need that call.

A property a trait introduces is checked on each class that uses the trait. An initializer on the trait property is a declaration guarantee.

Calling a `.tyhpdef` constructor, or inheriting it by declaring none, counts as initializing that stub's typed instance properties that have no initializer. A `.tyhpdef` type whose stub chain declares no constructor has nothing to call, so a subclass that replaces `__construct` is not asked to initialize its properties.

An anonymous class is named `class@anonymous` in TYHP4419.

## Property Accessors (PHP 8.4 Hooks)

Tyhp supports PHP 8.4 property hooks (`get` / `set`) on class properties. Hook bodies match PHP: a parameter-less `get { ... }`, optional `set { ... }` (the incoming value is `$value`), or a typed `set(string $value) { ... }`. `&get` and `final get` / `final set` are also valid.

```tyhp
<?tyhp

final class Widget {
    private string $_name = '';

    public string $name {
        get {
            return $this->_name;
        }
        set(string $value) {
            $this->_name = $value;
        }
    }
}
```

On PHP 8.4+, the compiler emits native hook syntax. On PHP 8.2–8.3, it lowers the same source through a polyfill (`\Tyhp\Concerns\UsesPropertyAccessors` and `$this->__tyhpPropertyHook`) so hooked properties work without native PHP 8.4 hooks.

To **describe** a hooked PHP property in a `.tyhpdef` file, write the bodyless list `{ get; set; }` (or `{ &get; }`). Hook bodies stay in `.tyhp` (and in PHP). See [Classes in Tyhpdef](tyhpdef_classes.md#properties).

## Best Practices

:::tip
A constructor without a return type is `: void`. Use `: void` (or omit it) when there is no parent call; use `: parent(args...)` when chaining so the parent constructor always runs first.
:::

:::tip
`: void` on constructors is optional and stripped from PHP output. Omitting it produces the same emitted PHP.
:::

:::tip
Use constructor property promotion with `readonly` for concise, immutable data classes. Update copies with `clone $obj with [...]`.
:::

## Common Mistakes

:::danger
Do not use : parent(...) on a class that has no parent class — the emitter still inserts `parent::__construct(...)`, which PHP will reject at runtime. Diagnostic TYHP4065 (`CheckerParentWithoutParent`) is for the type name `parent`, not this constructor-chaining form.
:::

:::warning
Prefer not to use `$this` or method calls in parent(...) arguments — the parent call runs before the constructor body. The compiler does not currently reject those expressions.
:::

:::warning
Do not also write a manual `parent::__construct()` when using : parent(...) — the compiler already inserts the call, so a second call would run the parent constructor twice. The compiler does not currently diagnose the duplicate.
:::

```tyhp
<?tyhp

// Avoid: no parent class to chain to (emits parent::__construct anyway)
// class NoParent {
//     public function __construct(): parent() {}
// }

// Avoid: $this / method calls in parent args (not a compiler error today)
// class Bad extends BaseModel {
//     public function __construct(string $name): parent(true, 0, $this->process($name)) {}
// }

// Avoid: double parent call (not a compiler error today)
// class Double extends BaseModel {
//     public function __construct(string $name): parent(true, 0, $name) {
//         parent::__construct(true, 0, $name);
//     }
// }
```

## Compiler Errors

- Passing arguments to parent(...) that don't match the parent constructor's parameter types.
