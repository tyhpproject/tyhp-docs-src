---
title: 'Disposables and the := Operator'
status:
  tier: 1
  story: '11'
  state: complete
---

Tyhp provides deterministic resource management through the `IsDisposable` and `AsyncIsDisposable` interfaces, the `:=` (using assignment) operator, and the `using` block. These features make sure resources such as database connections, file handles, and network sockets are cleaned up when you are finished with them.

## The IsDisposable Interface

Any class that manages a resource should implement `\Tyhp\Contracts\IsDisposable` (provided by the `tyhp/core` package). The interface requires a single `dispose()` method that performs cleanup.

```tyhp
<?tyhp

use Tyhp\Contracts\IsDisposable;

class DatabaseConnection implements IsDisposable {
    public function __construct(private readonly string $name) {}

    public function query(string $sql): string {
        return "{$this->name}: {$sql}";
    }

    public function dispose(): void {
        echo "closed {$this->name}\n";
    }
}
```

## The AsyncIsDisposable Interface

For resources that need asynchronous cleanup (for example, closing a connection over the network), implement `\Tyhp\Contracts\AsyncIsDisposable` (provided by the `tyhp/async` package). The interface requires a `disposeAsync()` method that returns a promise.

```tyhp
<?tyhp

use Tyhp\Contracts\AsyncIsDisposable;
use Tyhp\Promise;

class AsyncConnection implements AsyncIsDisposable {
    public function __construct(private readonly string $name) {}

    public async function fetch(string $path): string {
        await Promise::delay(5);
        return "{$this->name}{$path}";
    }

    public async function disposeAsync(): void {
        await Promise::delay(5);
        echo "async closed {$this->name}\n";
    }
}
```

## The := Operator (Using Assignment)

`:=` assigns a disposable value to a variable and registers it for disposal. The resource is disposed automatically when the enclosing scope ends, whether it ends normally or by an exception: the function's return for a `:=` at function level, or the end of the block for a `:=` inside a nested block (see [Nested Blocks](#nested-blocks)). The value on the right must be an object of a class that implements `IsDisposable` or `AsyncIsDisposable`; any other type is rejected with **TYHP4030**.

```tyhp
<?tyhp

function scoped(): void {
    // := registers $db for disposal when the function returns
    $db := new DatabaseConnection('scoped');
    echo $db->query('SELECT 1'), "\n";
}

// scoped() prints:
// scoped: SELECT 1
// closed scoped
```

In an async function, an `AsyncIsDisposable` value declared with `:=` has `disposeAsync()` awaited when the function finishes:

```tyhp
<?tyhp

async function asyncScoped(): void {
    $conn := new AsyncConnection('scoped-async');
    string $data = await $conn->fetch('/api/data');
    echo $data, "\n";
}

// await asyncScoped() prints:
// scoped-async/api/data
// async closed scoped-async
```

## Compiled PHP Output — DisposableScope

`:=` compiles to a `\Tyhp\DisposableScope` from the `tyhp/async` package. The compiler creates one scope object per scope that declares disposables and registers each resource with `$scope->using(...)`. When PHP destroys the scope object as the function returns, its `__destruct()` disposes every registered resource.

```php
<?php

function scoped(): void
{
    $__scope_0 = \Tyhp\DisposableScope::create();
    $db = $__scope_0->using(new DatabaseConnection('scoped'));
    echo $db->query('SELECT 1'), "\n";
}
```

## Multiple Disposable Resources

Resources declared with `:=` in the same scope share one `DisposableScope` and are disposed in reverse order of registration (LIFO), like C#'s `using` declarations.

```tyhp
<?tyhp

function multiScope(): void {
    $source := new DatabaseConnection('source');
    $target := new DatabaseConnection('target');
    $logger := new DatabaseConnection('logger');
    echo "working\n";
}

// Prints:
// working
// closed logger
// closed target
// closed source
```

```php
<?php

function multiScope(): void
{
    $__scope_1 = \Tyhp\DisposableScope::create();
    $source = $__scope_1->using(new DatabaseConnection('source'));
    $target = $__scope_1->using(new DatabaseConnection('target'));
    $logger = $__scope_1->using(new DatabaseConnection('logger'));
    echo "working\n";
}
```

## Nested Blocks

