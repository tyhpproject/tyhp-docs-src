---
title: 'tyhp/parallel for PHP'
---

`tyhp/parallel` runs a serializable task in another PHP process and gives you a `\Tyhp\Promise` of the result. A CLI program forks a pool. php-fpm talks to a socket named by `TYHP_PARALLEL_SOCKET`. The namespace is `Tyhp\`. It depends on `tyhp/core` and `tyhp/async`.

Shared call syntax is on [Packages for PHP](php_packages.md). `await` is on [tyhp/async for PHP](php_package_async.md).

## Install

PHP 8.2 or newer. Composer requires `ext-pcntl` and `ext-posix`. The package version is `0.4`:

```bash
composer require tyhp/parallel:805.0.4
```

## Quick start

The task is a named class that implements `\Tyhp\ParallelTask`. `run()` returns the value. `runAsync` takes the result type first. `await` runs the loop and returns that value. `start` forks the pool. Call it before the process opens database connections.

```php
use Tyhp\Type as T;
use function Tyhp\await;

require 'vendor/autoload.php';

final class AddOne implements \Tyhp\ParallelTask
{
    public function __construct(private int $value) {}

    public function run(): int
    {
        return $this->value + 1;
    }
}

\Tyhp\Parallel::start();
try {
    echo await(\Tyhp\Parallel::runAsync(T::int)(new AddOne(41))), "\n";
} catch (\Tyhp\Exceptions\ParallelException $e) {
    $remote = $e->getRemoteError();
    if ($remote !== null) {
        echo $remote['class'], ': ', $remote['message'], "\n";
    }
} finally {
    \Tyhp\Parallel::shutdown();
}
```

That prints `42`. Closures and anonymous classes are not tasks. The object and the value `run()` returns have to be serializable. A pool forked by `start()` keeps classes that were already loaded in the parent, so the task class in this sample is enough. A worker service starts a new process and autoloads the class from your Composer project.

## Which calls take types first

`runAsync`, `forAsync`, `forEachAsync`, and `invokeAsync` take their types first. `start`, `isAvailable`, `shutdown`, and `serve` are ordinary calls.

`forEachAsync` has three type parameters, in order: the item type, the result type, and the key type. Omit them to leave them unbound, or pass them:

```php
await(\Tyhp\Parallel::forEachAsync(T::int, T::int, T::int)(
    [1, 2, 3],
    fn (int $n): \Tyhp\ParallelTask => new AddOne($n),
));
```

## The pool

`Parallel::start(int $workers = 4): void` forks a pool when `TYHP_PARALLEL_SOCKET` is unset. A later `start` with the same count does nothing. A different count throws. When the variable is set, `start` connects to that service and throws `\Tyhp\Exceptions\ParallelUnavailableException` if it is not accepting connections. `runAsync` starts 4 workers on its own if you have not called `start`.

`Parallel::isAvailable(): bool` is true when `TYHP_PARALLEL_SOCKET` names a service, or this is a CLI (or phpdbg) process with `pcntl_fork` and `posix_kill`. It is false inside a worker, and false in any other SAPI when the variable is unset. It does not contact the service. A down service still makes `isAvailable` true, and `runAsync` then throws `ParallelUnavailableException`.

`Parallel::shutdown(): void` stops this process's workers, or closes its connection to a service, and fails tasks that have not finished. The service keeps running when one client shuts down. Calling it again is safe.

`Parallel::serve(string $socketPath, int $workers = 4, int $socketMode = 0660): void` listens until `SIGTERM` or `SIGINT`. php-fpm sets `TYHP_PARALLEL_SOCKET` to `$socketPath`. Run the service as the php-fpm user, or as a user in the same group, and start it before opening database connections. The service must be able to autoload every task class.

The package also installs `vendor/bin/tyhp-parallel`, which loads Composer's autoload file and calls `serve`:

```bash
vendor/bin/tyhp-parallel serve --socket=/run/tyhp-parallel/app.sock --workers=4 --mode=0660
```

`--socket` defaults to `TYHP_PARALLEL_SOCKET`. `--workers` defaults to 4. `--mode` defaults to `0660`. `--bootstrap=<file>` is a PHP file loaded after the autoloader and before workers start. `--help` prints the usage and exits 0. A missing socket, an unknown argument, or a `serve` failure prints to standard error and exits 1.

In php-fpm, set the variable before the first `Parallel` call:

```text
env[TYHP_PARALLEL_SOCKET] = /run/tyhp-parallel/app.sock
```

When `TYHP_PARALLEL_SOCKET` is a non-empty path, even a CLI program sends tasks to that service instead of forking.

## One task

`Parallel::runAsync($type)(\Tyhp\ParallelTask $task, ?\Tyhp\CancellationToken $token = null)` returns a promise of the task's result. The task is serialized before the call returns. The promise rejects with `\Tyhp\Exceptions\ParallelException` when `run()` throws, the worker exits, or the result does not match the type, and with `\Tyhp\Exceptions\OperationCancelledException` when the token is cancelled first.

`ParallelException::getRemoteError(): ?array` is the exception from the worker, or `null` when the task did not throw (the worker exited, or the pool could not deliver the task). The array has `class`, `message`, `code`, `file`, `line`, and `trace`. `getRemoteClass(): string` is `class`, or `''` when there is no remote error.

```php
use Tyhp\Type as T;
use function Tyhp\await;

$value = await(\Tyhp\Parallel::runAsync(T::int)(new AddOne(1)));
```

## Many tasks

`forAsync`, `forEachAsync`, and `invokeAsync` wait for every task, keep keys, and fail fast: the first failure cancels the others and is thrown. A cancelled token cancels every task and throws `OperationCancelledException`.

| Call | Arguments |
|------|-----------|
| `forAsync($type)(int $fromInclusive, int $toExclusive, callable $factory, ?\Tyhp\CancellationToken $token = null)` | `$factory` receives the index and returns a task. `$toExclusive` is not included. |
| `forEachAsync($itemType, $resultType, $keyType)(array $items, callable $factory, ?\Tyhp\CancellationToken $token = null)` | `$factory` receives one item and returns a task. Result keys match the input keys. |
| `invokeAsync($type, $keyType)(array $tasks, ?\Tyhp\CancellationToken $token = null)` | The array values are already tasks. |

```php
use Tyhp\Type as T;
use function Tyhp\await;

$results = await(\Tyhp\Parallel::forAsync(T::int)(
    0,
    3,
    fn (int $i): \Tyhp\ParallelTask => new AddOne($i),
));
```

`forAsync` rejects with `\InvalidArgumentException` when `$fromInclusive` is greater than `$toExclusive`.

A task cannot start more parallel work. Inside a worker, `Parallel` throws `ParallelUnavailableException`.

## Errors

| Exception | When |
|-----------|------|
| `\Tyhp\Exceptions\ParallelException` | `run()` threw, the worker exited, or the result could not be delivered. Read `getRemoteError()`. |
| `\Tyhp\Exceptions\ParallelUnavailableException` | This process cannot run a task: not a CLI process and `TYHP_PARALLEL_SOCKET` is unset, `ext-pcntl` or `ext-posix` is missing, the call is inside a worker, or the service is not accepting connections. Extends `ParallelException`. `getRemoteError()` is `null`. |
| `\Tyhp\Exceptions\OperationCancelledException` | The token was cancelled. |

## Related

- [Packages for PHP](php_packages.md)
- [tyhp/async for PHP](php_package_async.md), [tyhp/io for PHP](php_package_io.md), [tyhp/core for PHP](php_package_core.md)
- [The tyhp/parallel Package](package_parallel.md) — the same package as used from Tyhp
