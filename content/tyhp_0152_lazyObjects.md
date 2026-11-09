---
title: 'Lazy Objects'
status:
  state: complete
---

`lazy new` constructs a PHP 8.4 lazy ghost when `output.phpVersion` is 8.4 or newer. The expression evaluates its arguments immediately. The constructor runs later, on that same instance, the first time the object's state is observed. The instance keeps its identity. Below that PHP version it is an ordinary `new`.

`lazy` is only the word before `new`. A method named `lazy` is an ordinary method.

## `lazy new`

```tyhp
<?tyhp

class User {
    public function __construct(public int $id) {}
}

function make(int $id): User {
    // $id is read now. User::__construct runs the first time $user's state is observed.
    User $user = lazy new User($id);
    return $user;
}
```

The two forms are `lazy new Name(args)` and `lazy new Name<T>(args)`, including an empty argument list. Arguments run in the caller's scope, in written order, before the ghost exists. An argument that throws throws at the expression. Positional, named, and spread arguments reach the constructor as written.

`lazy new static()` is late-bound: the class is the one that was called. A class with no constructor gets an initializer that does nothing, not a call to `__construct`.

`lazy new $class` and `lazy new class { }` do not parse.

When `output.phpVersion` is below 8.4, `lazy new` is an ordinary `new` (or the ordinary generic factory). The emitted PHP does not test `\PHP_VERSION_ID`, so a project compiled for an older PHP stays eager when it later runs on PHP 8.4. See [PHP Version Gating](tyhp_0320_phpVersionGating.md).

### When the constructor runs

On PHP 8.4 and newer, the ghost initializes in place when its state is observed or modified: reading or writing a property, iterating properties, `serialize`, `json_encode`, and `clone`. A method call that does not touch a property does not initialize it. The object before and after initialization is the same instance.

`ReflectionClass::SKIP_INITIALIZATION_ON_SERIALIZE`, passed as the `$options` of `\Tyhp\Lazy::ghost` or `reset`, opts out of initialization during `serialize`. `json_encode` still reads the object's state and initializes it.

If the initializer throws, the exception propagates and PHP leaves the object lazy.

### What can stay lazy

A ghost stays uninitialized only when the class stores at least one instance property. That property may be declared on the class, inherited, or brought in by a trait. Static properties do not count, and neither does a virtual property that only has hooks and no stored value.

A generic class that Tyhp tracks at runtime stores its type arguments on the instance. That storage counts, so the class can be lazy even when you declare no property:

```tyhp
<?tyhp

class Box<T> {
    public function __construct(T $item) {
        echo (string) typeof(T), "\n";
    }
}

function make(): Box<int> {
    return lazy new Box<int>(1);
}
```

The constructor observes `int`. The compiler binds the type arguments on that instance before `__construct` runs.

`\Tyhp\Lazy::ghost` binds its own type parameter, the class of the instance, and does not bind that class's type arguments. The parameter sits in `callable(T): void`, so PHP calls the binder: `Lazy::ghost(\App\User::class)($initializer)`. `proxy` and `reset` are `#[\Tyhp\InferGeneric]` and stay plain calls; explicit type arguments use the `proxy__tyhpGeneric` and `reset__tyhpGeneric` companions. When the class or its type arguments are chosen at runtime, call `\Tyhp\Generic::bind($className, T::int)->ghost(...)`. A `ReflectionClass::newLazyGhost` closure you write yourself skips the generic-class binding, and the constructor then sees unbound type arguments.

`lazy new` of a generic class compiled in another package emits `\Tyhp\Generic::bind(...)(...)`, which runs the constructor immediately. Call `ghost()` on that binder to defer it. See [Generics](tyhp_0500_generics.md).

### Diagnostics

**TYHP4402** (error). `` `lazy new` cannot construct `{0}` ``. The target is an internal PHP class other than `\stdClass`, a class that extends an internal class other than `\stdClass`, or a non-class (a struct, interface, enum, trait, or type parameter). `\stdClass`, and a user class that extends only `\stdClass`, are allowed.

**TYHP4403** (warning). `` `{0}` has no lazy-capable instance property, so `lazy new` runs the constructor immediately ``. PHP would return a normal instance and never call the initializer, so Tyhp emits an ordinary `new` and the constructor does run. The expression is still valid. `\stdClass` has no stored property, so `lazy new \stdClass()` reports this warning. A class that extends `\stdClass` and declares an instance property does not.

A wrong constructor argument list uses the same diagnostic as `new`.

## `\Tyhp\Lazy`

`final class \Tyhp\Lazy` lives in `tyhp/core`. It cannot be constructed. The PHP 8.4 and 8.5 builds call the reflection methods below and do not test `\PHP_VERSION_ID`. The PHP 8.2 and 8.3 builds are eager: the initializer or factory runs before the call returns, the object is not lazy, and those builds stay eager when they run on a newer PHP.