A resource declared with `:=` inside a nested block (an `if`, loop, or similar block) is disposed when that block ends, and again for each loop iteration. The compiler wraps the block's statements in `try`/`finally`, so the resource is also disposed when the block exits through `return`, `break`, or an exception. Resources declared with `:=` at function level are disposed when the function returns, after any nested-block resources.

```tyhp
<?tyhp

function nested(bool $condition): void {
    $outer := new DatabaseConnection('outer');
    if ($condition) {
        $inner := new DatabaseConnection('inner');
        echo "in block\n";
    }
    echo "after block\n";
}

// nested(true) prints:
// in block
// closed inner
// after block
// closed outer
```

```php
<?php

function nested(bool $condition): void
{
    $__scope_2 = \Tyhp\DisposableScope::create();
    $outer = $__scope_2->using(new DatabaseConnection('outer'));
    if ($condition) {
        $inner = null;
        try {
            $inner = new DatabaseConnection('inner');
            echo "in block\n";
        } finally {
            if ($inner instanceof \Tyhp\Contracts\IsDisposable) {
                $inner->dispose();
            }
        }
    }
    echo "after block\n";
}
```

A [`using` block](#the-using-block-syntax) states the same intent explicitly and also works for several resources at once.

## The using Block Syntax

A `using` block disposes its resources when the block ends, regardless of how it ends. It always compiles to `try`/`finally`, so it does not depend on reference counting or garbage collection. The resource variables belong to the block.

```tyhp
<?tyhp

function usingSingle(): void {
    using ($db = new DatabaseConnection('single')) {
        echo $db->query('SELECT 2'), "\n";
    }
}

// Resource variables may carry a type
function usingTyped(): void {
    using (DatabaseConnection $db = new DatabaseConnection('typed')) {
        echo $db->query('SELECT 3'), "\n";
    }
}

// usingSingle() prints:
// single: SELECT 2
// closed single
```

```php
<?php

// A single resource compiles to try/finally
function usingSingle(): void
{
    $db = new DatabaseConnection('single');
    try {
        echo $db->query('SELECT 2'), "\n";
    } finally {
        if ($db instanceof \Tyhp\Contracts\IsDisposable) {
            $db->dispose();
        }
    }
}
```

## Multiple Resources in a using Block

A `using` block can declare several resources separated by commas. They are initialized in order and disposed in reverse order in a single `finally`. Each `dispose()` call is isolated, so an exception from one does not prevent the others from running; the collected exceptions are then thrown together as an `AggregateException`.

```tyhp
<?tyhp

function usingMultiple(): void {
    using ($db = new DatabaseConnection('db'), $cache = new DatabaseConnection('cache')) {
        echo "working\n";
    }
}

// Prints:
// working
// closed cache
// closed db
```

```php
<?php

function usingMultiple(): void
{
    $db = null;
    $cache = null;
    try {
        $db = new DatabaseConnection('db');
        $cache = new DatabaseConnection('cache');
        echo "working\n";
    } finally {
        $__disposeErrors = [];
        if ($cache instanceof \Tyhp\Contracts\IsDisposable) {
            try {
                $cache->dispose();
            }
            catch (\Throwable $__e) {
                $__disposeErrors[] = $__e;
            }
        }
        if ($db instanceof \Tyhp\Contracts\IsDisposable) {
            try {
                $db->dispose();
            }
            catch (\Throwable $__e) {
                $__disposeErrors[] = $__e;
            }
        }
        if (!empty($__disposeErrors)) {
            throw new \Tyhp\Exceptions\AggregateException($__disposeErrors, 'One or more errors during disposal');
        }
    }
}
```

With a single resource, an exception thrown by `dispose()` propagates unchanged.

## Reverse Order Disposal

Both `:=` and `using` dispose resources in reverse order (last in, first out), so resources are released in the opposite order they were acquired. This matters when resources depend on each other, such as a query that depends on a connection.

## Choosing := vs using Block

:::member[:= operator]
Disposes when the function returns. Lighter syntax, works anywhere in a function. Relies on PHP reference counting to run the scope's destructor, so a reference cycle can delay disposal (see [Circular Reference Mitigation](#circular-reference-mitigation)). A disposal error is reported as a PHP warning, not thrown.
:::

:::member[using block]
Disposes when the block ends, through `try`/`finally`. Deterministic regardless of reference cycles or garbage collection. Disposal errors are thrown.
:::

## Async Disposal

When `DisposableScope` disposes an `AsyncIsDisposable`, it waits for `disposeAsync()` to settle:

- If the promise has already settled, it observes the result immediately (this also works from a synchronous event-loop callback).
- Inside a fiber, it suspends the fiber with `Promise::_await()` so the running loop can continue.
- Outside a fiber with the loop idle, it blocks with `Promise::wait()` until this promise settles. It does not run unrelated queued work.
- A *pending* async disposal from a synchronous callback while the loop is running cannot be waited on, and throws `AsyncContextException`. Prefer `using await`, or dispose from async code.

`using await` disposes its resources asynchronously in the `finally` block. It is only allowed inside async functions, closures, and blocks; elsewhere it reports **TYHP4028**. A resource that implements `AsyncIsDisposable` has `disposeAsync()` awaited; one that implements only `IsDisposable` has `dispose()` called.

```tyhp
<?tyhp

async function usingAwait(): void {
    using await ($conn = new AsyncConnection('using-await')) {
        string $data = await $conn->fetch('/api/data');
        echo $data, "\n";
    }
}

// await usingAwait() prints:
// using-await/api/data
// async closed using-await
```

```php
<?php

// using await compiles to try/finally with an awaited async dispose
function usingAwait(): \Tyhp\Promise
{
    return \Tyhp\Promise::_async(function (): void {
        $conn = new AsyncConnection('using-await');
        try {
            $data = \Tyhp\Promise::_await($conn->fetch('/api/data'));
            echo $data, "\n";
        } finally {
            if ($conn instanceof \Tyhp\Contracts\AsyncIsDisposable) {
                \Tyhp\Promise::_await($conn->disposeAsync());
            }
            elseif ($conn instanceof \Tyhp\Contracts\IsDisposable) {
                $conn->dispose();
            }
        }
    });
}
```

The `tyhp/async` package also provides [`DisposableHelper::dispose()`](package_async.md#disposablehelper) for disposing several resources from async code without a `using` block.

## Circular Reference Mitigation

`DisposableScope` relies on PHP's `__destruct()`, which only runs promptly when no reference cycle keeps the scope alive. The compiler handles the most common cycle automatically: a closure that captures `$this` and is stored in a property of the same object is rewritten to capture a `WeakReference`.

```php
<?php

// Instead of this (creates a reference cycle):
$this->onReady = function (): void {
    $this->emit('ready');
};

// the compiler generates this (the variable name carries a numeric suffix):
$__weakSelf_1 = \WeakReference::create($this);
$this->onReady = function () use ($__weakSelf_1): void {
    $__weakSelf_1->get()?->emit('ready');
};
```

When the compiler finds `:=` variables that reference each other (for example `$parent->peer = $child; $child->peer = $parent;`), it cannot rely on reference counting. It reports warning TYHP4212 and compiles that scope to `try`/`finally` instead of `DisposableScope`, disposing the resources in reverse order when the function exits.

## Best Practices

:::tip
Use `:=` for resources that should be disposed when the function finishes — it is the simplest and most concise approach for most cases.
:::

:::tip
Use a `using` block when a resource must be disposed at the end of a specific block, when disposal errors must be thrown, or when the object graph contains reference cycles.
:::

:::tip
Implement `IsDisposable` on any class that manages an external resource such as a database connection, file handle, or network socket.
:::

:::tip
Implement `AsyncIsDisposable` for resources that need async cleanup, such as closing a network connection that waits for a server acknowledgement.
:::

:::tip
Make `dispose()` idempotent, so calling it more than once is harmless.
:::

## Common Mistakes

:::danger
Do not call `dispose()` yourself on a `:=` variable. The scope disposes the resource again when the function returns, so `dispose()` runs twice.
:::

:::danger
Do not declare the same resource with both `:=` and `using`. Pick one approach per resource.
:::

:::danger
Do not use `:=`, `using`, or `using await` with a class that does not implement `IsDisposable` (or `AsyncIsDisposable`). The compiler rejects it with **TYHP4030**.
:::

:::danger
Do not create reference cycles between disposable objects held in `:=` variables unless you accept the `try`/`finally` fallback described above.
:::

:::danger
Remember that a `using` block with several resources reports disposal errors as one `AggregateException`; catch and handle it where the block runs.
:::
