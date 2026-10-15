---
title: 'The tyhp/parallel Package'
---

`tyhp/parallel` runs CPU-heavy work in separate PHP processes and gives you the result as a `Promise`. It is a **process pool**: each task runs in a worker process with its own memory, so a long calculation uses another CPU core instead of stalling your program. You `await` the result on the normal [tyhp/async](package_async.md) event loop, so the rest of your async code keeps running while the worker is busy.

Use it for work that keeps a CPU busy: hashing, compression, image or PDF rendering, parsing large files, number crunching, or calls into a blocking library that has no async API. For work that mostly *waits* on the network, a database, or the disk, use the non-blocking clients in [tyhp/io](package_io.md) instead (see *Choosing between tyhp/parallel and tyhp/io* below).

The pool lives in one of two places:

- **CLI programs** (scripts, queue consumers, cron jobs) host the pool themselves. `Parallel::start()` forks the worker processes with `ext-pcntl`.
- **php-fpm applications** cannot fork. They connect to a separate worker service that you run with `vendor/bin/tyhp-parallel serve`, and the `TYHP_PARALLEL_SOCKET` environment variable tells them where its Unix socket is.

Your code is the same in both cases: you call `runAsync()`, `forAsync()`, `forEachAsync()`, or `invokeAsync()`.

:::note Naming convention
Methods whose names end in `Async` return a `Promise`. `await` them inside async code, or hand them to `Promise::run()` at a synchronous entry point. `start()`, `serve()`, `shutdown()`, and `isAvailable()` are ordinary synchronous calls. The same convention is used across `tyhp/async` and `tyhp/io`.
:::

## Installation and requirements

`tyhp/parallel` is not added by the compiler. Require it yourself:

```bash
composer require tyhp/parallel:804.0.*
```

Version pins follow the same `80N.X.Y` scheme as the other compiled `tyhp/*` helpers, where `80N` matches your `output.phpVersion` (`802` for PHP 8.2 through `805` for PHP 8.5) and `X.Y` is the package's own version (currently `0.1`, so the PHP 8.4 artifact is `804.0.1`). See [Composer Runtime Packages](project_composerPackages.md) for how to pin compiled helpers.

| Requirement | Why |
|-------------|-----|
| PHP 8.2 or later (the artifact for your PHP target) | Same baseline as the other runtime packages. |
| `ext-pcntl` and `ext-posix` | Forking and managing worker processes. Composer checks for them when it installs the package. The process that hosts the pool (a CLI program or the worker service) must have them loaded. |
| `tyhp/core`, `tyhp/async` | Installed automatically as dependencies. Results are delivered as `\Tyhp\Promise` values on the `tyhp/async` event loop. |

Only `tyhpdef/php` is needed to type-check code that uses the package. You do not need the pcntl or posix tyhpdefs in your project.

## Getting started: a CLI program

A task is a class that implements `\Tyhp\ParallelTask<T>`. Its `run()` method does the work in a worker and returns a value of type `T`.

```tyhp
<?tyhp

namespace App\Tasks;

use Tyhp\ParallelTask;

/** Counts the primes in [$from, $to). */
final class CountPrimesTask implements ParallelTask<int> {
    public function __construct(
        private readonly int $from,
        private readonly int $to,
    ) {}

    public function run(): int {
        int $count = 0;
        for (int $n = \max(2, $this->from); $n < $this->to; $n++) {
            bool $prime = true;
            for (int $d = 2; $d * $d <= $n; $d++) {
                if ($n % $d === 0) {
                    $prime = false;
                    break;
                }
            }
            if ($prime) {
                $count++;
            }
        }
        return $count;
    }
}
```

The entry script starts a pool of four workers, splits the range into eight chunks, runs them with `forAsync()`, and adds up the results:

```tyhp
<?tyhp

namespace App;

use App\Tasks\CountPrimesTask;
use Tyhp\Parallel;
use Tyhp\Promise;

function countPrimes(int $limit, int $chunks): int {
    int $chunkSize = \intdiv($limit, $chunks);

    int $total = Promise::run(async function () use ($limit, $chunks, $chunkSize): int {
        array<int, int> $counts = await Parallel::forAsync(
            0,
            $chunks,
            fn(int $i): CountPrimesTask => new CountPrimesTask(
                $i * $chunkSize,
                $i === $chunks - 1 ? $limit : ($i + 1) * $chunkSize,
            ),
        );

        int $sum = 0;
        foreach ($counts as int $count) {
            $sum += $count;
        }
        return $sum;
    });
    return $total;
}

function main(): void {
    Parallel::start(4);
    echo 'Primes below 8,000,000: ' . (string) countPrimes(8_000_000, 8) . "\n";
}

main();
```

Build the project with [`tyhp build`](cli_build.md) and run the emitted entry script with the PHP CLI. The file has top-level code, so it is an entry point; set `build.entryPointAutoloader` so the emitted PHP loads Composer's autoloader (see [Including Files](tyhp_0300_includingFiles.md)).

```text
Primes below 8,000,000: 539777
```

Things to notice:

- `Parallel::start(4)` runs first, before the program opens database connections or loads large data. The workers are copies of your process at the moment they are forked.
- Eight tasks share four workers. Extra tasks wait in a queue and run as workers become free.
- `forAsync()` returns the results keyed by index, in index order, no matter which task finished first.
- `forAsync()` needs no type arguments: the result type `int` comes from `CountPrimesTask implements ParallelTask<int>`.

## How it works

### Where the workers live

| | CLI program | php-fpm (or any non-CLI SAPI) |
|-|-------------|-------------------------------|
| Who owns the workers | Your process forks them with `pcntl_fork()` | A separate `tyhp-parallel serve` process |
| How you enable it | Call `Parallel::start()` (or just call `runAsync()`, which starts 4 workers) | Run the service, then set `TYHP_PARALLEL_SOCKET` to its socket path |
| Who chooses the worker count | `Parallel::start($workers)` | `--workers` on the service |
| Where task classes must load | Your process (workers are forks of it) | The service process (its `vendor/autoload.php` and `--bootstrap` file) |