| Method | PHP 8.4 and 8.5 builds | PHP 8.2 and 8.3 builds |
|--------|------------------------|------------------------|
| `ghost` | `ReflectionClass::newLazyGhost`. The instance stays uninitialized until something reads it, then the initializer runs on that same instance. | `newInstanceWithoutConstructor()`, then the initializer. Not lazy. |
| `proxy` | `ReflectionClass::newLazyProxy`. The value is not the instance the factory returns. | Calls the factory immediately and returns that value. Not a proxy. |
| `isLazy` | `ReflectionClass::isUninitializedLazyObject`. | `false`. |
| `initialize` | `ReflectionClass::initializeLazyObject`. Returns the same instance. | Returns the object. |
| `reset` | `ReflectionClass::resetAsLazyGhost`. | Runs the initializer on the existing instance. The instance does not become lazy. |
| `preset` | `ReflectionProperty::setRawValueWithoutLazyInitialization`. Does not initialize. | `ReflectionProperty::setValue`. |

```tyhp
<?tyhp

use Tyhp\Lazy;

function ghostUser(int $id): User {
    return Lazy::ghost(function (User $user) use ($id): void {
        $user->__construct($id);
    });
}
```

:::member[public static function ghost<T extends object>(callable(T): void $initializer, int $options = 0): T]
Creates a ghost of `T`. `$initializer` runs on that instance when it initializes. An exception it throws propagates and, on the native build, leaves the object lazy. `$options` is forwarded to `ReflectionClass::newLazyGhost` (`SKIP_INITIALIZATION_ON_SERIALIZE`, `SKIP_DESTRUCTOR`).

`T` is the class. `ghost` does not bind that class's type arguments. A `new` inside the initializer constructs a different instance and binds that instance the way an ordinary `new` does.
:::

:::member[public static function proxy<T extends object>(callable(T): T $factory, int $options = 0): T]
Creates a lazy proxy. The factory returns the real instance, which is a different object. On the PHP 8.2 and 8.3 builds this is not a proxy: the caller receives the factory's return value immediately. `$options` is forwarded to `ReflectionClass::newLazyProxy`.
:::

:::member[public static function isLazy(object $object): bool]
`true` when `$object` is a lazy object that has not been initialized. This is not `ReflectionProperty::isLazy`. On the PHP 8.2 and 8.3 builds it is `false`.
:::

:::member[public static function initialize<T>(T $object): T]
Forces initialization and returns the same value. On the PHP 8.2 and 8.3 builds it returns `$object`.
:::

:::member[public static function reset<T extends object>(T $object, callable(T): void $initializer, int $options = 0): void]
Makes an existing instance lazy again. `$options` is forwarded, including `ReflectionClass::SKIP_DESTRUCTOR` when the caller passes it. On the PHP 8.2 and 8.3 builds the initializer runs immediately and the instance does not become lazy.
:::

:::member[public static function preset<T extends object>(T $object, __PropertyName<T> $property, mixed $value): void]
Writes `$property` without initializing the object. `$property` is a property name of `T`. On the PHP 8.2 and 8.3 builds the write is `ReflectionProperty::setValue`.
:::

## `Generic::bind()->ghost()`

`\Tyhp\Generic::bind` of a class name returns a binder. `new()` and invoking the binder stay eager. `ghost()` takes the same constructor arguments and, on the PHP 8.4 and 8.5 builds of `tyhp/core`, returns a lazy ghost whose initializer binds the type arguments and then calls the constructor on that instance:

```php
<?php

use Tyhp\Generic;
use Tyhp\Type as T;

$box = Generic::bind(\Vendor\Box::class, T::int)->ghost(1);
```

The constructor observes `int`. `new()`, `__invoke()`, and `ghost()` share one construction: a second call on the same binder throws `\LogicException`.

A class with no stored instance property cannot stay lazy. PHP never calls the initializer in that case, so `ghost()` runs it before returning and the constructor still runs. A class that has no constructor is not given a `__construct` call, and arguments passed to it fail at the `ghost()` call, the same way `new` fails. On the PHP 8.2 and 8.3 builds, `ghost()` does the same thing as `new()`.

`bind()` of a callable returns a `\Closure`. That closure has no `ghost` method.

## Disposal

`using`, `using await`, and `:=` skip an uninitialized lazy object, so leaving the scope does not run its constructor. An object that has already been initialized still disposes. The check is `ReflectionClass::isUninitializedLazyObject`. It does not call `\Tyhp\Lazy::isLazy`. A project whose `output.phpVersion` is below 8.4 still skips a ghost when it runs on PHP 8.4 or newer, because the emitted check tests `\PHP_VERSION_ID` first. See [Disposables](tyhp_2300_disposables.md).

## Doctrine ORM

Doctrine ORM users turn on native lazy objects with `\Doctrine\ORM\Configuration::enableNativeLazyObjects(true)`.