The environment variable decides the mode in every SAPI. When `TYHP_PARALLEL_SOCKET` is set to a non-empty path, even a CLI program sends its tasks to that service instead of forking. When it is unset or empty, the process must be a CLI process with `ext-pcntl` and `ext-posix`.

Many processes can share one worker service at the same time. Each connected process (for example each php-fpm worker) keeps one socket to the service, and all of their tasks share the service's pool.

### The life of a task

1. **Snapshot.** `runAsync()` serializes the task object with PHP's `serialize()` before it returns. Changing the object afterward does not affect the run.
2. **Queue.** The serialized task waits until a worker is free. Each worker runs one task at a time, in the order the tasks were queued.
3. **Run.** The worker unserializes its own copy of the task and calls `run()`. The copy shares nothing with your process: no objects, sockets, or database connections.
4. **Return.** The worker serializes the value `run()` returned and sends it back. Your process unserializes it, checks that it matches `T`, and resolves the promise. If `run()` threw, the promise rejects with a `ParallelException` that describes the worker's exception.

A worker stays alive and runs more tasks after it finishes one. When a worker exits or crashes, or when a running task is cancelled, the pool removes that worker and starts a new one.

### Awaiting results on the event loop

Workers report back over sockets that the `tyhp/async` event loop watches. While a task runs, your process is free: other fibers keep running, timers fire, and `tyhp/io` requests make progress. A promise from this package settles only while the event loop is running, which means inside async code, inside `Promise::run()`, or while something waits with `EventLoop::getInstance()->runUntilSettled()`. See [Async and Await](tyhp_2600_asyncAndAwait.md) for how the loop starts.

## Writing tasks

### Serialization rules

A task crosses a process boundary twice: the task object goes to the worker, and the result comes back. Both trips use `serialize()` and `unserialize()`, so both must contain only data that survives that round trip.

These work well as task properties and results:

- `int`, `float`, `string`, `bool`, `null`, and arrays of them
- [structs](tyhp_0400_structs.md), which are arrays at run time
- enums
- objects of named classes whose properties follow these same rules, including classes with `__serialize()` / `__unserialize()`

These do not:

- **Closures** and **anonymous classes.** `serialize()` throws, so `runAsync()` throws a `ParallelException` that starts with "Parallel tasks must be serializable." Write a named task class instead.
- **Objects that refuse serialization**, such as `PDO`. `runAsync()` throws the same way.
- **Resources** (open files, sockets, cURL handles). PHP serializes a resource as the integer `0`, so the worker does not receive a usable handle. Pass a path or connection settings and open the resource inside `run()`.

The serialized task and the serialized result are each limited to 16 MiB. A larger task makes `runAsync()` throw a `ParallelException`; a larger result rejects the promise. For big inputs, pass a file path, an ID, or a range and let the worker load the data itself.

### Autoloading task classes

The process that runs the task must be able to load the task class, and your process must be able to load any class in the result.

- **CLI programs:** workers are forks of your process, so every class your program can autoload (or has already loaded) is available to them.
- **Worker service:** the service loads its own `vendor/autoload.php` and the optional `--bootstrap` file, and its workers are forked from it. Run it from the same application checkout as php-fpm so it autoloads the same classes. If a worker cannot load the task class, the promise rejects with a `ParallelException` whose message names the class ("The worker could not load task class …").

If a result contains an object of a class your process cannot load, the promise rejects with "The task result is an object of a class this process cannot load."

### What a task can rely on

- `run()` is an ordinary synchronous method. It runs to completion in the worker.
- A task gets a fresh copy of its own properties. It does not see later changes to the original object, and changes it makes to itself are not sent back. Only the return value comes back.
- Open connections inside `run()`. A database connection, socket, or file handle from your process is not available in the worker.
- Workers are long-lived. Static properties and globals that one task sets stay set for the next task that lands on the same worker, and you cannot choose which worker that is. Do not rely on that state.
- Calling `exit()` or crashing the worker fails the task with a `ParallelException` whose `getRemoteError()` is `null`. The pool replaces the worker.
- Inside a task, `Parallel` is not usable: `Parallel::isAvailable()` returns `false`, and the other `Parallel` methods throw `ParallelUnavailableException`. Code in a task that uses `tyhp/io`'s `Offload`, `PdoConnection`, or `Dns` runs inline in that worker.

### Results and the declared result type

`T` in `ParallelTask<T>` is checked at run time when the result comes back. If `run()` returned a value that does not match `T`, the promise rejects with "The task returned …, which does not match its declared result type." A task declared as `ParallelTask<void>` resolves its promise with `null` when it finishes.

### Result types are inferred

The checker infers `T` from the task class, so the awaited value has a precise type without any type arguments at the call site:

```tyhp
<?tyhp

int $count = await Parallel::runAsync(new CountPrimesTask(0, 1_000_000));

array<string, string> $hashes = await Parallel::forEachAsync(
    $files,
    fn(string $path): Sha256FileTask => new Sha256FileTask($path),
);
```

The same holds for `invokeAsync()` with an array of tasks, such as an `array<int, ParallelTask<int>>`. You can still write some type arguments yourself, for example `forEachAsync<string, int>(…)` for item type `string` and result type `int`; the remaining ones (here the key type) are inferred. See [Generics](tyhp_0500_generics.md).

## API reference

All classes are in the `tyhp/parallel` Composer package. `CancellationToken`, `Promise`, and `OperationCancelledException` come from [tyhp/async](package_async.md).

### `\Tyhp\Parallel`

`final class Parallel` — static entry points for the pool. You never construct it.

:::member[public static function start(int $workers = 4): void]
Prepares this process to run tasks. Calling it is optional, but recommended in CLI programs so that the workers are forked early and with the count you choose.

**Without `TYHP_PARALLEL_SOCKET`** (pool in this process):

- Starts a pool of `$workers` worker processes. When called from the main script (not from inside async code), the workers are forked before `start()` returns. When called from inside an async function, they are forked on the next turn of the event loop.
- Calling it again with the same count does nothing. Calling it with a different count throws `\LogicException` ("The parallel pool is already started with N workers."). This includes the 4-worker pool that `runAsync()` starts on its own when `start()` was not called first.
- After `shutdown()`, `start()` can start a new pool with any count.
- Registers a shutdown function that stops the workers when the script ends.

**With `TYHP_PARALLEL_SOCKET`** (worker service):

- Connects to the service right away. The service chooses the worker count, so `$workers` is ignored.
- Use it as an early check that the service is up.

**Throws**

- `\InvalidArgumentException` — `$workers` is less than 1 (pool mode).
- `\LogicException` — the pool is already running with a different count.
- `ParallelUnavailableException` — called inside a worker; the process is not a CLI process and `TYHP_PARALLEL_SOCKET` is not set; `ext-pcntl` or `ext-posix` is missing; or the service is not accepting connections (the connection attempt waits up to one second).
:::

:::member[public static function serve(string $socketPath, int $workers = 4, int $socketMode = 0660): void]
Runs a worker service: hosts a pool of `$workers` processes and accepts client connections on the Unix socket `$socketPath` until the process receives `SIGTERM` or `SIGINT`. It blocks for the life of the service. Most deployments call it through the `vendor/bin/tyhp-parallel serve` command (described below) instead of directly.

| Parameter | Meaning |
|-----------|---------|
| `$socketPath` | Path of the Unix socket to create. At most 100 bytes. Clients set `TYHP_PARALLEL_SOCKET` to the same path. |
| `$workers` | Number of worker processes. At least 1. |
| `$socketMode` | Permissions applied to the socket file with `chmod()`, between `0` and `0777`. The default `0660` lets the owner and the owner's group connect. |

Behavior:

- Requires the CLI SAPI with `ext-pcntl` and `ext-posix`. The service removes `TYHP_PARALLEL_SOCKET` from its own environment, so it always hosts its pool itself.
- If a socket file already exists at `$socketPath` and nothing answers on it, the stale file is deleted and replaced. If another service is listening there, `serve()` throws.
- Writes `tyhp-parallel listening on <path> with <n> workers` to standard error once it is ready.
- Run it as the php-fpm user, or as a user whose group the php-fpm user belongs to, so that php-fpm can open the socket with the default mode.
- Start it before it opens any database connections. Its workers are forked from it.
- The service forwards each task to a worker without unserializing it. The workers must be able to autoload every task class that clients send.
- When a client disconnects (for example, when a php-fpm request ends), its unfinished tasks are cancelled.
- On `SIGTERM` or `SIGINT` it stops accepting connections, closes client connections (their unfinished tasks fail), stops the workers, deletes the socket file, and returns.

**Throws**

- `\InvalidArgumentException` — `$workers` is less than 1, `$socketMode` is outside `0`–`0777`, or `$socketPath` is empty or longer than 100 bytes.
- `\LogicException` — this process is already running a worker service.
- `ParallelUnavailableException` — not a CLI process, `ext-pcntl` or `ext-posix` is missing, or called inside a worker.
- `ParallelException` — another service is already listening on `$socketPath`, or the socket cannot be created ("Could not listen on …").
:::

:::member[public static function shutdown(): void]
Stops using parallel workers in this process and fails every task that has not finished.

- **Pool in this process:** kills the worker processes and waits for them to exit. Queued tasks reject with `ParallelException` ("The parallel pool shut down before the task ran."), and running tasks reject with "The parallel pool shut down while the task was running."
- **Worker service client:** closes this process's connection. In-flight tasks reject with `ParallelException` ("The connection to the parallel worker service closed."). The service keeps running for its other clients and cancels this client's unfinished tasks.

Safe to call more than once, and safe to call when nothing was started. The package already calls it from a shutdown function when the script ends, so you only need it to release workers early (for example in a long-running program that has finished its parallel phase) or in tests. A later `start()` or `runAsync()` starts again from scratch.
:::

:::member[public static function isAvailable(): bool]
Returns `true` when `runAsync()` can send work to another process:

- `TYHP_PARALLEL_SOCKET` names a worker service, or
- this is a CLI process (`cli` or `phpdbg` SAPI) where `pcntl_fork()` and `posix_kill()` exist.

Returns `false` inside a worker, in a non-CLI process without `TYHP_PARALLEL_SOCKET`, and in a CLI process that lacks either function (for example because `ext-pcntl` is not loaded or `pcntl_fork` is listed in `disable_functions`).

It does not contact a configured service. A service that is down still makes `runAsync()` fail with `ParallelUnavailableException`. Call `start()` when you need to know that the service is reachable.

Use it to choose between running a task in a worker and calling its `run()` method directly (see the password-hashing example under *Worked examples*).
:::

:::member[public static function runAsync<T extends __Awaited<void|mixed>>(ParallelTask<T> $task, ?CancellationToken $token = null): Promise<T>]
Queues one task and returns a promise of its result. In a CLI program without `start()`, the first call starts a pool of 4 workers.

| Parameter | Meaning |
|-----------|---------|
| `$task` | The task to run. It is serialized before this method returns. |
| `$token` | Optional cancellation. A token that is already cancelled returns a rejected promise without queueing anything. Cancelling later removes a queued task, or kills the worker running it and starts a replacement. |

**Returns** `Promise<T>`, which resolves with the value `run()` returned.

**Throws immediately** (from the call itself):

- `ParallelException` — the task cannot be serialized, or it is larger than 16 MiB once serialized.
- `ParallelUnavailableException` — called inside a worker; no worker service is configured and this is not a CLI process with `ext-pcntl` and `ext-posix`; or the configured service is not accepting connections.

**Rejects with:**

- `ParallelException` with a remote error — `run()` threw. `getRemoteError()` describes the exception.
- `ParallelException` without a remote error — the worker exited or crashed, the pool shut down, or the service connection closed.
- `ParallelException` — the result does not match `T`, cannot be unserialized, or is an object of a class this process cannot load.
- `OperationCancelledException` — `$token` was cancelled before the task finished.

When you write `await Parallel::runAsync(...)` inside a `try` block, the immediate throws and the rejections are caught by the same `catch`.
:::

:::member[async public static function forAsync<T extends __Awaited<void|mixed>>(int $fromInclusive, int $toExclusive, callable(int): ParallelTask<T> $factory, ?CancellationToken $token = null): array<int, T>]
Runs one task for every index from `$fromInclusive` up to, but not including, `$toExclusive`, and resolves with the results keyed by that index. The call returns `Promise<array<int, T>>`.

| Parameter | Meaning |
|-----------|---------|
| `$fromInclusive` | First index. |
| `$toExclusive` | One past the last index. When it equals `$fromInclusive`, the result is an empty array. |
| `$factory` | Builds the task for an index. It runs in your process, once per index in ascending order, before any task is queued. |
| `$token` | Optional cancellation for the whole run. |

The keys are the indices themselves, so `forAsync(1, 4, …)` resolves with keys `1`, `2`, and `3`. Use `\array_values()` if you need a list that starts at 0.

Fails fast like `invokeAsync()`: the first task that fails cancels the others, and its exception is thrown.

**Rejects with** `\InvalidArgumentException` when `$fromInclusive` is greater than `$toExclusive`, any exception thrown by `$factory`, and everything listed for `invokeAsync()`.
:::

:::member[async public static function forEachAsync<TItem, TResult extends __Awaited<void|mixed>, TKey extends int|string = int|string>(array<TKey, TItem> $items, callable(TItem): ParallelTask<TResult> $factory, ?CancellationToken $token = null): array<TKey, TResult>]
Builds one task per item and runs them on the pool. Resolves with the results under the same keys, in the same order, as `$items`. The call returns `Promise<array<TKey, TResult>>`.

| Parameter | Meaning |
|-----------|---------|
| `$items` | The inputs. List keys and string keys are both kept. |
| `$factory` | Builds the task for one item. It runs in your process, once per item in input order, before any task is queued. It receives the item, not the key. |
| `$token` | Optional cancellation for the whole run. |

Fails fast like `invokeAsync()`.

**Rejects with** any exception thrown by `$factory`, and everything listed for `invokeAsync()`.
:::

:::member[async public static function invokeAsync<T extends __Awaited<void|mixed>, TKey extends int|string = int|string>(array<TKey, ParallelTask<T>> $tasks, ?CancellationToken $token = null): array<TKey, T>]
Runs every task in `$tasks` and resolves with the results under the same keys, in the same order as the input. The call returns `Promise<array<TKey, T>>`. An empty array resolves with an empty array.

**Fail-fast:** when one task fails, the others are cancelled (queued ones are removed, running ones have their workers killed and replaced), and the first failure is thrown. Cancellations caused by that first failure are not reported in its place.

**Cancellation:** when `$token` is cancelled, every task is cancelled and `OperationCancelledException` is thrown. A token that is already cancelled throws before anything is queued.

**Rejects with** the first task failure (usually a `ParallelException`, see `runAsync()`), anything `runAsync()` throws immediately for one of the tasks (the tasks queued before it are cancelled), or `OperationCancelledException`.
:::

### `\Tyhp\ParallelTask<T>`

:::member[interface ParallelTask<T extends void|mixed = mixed>]
One unit of work for a worker process. Implement it with a named, serializable class:

- `runAsync()` serializes the object once, when the task is queued, and the worker runs an unserialized copy. Changing the object afterward does not affect that run.
- Its properties and the value `run()` returns must be serializable (see *Serialization rules* above).
- The process that runs it must be able to autoload the class (see *Autoloading task classes* above).
- The copy does not share the caller's objects, sockets, or database connections.

`T` is the result type. It defaults to `mixed`, and `void` is allowed for tasks that return nothing.
:::

:::member[public function run(): T]
Does the work inside the worker and returns the result.

- When it returns, the caller's promise resolves with that value, after the result type check described in *Results and the declared result type*.
- When it throws, the promise rejects with a `ParallelException` whose `getRemoteError()` describes the exception.
- When it calls `exit()` or the worker crashes, the task fails with a `ParallelException` without a remote error, and the pool starts a new worker.
:::

### `\Tyhp\ParallelRemoteError`

:::member[type ParallelRemoteError = struct { string $class = ''; string $message = ''; int $code = 0; string $file = ''; int $line = 0; string $trace = ''; }]
A copy of an exception that was thrown inside a worker, returned by `ParallelException::getRemoteError()`. It is a [struct](tyhp_0400_structs.md): plain data, read with `$remote->class`, `$remote->trace`, and so on. In emitted PHP it is an array (`$remote['class']`).

| Field | Contents |
|-------|----------|
| `$class` | Fully qualified class name of the exception, from `get_class()`. |
| `$message` | The exception message, cut to 64 KiB. |
| `$code` | The exception code when it is an `int`; otherwise `0`. (For example, `PDOException` codes are strings and arrive as `0`.) |
| `$file` | File where the exception was created, in the worker. |
| `$line` | Line where the exception was created. |
| `$trace` | The worker's `getTraceAsString()`, cut to 32 KiB. |

Only the thrown exception itself is described. Its `getPrevious()` chain is not included.
:::

### `\Tyhp\Exceptions\ParallelException`

`class ParallelException extends \RuntimeException` — a task failed, or the pool could not deliver it. It is the base class of `ParallelUnavailableException`.

The original exception object stays in the worker. What you receive is a `ParallelException` that describes it, so `catch (MyDomainException $e)` around `await` never matches a task's exception. Catch `ParallelException` and inspect `getRemoteClass()` or `getRemoteError()` instead.

When the task threw, the message has the form `<class>: <message> in <file>:<line>` (for example `RuntimeException: boom in /app/src/Tasks/ImportTask.php:42`), and `getCode()` is `0`. Use `getRemoteError()->code` for the worker's exception code.

:::member[public function __construct(string $message, ?ParallelRemoteError $remoteError = null, ?\Throwable $previous = null): void]
Creates the exception. The package constructs it for you; constructing one yourself is mainly useful in tests, for example to fake a failed task. The exception code is always `0`.
:::

:::member[public function getRemoteError(): ?ParallelRemoteError]
Returns the description of the exception thrown inside the worker. Returns `null` when the task did not throw: the worker exited or crashed, the pool shut down, the service connection failed, the task could not be serialized, or the result failed the type check.
:::

:::member[public function getRemoteClass(): string]
Returns the class name of the exception thrown inside the worker (the `class` field of `getRemoteError()`), or `''` when there is no remote error. Compare it with `::class` constants to react to specific failures, for example `$e->getRemoteClass() === \JsonException::class`.
:::

### `\Tyhp\Exceptions\ParallelUnavailableException`

`final class ParallelUnavailableException extends ParallelException` — this process cannot run a parallel task right now. A CLI program needs `ext-pcntl` and `ext-posix`; any other SAPI needs `TYHP_PARALLEL_SOCKET` pointing at a running worker service. It is also thrown when `Parallel` is used inside a worker. `getRemoteError()` is always `null`.

Catch it to fall back to running the work inline, or to show a "try again later" error while the service restarts.

:::member[public function __construct(string $message): void]
Creates the exception with a message and no remote error.
:::

### The `TYHP_PARALLEL_SOCKET` environment variable

:::member[TYHP_PARALLEL_SOCKET=<path>]
When set to a non-empty value, `Parallel` sends tasks to the worker service listening on that Unix socket instead of forking a pool in this process. It is read with `getenv()` each time a `Parallel` method needs it, in every SAPI.

- Set it for php-fpm in the pool configuration with `env[TYHP_PARALLEL_SOCKET] = <path>`, or call `\putenv('TYHP_PARALLEL_SOCKET=<path>')` before the first `Parallel` call.
- `tyhp-parallel serve` uses it as the default for `--socket`.
- The service removes it from its own environment, so it never connects to itself.
:::

### Command line: `vendor/bin/tyhp-parallel`

:::member[vendor/bin/tyhp-parallel serve [--socket=<path>] [--workers=<n>] [--mode=<octal>] [--bootstrap=<file>]]
Starts the worker service for php-fpm and other processes that cannot fork. It loads Composer's `vendor/autoload.php` from the project that installed the package, then the optional bootstrap file, then calls `Parallel::serve()`. It runs in the foreground until it receives `SIGTERM` or `SIGINT`.

| Option | Default | Meaning |
|--------|---------|---------|
| `--socket=<path>` | `TYHP_PARALLEL_SOCKET` | Socket path. Required when the environment variable is not set. |
| `--workers=<n>` | `4` | Number of worker processes. Must be a positive integer. |
| `--mode=<octal>` | `0660` | Socket file permissions, as three octal digits with an optional leading `0` (`660` or `0660`). |
| `--bootstrap=<file>` | none | PHP file to `require` after the autoloader and before the workers start. |

`vendor/bin/tyhp-parallel --help` (also `-h` or `help`) prints the usage text and exits with status 0. A missing or unknown command, an unknown option, an invalid value, a missing bootstrap file, a missing `vendor/autoload.php`, or an error from `Parallel::serve()` prints a message to standard error and exits with status 1. After a clean stop on `SIGTERM` or `SIGINT` the command exits normally.
:::

## Cancellation

Every `Parallel` call that runs tasks takes an optional `CancellationToken` from [tyhp/async](package_async.md). Create a `CancellationTokenSource`, pass `$source->getToken()`, and call `$source->cancel()` (or pass a timeout in milliseconds to the source's constructor).

What cancelling does depends on where the task is:

- **Not queued yet** (the token was already cancelled): `runAsync()` returns a rejected promise and `invokeAsync()` throws before anything is queued.
- **Queued:** the task is removed from the queue. No worker is affected.
- **Running:** the worker running it is killed with `SIGKILL` and a new worker is started in its place. In service mode, the client tells the service to cancel, and the service does the same.

In every case the promise rejects with `\Tyhp\Exceptions\OperationCancelledException`, without waiting for the task to finish.

:::warning
A cancelled task gets no chance to clean up. Its `finally` blocks, destructors, and shutdown functions do not run, and a half-written file stays half-written. Design tasks so that being killed is harmless: write to a temporary file and rename it at the end, or do the final write in your own process with the returned data. A database transaction the task had open is rolled back by the database server when the killed worker's connection closes.
:::

A deadline for one task:

```tyhp
<?tyhp

namespace App\Usage;

use App\Tasks\CountPrimesTask;
use Tyhp\CancellationTokenSource;
use Tyhp\Exceptions\OperationCancelledException;
use Tyhp\Parallel;

/** Returns null when the count takes longer than two seconds. */
async function countWithDeadline(int $limit): ?int {
    $cts := new CancellationTokenSource(2000);
    try {
        return await Parallel::runAsync(new CountPrimesTask(0, $limit), $cts->getToken());
    } catch (OperationCancelledException $e) {
        return null;
    }
}
```

`$cts := …` disposes the source when the function returns; see [Disposables](tyhp_2300_disposables.md).

## Fail-fast and key preservation

`forAsync()`, `forEachAsync()`, and `invokeAsync()` share the same rules.

**They wait for every task.** The promise resolves only when every task has succeeded.

**They fail fast.** As soon as one task fails, the remaining tasks are cancelled: queued tasks are dropped and running tasks have their workers killed and replaced. The first failure is what you catch. A failure is not hidden by the cancellations it caused. When you cancel the whole call with your own token, you get `OperationCancelledException` instead.

**They keep keys and order.** The result array has the same keys in the same order as the input, regardless of which task finished first:

| Call | Result keys |
|------|-------------|
| `forAsync(1, 4, $factory)` | `1`, `2`, `3` |
| `forEachAsync([10, 20, 30], $factory)` | `0`, `1`, `2` |
| `forEachAsync(['a' => 1, 'b' => 2], $factory)` | `'a'`, `'b'` |
| `invokeAsync(['price' => $t1, 'weight' => $t2])` | `'price'`, `'weight'` |

If you want every outcome rather than the first failure, call `runAsync()` for each task and combine the promises with `Promise::allSettled()` from [tyhp/async](package_async.md).

## Error reporting

| What happened | What you see | `getRemoteError()` |
|---------------|--------------|--------------------|
| `run()` threw | Promise rejects with `ParallelException` (`<class>: <message> in <file>:<line>`) | Describes the exception |
| Worker could not load the task class | Promise rejects with `ParallelException` ("The worker could not load task class …") | Describes the loading error |
| Result not serializable, or larger than 16 MiB | Promise rejects with `ParallelException` | Describes the error from the worker |
| `run()` called `exit()`, or the worker crashed | Promise rejects with `ParallelException` ("The worker exited before it finished the task.") | `null` |
| Result does not match `T` | Promise rejects with `ParallelException` ("The task returned …, which does not match its declared result type.") | `null` |
| Result contains a class this process cannot load | Promise rejects with `ParallelException` | `null` |
| `shutdown()` or script end while the task was queued or running | Promise rejects with `ParallelException` | `null` |
| Worker service connection closed | Promise rejects with `ParallelException` | `null` |
| Your cancellation token was cancelled | Promise rejects with `OperationCancelledException` | not a `ParallelException` |
| Task not serializable, or larger than 16 MiB | `runAsync()` throws `ParallelException` | `null` |
| No way to run tasks (not CLI and no socket, missing extensions, service down, or inside a worker) | `runAsync()` throws `ParallelUnavailableException` | `null` |

A typical handler logs the worker's details and rethrows:

```tyhp
<?tyhp

try {
    array<string, ColumnStats> $stats = await Parallel::invokeAsync($tasks);
} catch (ParallelException $e) {
    ?ParallelRemoteError $remote = $e->getRemoteError();
    if ($remote !== null) {
        \error_log(
            'A stats task threw ' . $remote->class . ' at ' . $remote->file . ':' . (string) $remote->line
            . "\n" . $remote->trace
        );
    } else {
        \error_log('A stats task did not finish: ' . $e->getMessage());
    }
    throw $e;
}
```

The file and line in a remote error point at the emitted PHP that ran in the worker.

## Running under php-fpm: the worker service

php-fpm workers do not fork. Instead, a long-running CLI process hosts the pool, and each php-fpm worker connects to it over a Unix socket. Application code does not change: requests call the same `Parallel` methods and `await` the results.

### 1. Start the service

From the application's root directory (the one that contains `vendor/`):

```bash
vendor/bin/tyhp-parallel serve --socket=/run/tyhp-parallel/app.sock --workers=8
```

```text
tyhp-parallel listening on /run/tyhp-parallel/app.sock with 8 workers
```

Choose `--workers` from the number of CPU cores you want to give to background work. Tasks from every connected php-fpm worker share this pool, so the number of tasks running at once never exceeds `--workers`. Additional tasks wait in the queue.

The directory of the socket must exist and be writable by the service user. Keep the path at 100 bytes or less.

### 2. Point php-fpm at the socket

Set the environment variable in the php-fpm pool configuration and reload php-fpm:

```ini
; for example /etc/php/8.4/fpm/pool.d/www.conf
env[TYHP_PARALLEL_SOCKET] = /run/tyhp-parallel/app.sock
```

Alternatively, call `\putenv('TYHP_PARALLEL_SOCKET=/run/tyhp-parallel/app.sock')` in your front controller before any `Parallel` call.

### 3. Permissions

The socket is created with mode `0660`, so only its owner and group can connect. Either run the service as the php-fpm user (for example `www-data`), or run it as a user whose group the php-fpm user belongs to. Use `--mode` only if you need different permissions.

:::danger
Anyone who can connect to the socket can make the workers unserialize arbitrary data and run any task class the service can autoload, with the service user's permissions. Keep the socket in a directory that only the application can reach, and do not make it world-writable.
:::

### 4. Bootstrap file (optional)

`--bootstrap=<file>` requires one PHP file after Composer's autoloader and before the workers are forked, so everything it sets up is inherited by every worker. Use it to register an autoloader that Composer does not know about, set `ini` values, or set the default time zone. Do not open database connections in it. Give an absolute path; a relative path is resolved against the service's working directory.

```php
<?php
// /var/www/app/config/parallel-bootstrap.php

\date_default_timezone_set('UTC');
\ini_set('memory_limit', '512M');

\spl_autoload_register(static function (string $class): void {
    $file = __DIR__ . '/../legacy/' . \str_replace('\\', '/', $class) . '.php';
    if (\is_file($file)) {
        require $file;
    }
});
```

### 5. Keep it running

The service runs in the foreground and stops cleanly on `SIGTERM` or `SIGINT`, so any process supervisor can manage it. Run it from the same checkout that php-fpm serves, and restart it when you deploy new code so its workers load the new task classes.

A systemd unit:

```ini
# /etc/systemd/system/tyhp-parallel.service
[Unit]
Description=Tyhp parallel worker service
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/var/www/app
RuntimeDirectory=tyhp-parallel
ExecStart=/usr/bin/php /var/www/app/vendor/bin/tyhp-parallel serve --socket=/run/tyhp-parallel/app.sock --workers=8 --bootstrap=/var/www/app/config/parallel-bootstrap.php
Restart=always

[Install]
WantedBy=multi-user.target
```

`RuntimeDirectory=` creates `/run/tyhp-parallel` owned by the service user. systemd stops services with `SIGTERM` by default.

A Supervisor program (create the socket directory yourself, owned by `www-data`):

```ini
; /etc/supervisor/conf.d/tyhp-parallel.conf
[program:tyhp-parallel]
command=/usr/bin/php /var/www/app/vendor/bin/tyhp-parallel serve --socket=/run/tyhp-parallel/app.sock --workers=8
directory=/var/www/app
user=www-data
autostart=true
autorestart=true
stopsignal=TERM
redirect_stderr=true
stdout_logfile=/var/log/tyhp-parallel.log
```

You can also host the service from your own CLI script by calling `Parallel::serve()` after loading the autoloader.

### How requests use the service

- Each php-fpm request that uses `Parallel` opens one connection to the service and reuses it for all of its tasks.
- When the request ends, the connection closes and the service cancels any of that request's tasks that are still queued or running. Await the results you need before the response is sent; for work that must outlive the request, use a job queue and a CLI consumer.
- If the service is down or restarting, `runAsync()` throws `ParallelUnavailableException`, and in-flight tasks fail with `ParallelException`. Call `Parallel::start()` early in the request when you want to detect this before doing anything else:

```tyhp
<?tyhp

namespace App\Usage;

use Tyhp\Exceptions\ParallelUnavailableException;
use Tyhp\Parallel;

function serviceIsUp(): bool {
    try {
        Parallel::start();
        return true;
    } catch (ParallelUnavailableException $e) {
        \error_log($e->getMessage());
        return false;
    }
}
```

## Worked examples

These examples reuse `CountPrimesTask` from *Getting started* and define the other task classes they need.

### Hashing passwords during a bulk import

bcrypt is deliberately slow, so hashing a few hundred passwords one after another can take a minute. This import runs the hashes on the pool when one is available and falls back to hashing inline when it is not, for example in a php-fpm process without `TYHP_PARALLEL_SOCKET`.

```tyhp
<?tyhp

namespace App\Tasks;

use Tyhp\ParallelTask;

/** Hashes one password with bcrypt. */
final class HashPasswordTask implements ParallelTask<string> {
    public function __construct(
        private readonly string $password,
        private readonly int $cost = 12,
    ) {}

    public function run(): string {
        return \password_hash($this->password, \PASSWORD_BCRYPT, ['cost' => $this->cost]);
    }
}
```

```tyhp
<?tyhp

namespace App\Usage;

use App\Tasks\HashPasswordTask;
use Tyhp\Parallel;
use Tyhp\Promise;

/** Keys are e-mail addresses; values are plain-text passwords. */
async function hashPasswords(array<string, string> $passwords): array<string, string> {
    if (!Parallel::isAvailable()) {
        array<string, string> $hashes = [];
        foreach ($passwords as string $email => string $password) {
            $hashes[$email] = (new HashPasswordTask($password))->run();
        }
        return $hashes;
    }

    return await Parallel::forEachAsync(
        $passwords,
        fn(string $password): HashPasswordTask => new HashPasswordTask($password),
    );
}

function importUsers(array<string, string> $passwords): array<string, string> {
    return Promise::run(async fn(): array<string, string> => await hashPasswords($passwords));
}
```

The result keeps the e-mail keys, so `$hashes[$email]` lines up with the input without any bookkeeping. Calling `run()` directly is a convenient fallback because a task is an ordinary object.

### Checksumming files with string keys

Pass paths, not file contents: each worker reads its own file, so only a short string crosses the process boundary in each direction.

```tyhp
<?tyhp

namespace App\Tasks;

use Tyhp\ParallelTask;

/** Returns the SHA-256 checksum of one file. */
final class Sha256FileTask implements ParallelTask<string> {
    public function __construct(private readonly string $path) {}

    public function run(): string {
        string|false $hash = @\hash_file('sha256', $this->path);
        if ($hash === false) {
            throw new \RuntimeException('Cannot read ' . $this->path);
        }
        return $hash;
    }
}
```

```tyhp
<?tyhp

namespace App\Usage;

use App\Tasks\Sha256FileTask;
use Tyhp\Parallel;

/** Keys are display names; values are paths. Resolves with display name => checksum. */
async function checksums(array<string, string> $files): array<string, string> {
    return await Parallel::forEachAsync(
        $files,
        fn(string $path): Sha256FileTask => new Sha256FileTask($path),
    );
}
```

If one file cannot be read, the whole call rejects with a `ParallelException` whose remote error is the `RuntimeException`, and the other checksums are cancelled.

### Summarizing CSV columns with a struct result

Each task reads the same CSV file and summarizes one column. The result type is a struct, which travels back as an array and is checked against `ColumnStats` when it arrives.

```tyhp
<?tyhp

namespace App\Tasks;

use Tyhp\ParallelTask;

type ColumnStats = struct {
    int $count = 0;
    float $min = 0.0;
    float $max = 0.0;
    float $mean = 0.0;
};

/** Reads one numeric column of a CSV file and summarizes it. */
final class ColumnStatsTask implements ParallelTask<ColumnStats> {
    public function __construct(
        private readonly string $csvPath,
        private readonly int $column,
    ) {}

    public function run(): ColumnStats {
        $handle = @\fopen($this->csvPath, 'r');
        if ($handle === false) {
            throw new \RuntimeException('Cannot open ' . $this->csvPath);
        }

        int $count = 0;
        float $sum = 0.0;
        float $min = \INF;
        float $max = -\INF;
        try {
            mixed $row = \fgetcsv($handle, null, ',', '"', '\\');
            while (\is_array($row)) {
                mixed $cell = $row[$this->column] ?? null;
                if (\is_numeric($cell)) {
                    float $value = (float) $cell;
                    $count++;
                    $sum += $value;
                    $min = \min($min, $value);
                    $max = \max($max, $value);
                }
                $row = \fgetcsv($handle, null, ',', '"', '\\');
            }
        } finally {
            \fclose($handle);
        }

        if ($count === 0) {
            return new ColumnStats();
        }
        return new ColumnStats() with [
            count => $count,
            min => $min,
            max => $max,
            mean => $sum / $count,
        ];
    }
}
```

```tyhp
<?tyhp

namespace App\Usage;

use App\Tasks\ColumnStats;
use App\Tasks\ColumnStatsTask;
use Tyhp\Exceptions\ParallelException;
use Tyhp\Parallel;
use Tyhp\ParallelRemoteError;
use Tyhp\ParallelTask;

async function summarize(string $csvPath): array<string, ColumnStats> {
    array<string, ParallelTask<ColumnStats>> $tasks = [
        'price' => new ColumnStatsTask($csvPath, 2),
        'quantity' => new ColumnStatsTask($csvPath, 3),
        'weight' => new ColumnStatsTask($csvPath, 5),
    ];

    try {
        return await Parallel::invokeAsync($tasks);
    } catch (ParallelException $e) {
        ?ParallelRemoteError $remote = $e->getRemoteError();
        if ($remote !== null) {
            \error_log(
                'A stats task threw ' . $remote->class . ' at ' . $remote->file . ':' . (string) $remote->line
                . "\n" . $remote->trace
            );
        } else {
            \error_log('A stats task did not finish: ' . $e->getMessage());
        }
        throw $e;
    }
}
```

`$stats['price']->mean` is available as soon as the promise resolves. See [The with Keyword](tyhp_2200_withKeyword.md) for building struct values.

### Doing other work while a task runs

A running task does not block your process. This program prints a progress dot every half second until the result arrives:

```tyhp
<?tyhp

namespace App\Usage;

use App\Tasks\CountPrimesTask;
use Tyhp\Parallel;
use Tyhp\Promise;

async function countWithProgress(): int {
    Promise<int> $work = Parallel::runAsync(new CountPrimesTask(0, 4_000_000));
    while (!$work->isCompleted()) {
        echo '.';
        await Promise::delay(500);
    }
    echo "\n";
    return await $work;
}
```

It prints about one dot per half second of waiting, then `283146`. The same applies to real work: while the worker counts, the loop can serve `tyhp/io` HTTP requests, database queries, or other fibers. `Promise::delay()` keeps the loop running; PHP's `\sleep()` or `\usleep()` would block it, and the result could not be delivered until the sleep ends.

### Releasing workers early

A long-running CLI program that has a parallel phase followed by a long single-threaded phase can release its workers when the parallel phase ends:

```tyhp
<?tyhp

namespace App\Usage;

use App\Tasks\CountPrimesTask;
use Tyhp\Parallel;
use Tyhp\Promise;

function shutdownExample(): void {
    Parallel::start(2);
    try {
        int $n = Promise::run(async fn(): int => await Parallel::runAsync(new CountPrimesTask(0, 1000)));
        echo (string) $n . "\n";
    } finally {
        Parallel::shutdown();
    }
}
```

### Calling from PHP

Compiled code and plain PHP use the same static methods. In PHP, drive the event loop yourself and read the remote error as an array:

```php
<?php

use Tyhp\EventLoop;
use Tyhp\Exceptions\ParallelException;
use Tyhp\Parallel;

Parallel::start(2);

try {
    $result = EventLoop::getInstance()->runUntilSettled(
        Parallel::runAsync(new \App\Tasks\CountPrimesTask(0, 1_000_000))
    );
    echo $result, "\n";
} catch (ParallelException $e) {
    $remote = $e->getRemoteError();
    echo $remote === null ? $e->getMessage() : $remote['class'] . ': ' . $remote['message'], "\n";
}
```

## Choosing between tyhp/parallel and tyhp/io

Both packages let other work continue while something slow happens. They solve different problems.

| Your code is slow because… | Use |
|----------------------------|-----|
| It waits on HTTP, Redis, PostgreSQL, MySQL, sockets, files, or child processes | [tyhp/io](package_io.md). Its clients wait without blocking, inside your process, with no serialization and no extra processes. |
| It keeps a CPU busy (hashing, compression, parsing, rendering, math) | `tyhp/parallel`. Only a separate process can use another core. |
| It calls a blocking library that has no async version | `tyhp/io`'s `Offload` (which runs the job in a `tyhp/parallel` worker when `Parallel::isAvailable()` is true and inline otherwise), or a `ParallelTask` of your own. `tyhp/io`'s `PdoConnection` and `Dns` work the same way. |

Every task pays for serialization, a trip over a socket, and unserialization in each direction. Give each task enough work to make that worthwhile (a chunk of rows or a range of numbers rather than a single item), and keep inputs and results small.

## Gotchas

- **Start the pool early.** In a CLI program, call `Parallel::start()` before you open database connections or load large data sets. Workers are copies of your process at the moment they are forked. Replacement workers (after a crash, an `exit()`, or a cancellation) are forked from your process as it is at that later moment.
- **Choose the worker count first.** `runAsync()` starts 4 workers when `start()` was not called. Calling `start(8)` afterward throws `\LogicException`.
- **Tasks are snapshots.** The task is serialized when you call `runAsync()` (or when `forAsync()`, `forEachAsync()`, or `invokeAsync()` queue it). Later changes to the object are not seen by the worker, and changes the worker makes are not sent back. Only the return value comes back.
- **Named classes only.** Closures and anonymous classes cannot be serialized. Resources arrive as the integer `0`.
- **Exceptions arrive as descriptions.** A task's exception is reported as a `ParallelException`. Check `getRemoteClass()` rather than catching the original class around `await`.
- **Cancelled and failed-fast tasks are killed.** Their `finally` blocks and destructors do not run. Make tasks safe to interrupt.
- **Workers keep state between tasks.** Static properties and globals persist on a worker from one task to the next. Worker processes also run with PHP's cycle garbage collector turned off; a task that builds large reference cycles can call `\gc_collect_cycles()` before it returns.
- **Results need a running event loop.** Results arrive only while the `tyhp/async` loop runs. Waiting with `\sleep()` blocks the loop.
- **Unfinished work is cancelled at the end.** When a CLI script ends, its workers are stopped and unfinished tasks fail. When a php-fpm request ends, the service cancels that request's unfinished tasks. Neither is a background job queue.
- **No nesting.** A task cannot start more parallel tasks; inside a worker, `Parallel` throws `ParallelUnavailableException`.
- **16 MiB per direction.** A serialized task and a serialized result are each limited to 16 MiB.
- **Output goes to the worker.** `echo` in a task writes to the worker process's standard output. Under the worker service that is the service's log, not the HTTP response. Return data instead of printing it.
## Related pages

- [Async and Await](tyhp_2600_asyncAndAwait.md) — `async`, `await`, `Promise::run()`, and the event loop
- [The tyhp/async Package](package_async.md) — `Promise`, `CancellationTokenSource`, `OperationCancelledException`
- [The tyhp/io Package](package_io.md) — non-blocking I/O and `Offload`
- [Runtime Packages Overview](package_intro.md)
- [Composer Runtime Packages](project_composerPackages.md) — versions and pins for compiled `tyhp/*` helpers
- [Generics](tyhp_0500_generics.md) — type arguments such as `ParallelTask<int>`
- [Structs](tyhp_0400_structs.md) — struct results such as `ParallelRemoteError`
- [Disposables](tyhp_2300_disposables.md) — `:=` for `CancellationTokenSource`
- [Including Files](tyhp_0300_includingFiles.md) — entry points and `build.entryPointAutoloader`
