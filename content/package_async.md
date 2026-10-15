---
title: 'The tyhp/async Package'
---

`tyhp/async` is the runtime behind Tyhp's `async` and `await` keywords. It provides `\Tyhp\Promise<T>`, the fiber-based event loop that runs promises (`\Tyhp\EventLoop`), cooperative cancellation (`CancellationTokenSource` and `CancellationToken`), timeouts, deferred promises, the async iteration and async disposal contracts, and the exceptions those features throw.

This page is the API reference and runtime guide for the package. The language syntax — `async function`, `await`, async closures and blocks, and `foreach (await ...)` — is described in [Async and Await](tyhp_2600_asyncAndAwait.md). Read that page first if you have not written async Tyhp code before.

## Installing

| | |
|---|---|
| Composer name | `tyhp/async` |
| Requires | PHP 8.2 or later, `tyhp/core` |
| Namespaces | `Tyhp`, `Tyhp\Contracts`, `Tyhp\Exceptions` |

`tyhp build` lists `tyhp/async` among the runtime packages your project needs as soon as your code uses `async`, `await`, or the `:=` operator. The package belongs in `require` (emitted PHP loads it at runtime). Version pins follow the same `80N.X.Y` scheme as the other compiled `tyhp/*` helpers; see [Composer Runtime Packages](project_composerPackages.md).

The non-blocking HTTP, process, file, socket, Redis, and database clients in [`tyhp/io`](package_io.md), and the worker pool in [`tyhp/parallel`](package_parallel.md), run on this package's event loop and return its `Promise` type.

### What the package contains

| Area | Types |
|---|---|
| Promises | [`Promise<TReturn>`](#the-promise-class), [`PromiseState`](#promisestate), [`PromiseSettledResult<T>`](#promisesettledresult), [`Deferred<T>`](#deferred) |
| Event loop | [`EventLoop`](#the-event-loop), [`EventLoopTimerItem`, `EventLoopFiberItem`](#queue-entry-classes) |
| Cancellation | [`CancellationTokenSource`](#cancellationtokensource), [`CancellationToken`](#cancellationtoken) |
| Async iteration | [`Contracts\AsyncIterable<T>`, `Contracts\AsyncIterator<T>`, `Contracts\AsyncKeyValueIterator<TKey, TValue>`](#async-iteration-contracts) |
| Async disposal | [`Contracts\AsyncIsDisposable`, `DisposableScope`, `DisposableHelper`](#async-disposal) |
| Exceptions | [`Exceptions\TimeoutException`, `Exceptions\OperationCancelledException`, `Exceptions\InvalidPromiseStateException`, `Exceptions\AsyncContextException`](#exceptions) |

## Getting started

The declared return type of an `async` function is the type you get when you `await` it. Calling the function schedules the work and returns a `Promise` of that type; `await` suspends the current async function until the promise settles and then gives you the value.

In an application, the simplest way to run async code is top-level `await` in an entry-point file. The compiler wraps the file's top-level code in the event loop for you:

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

async function loadGreeting(string $name): string {
    await Promise::delay(100);
    return "Hello, {$name}!";
}

string $greeting = await loadGreeting('Ada');
echo $greeting, "\n"; // Hello, Ada!
```

Promises start running as soon as they are created, so you get concurrency by starting several operations before you await any of them. `Promise::all()` then collects the results:

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

async function fetchPrice(string $sku): int {
    await Promise::delay(50); // stands in for a network call
    return \strlen($sku) * 100;
}

async function totalFor(array<string> $skus): int {
    array<Promise<int>> $pending = [];
    foreach ($skus as $sku) {
        $pending[] = fetchPrice($sku); // all requests start here
    }

    array<int> $prices = await Promise::all($pending);

    int $total = 0;
    foreach ($prices as $price) {
        $total += $price;
    }
    return $total;
}
```

The three `fetchPrice()` calls wait concurrently, so `totalFor(['A-1', 'B-22', 'C-333'])` takes about 50 ms rather than 150 ms.

From an ordinary (non-async) function, hand the promise to the event loop and block until it settles:

```tyhp
<?tyhp

namespace App;

use Tyhp\EventLoop;

function printTotal(): void {
    int $total = EventLoop::getInstance()->run(totalFor(['A-1', 'B-22', 'C-333']));
    echo "Total: {$total}\n"; // Total: 1200
}
```

## How the runtime works

### Promises and fibers

A `Promise<T>` represents work that finishes later with a value of type `T` (it *fulfills*) or with an exception (it *rejects*). `T` is always the *settled* type: a promise never holds another promise, so `Promise<Promise<int>>` is rejected by the compiler (see [Settled types](#settled-types)). Once a promise leaves the pending state it never changes again. Its current state is a [`PromiseState`](#promisestate).

Each `async` function call, async closure call, and `async { ... }` block creates a promise backed by its own PHP `\Fiber`. `await` suspends that fiber until the awaited promise settles. All fibers run on a single thread and are scheduled cooperatively by the event loop: a fiber runs without interruption until it awaits a pending promise or returns.

Two consequences follow from that model:

- **Code between two `await`s runs atomically.** No other async code can observe or change shared state in the middle of it, so you do not need locks for in-process data.
- **Long synchronous work blocks everything.** A CPU-heavy loop, or a blocking PHP call such as `\file_get_contents()`, `\sleep()`, PDO, or plain curl, stops every other fiber until it returns. Use the non-blocking clients in [`tyhp/io`](package_io.md), or insert [`Promise::yield()`](#timing-and-yielding) into long loops.

### When async code starts running

Calling an async function does **not** run any of its body immediately. The call creates the promise, queues the fiber on the event loop, and returns. The body starts the next time the loop drains its queue — which happens when the calling fiber awaits something or finishes.

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

async function inner(): int {
    echo "3. inner body\n";
    return 1;
}

async function outer(): void {
    echo "1. outer start\n";
    Promise<int> $p = inner();     // queued, not started
    echo "2. after calling inner\n";
    int $v = await $p;             // outer suspends; inner runs now
    echo "4. after await, got {$v}\n";
}
```

The lines print in the numbered order: the body of `inner()` runs only after `outer()` reaches `await`. Arguments, validation, and early token checks inside `async` methods therefore surface as a **rejected promise** when you await it, not as an exception at the call site. For example, `Promise::delay(-1)` returns a promise that rejects with `\InvalidArgumentException`.

`await` on a promise that is already settled returns (or throws) immediately without suspending. When an awaited promise settles later, the waiting fiber is queued to resume; it continues on the loop's next queue drain rather than inside the code that settled the promise.

### The event loop cycle

There is one event loop per PHP process, returned by `EventLoop::getInstance()`. While it runs, it repeats this cycle:

1. **Fibers and microtasks.** Start, resume, or throw into every queued fiber. Then run queued microtasks one at a time (`EventLoop::queueMicrotask()` / `defer()`), draining newly queued fibers after each one. Microtasks added during this phase run in the same phase.
2. **Timers.** Run every timer whose due time has passed (`EventLoop::delay()`, `interval()`, and everything built on them, such as `Promise::delay()`). Intervals are rescheduled after they fire.
3. **I/O poll.** Check registered read and write streams with a non-blocking `\stream_select()` and call the callbacks of streams that are ready.
4. **Exit or wait.** If the root promise has settled and nothing is immediately runnable, stop. Otherwise, if nothing is runnable yet, block until the next timer is due or a registered stream becomes ready (at most one second per wait), then repeat.

Fibers and microtasks always run before timers, and timers before I/O callbacks:

```tyhp
<?tyhp

namespace App;

use Tyhp\EventLoop;

function showOrder(): void {
    EventLoop $loop = EventLoop::getInstance();
    $loop->delay(0, function (): void { echo "timer\n"; });
    $loop->queueMicrotask(function (): void { echo "microtask\n"; });
    $loop->defer(function (): void { echo "deferred\n"; });

    while ($loop->tick()) {
    }
    // Prints: microtask, deferred, timer
}
```

### When the loop stops

`EventLoop::run()` (and the top-level `await` wrapper and `Promise::run()`, which use it) returns once the root promise has settled and no work is immediately runnable. **Timers that are not yet due, intervals, and stream watchers do not keep it running.** A promise you started but never awaited (fire-and-forget) is abandoned mid-flight if the root finishes first:

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

async function sendAuditLog(string $message): void {
    await Promise::delay(500);
    echo "audit: {$message}\n";
}

async function handle(): void {
    sendAuditLog('user signed in'); // not awaited
    echo "handled\n";
}

// await handle(); prints "handled" and returns at once — the audit line never prints.
```

Abandoned work stays queued on the process-wide loop and continues the next time the loop runs. Await everything whose completion matters, or collect it with `Promise::all()` / `Promise::allSettled()` before the root finishes.

If the root promise can never settle — for example, it awaits a [`Deferred`](#deferred) that nothing resolves and no timer or stream can resolve it — the loop waits forever. Give such waits a timeout, or pass a [`CancellationToken`](#cancellationtoken) to `EventLoop::run()` / `Promise::run()`: cancelling it while the root is pending shuts the whole loop down and the run throws `OperationCancelledException` (see [`EventLoop::run()`](#eventloop-run)).

### Errors

- An exception thrown inside an async function, async closure, async block, or `then()`/`catch()`/`finally()` handler rejects that promise. `await` rethrows the rejection reason at the await point, so ordinary `try`/`catch` works.
- A rejected promise that nobody awaits or handles is silently discarded. There is no global unhandled-rejection handler.
- An exception thrown from a callback the **loop itself** calls — a timer callback, interval, microtask, stream callback, or a raw fiber that is not owned by a promise — is not turned into a rejection. It propagates out of `EventLoop::run()`, `runUntilSettled()`, `tick()`, `Promise::wait()`, or `Promise::run()` and stops the loop. Catch exceptions inside such callbacks and reject a [`Deferred`](#deferred) instead.

## Running async code from synchronous code

`await` is only legal inside async code. Ordinary functions, PHP scripts, and test methods need one of the following entry points. All of them start (or continue) the single process-wide loop.

| Entry point | Result | Use it when |
|---|---|---|
| Top-level `await` in an application entry file | — | Scripts and CLI commands written in Tyhp |
| `EventLoop::getInstance()->run($promise, $token)` | `T` (typed) | A synchronous Tyhp function needs the value of a promise. The optional token ends the run when cancelled (see [cancellation](#eventloop-run)) |
| `$promise->wait($timeoutMs)` | `mixed` | You need an upper bound on how long to block, or you are calling from PHP |
| `EventLoop::getInstance()->runUntilSettled($promise, $timeoutMs)` | `mixed` | Same as `wait()`; convenient in tests |
| `Promise::run($fn, $token)` | settled `T` (typed) | Run a plain or `async` closure inside the loop and get its value; convenient from PHP. Takes the same optional token |

`EventLoop::run()` keeps running immediately runnable work after the promise settles and stops once the queues are empty. `wait()` and `runUntilSettled()` stop as soon as the promise settles and leave any remaining work queued. Only `run()` (and `Promise::run()`, which uses it) accepts a cancellation token.

:::warning
None of these entry points may be called while the loop is already running — that is, from inside async code or from a timer, microtask, or stream callback. Doing so throws `\LogicException` ("called re-entrantly"). Inside async code, use `await` instead.
:::

### Calling async Tyhp code from PHP

Compiled async functions and methods return `\Tyhp\Promise` objects to PHP callers. Drive them with the same entry points:

```php
<?php

declare(strict_types=1);

require __DIR__ . '/vendor/autoload.php';

use Tyhp\EventLoop;

// Blocks until the promise settles, then returns its value or throws its rejection.
$total = EventLoop::getInstance()->run(\App\totalFor(['A-1', 'B-22']));

// Same, but gives up after two seconds with \Tyhp\Exceptions\TimeoutException.
$total = \App\totalFor(['A-1', 'B-22'])->wait(2000);
```

## The Promise Class

`final class Promise<TReturn extends __Awaited<void|mixed> = __Awaited<mixed>>` in namespace `Tyhp`.

An unparameterized `Promise` means `Promise<mixed>`. `Promise<void>` is the type of async functions that return nothing.

Members marked `async` below return `Promise<__Awaited<T>>` to the caller, where `T` is the declared return type, exactly like your own async functions: the declared type is what `await` gives you.

### Settled types

`TReturn` is bounded by `__Awaited<void|mixed>`, which means a promise's type argument is always an *already-awaited* type. A promise never holds another promise:

- `Promise<Promise<int>>` and `Promise<int|Promise<string>>` are rejected with TYHP4373, and so is `Promise<T>` for a type parameter `T` that is unconstrained (or bounded by `mixed`), because `T` could itself be a promise. `Promise<mixed>`, `Promise<object>`, and `Promise<?int>` are fine.
- Declare your own generic helpers with the same bound — `function collect<T extends __Awaited<void|mixed>>(array<Promise<T>> $promises): …` — so `T` is known to be settled. See [`__Awaited<T>`](tyhp_0150_newTypes.md#type-utility-types).
- The declared return type of an `async` function, method, or closure is read as `__Awaited<R>`, so `async function f(): Promise<int>` is the same as `async function f(): int`: awaiting it gives `int`.
- To pass a promise around as a value, put it inside an array, a class, or a struct, or use a [`Deferred`](#deferred).

Methods in this class that produce a promise from a type parameter, such as `resolved<T>()` and `timeout<T>()`, return `Promise<__Awaited<T>>`.

### Creating promises

You rarely construct promises directly: async functions, async closures, and `async { ... }` blocks create them for you (see [Async Blocks](tyhp_2600_asyncAndAwait.md#async-blocks) for returning a running promise from a method). Use the factories below for already-settled values and [`Deferred`](#deferred) for promises that an outside event settles. Pass the type argument explicitly to `resolve`, `resolved`, `reject`, and `rejected`, as in `Promise::resolved<int>(1)`; without it the result is not assignable to a `Promise<int>` variable.

:::member[public function __construct(callable(): TReturn $executor, bool $immediateResolve = false)]
Creates a promise that runs `$executor` in its own fiber. The fiber is queued on the event loop and starts on the next queue drain, not inside the constructor. The promise fulfills with the executor's return value or rejects with the exception it throws.

When `$immediateResolve` is `true`, no fiber is created: the executor runs synchronously inside the constructor and the promise is fulfilled with its result before the constructor returns. An exception from the executor then propagates out of the constructor instead of rejecting the promise.

The executor receives no arguments. To settle a promise from outside, use [`Deferred`](#deferred) or [`Promise::withResolvers()`](#promise-withresolvers).
:::

:::member[public static function resolve<T extends __Awaited<void|mixed>>(?T $value = null): Promise<T>]
Returns an already-fulfilled promise holding `$value`, without creating a fiber. If `$value` is itself a `Promise`, that same instance is returned unchanged — even if it is still pending. Because `T` must be a settled type, a typed promise argument such as a `Promise<int>` cannot be passed to `resolve()` directly; call `Promise::resolve<mixed>($value)` to accept a value that may or may not be a promise.

When `$value` is omitted or `null`, the promise fulfills with `default(T)` if `T` is `void` or nullable; for any other `T` it throws `InvalidPromiseStateException`.
:::

:::member[public static function resolved<T extends void|mixed = void>(?T $value = null): Promise<__Awaited<T>>]
Returns a new, already-fulfilled promise holding `$value`, without creating a fiber. When `$value` is omitted or `null`, the promise fulfills with `default(T)`. Unlike `resolve()`, it always returns a new promise object, even when `$value` is itself a promise; use `resolve()` when the argument might already be a promise and you want that same instance back.

If `$value` is a promise, the new promise adopts it and settles when `$value` settles, so `Promise::resolved<\Tyhp\Promise<int>>($p)` is a `Promise<int>`.

Specify the type argument explicitly, as in `Promise::resolved<void>()` or `Promise::resolved<int>($count)`.
:::

:::member[public static function reject<T extends __Awaited<void|mixed> = void>(\Throwable $reason): Promise<T>]
Returns an already-rejected promise with `$reason` as its rejection reason, without creating a fiber. Equivalent to `rejected()`.
:::

:::member[public static function rejected<T extends void|mixed = void>(\Throwable $error): Promise<__Awaited<T>>]
Returns an already-rejected promise with `$error` as its rejection reason, without creating a fiber.
:::

<a id="promise-withresolvers"></a>

:::member[public static function withResolvers<T extends void|mixed>(): Deferred<__Awaited<T>>]
Returns a new [`Deferred<T>`](#deferred): a pending promise (`getPromise()`) together with the `resolve()` and `reject()` methods that settle it. Equivalent to `new Deferred<T>()` in Tyhp code.

Plain PHP code cannot pass type arguments, so it should call `Promise::withResolvers()` to get a deferred promise that can be resolved with a value. A bare `new Deferred()` is a `Deferred<void>`, which can only be resolved without a value.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

function factories(): void {
    Promise<int> $one = Promise::resolved<int>(1);
    Promise<string> $two = Promise::resolve<string>('two');
    Promise<void> $done = Promise::resolved<void>();
    Promise<int> $failed = Promise::rejected<int>(new \RuntimeException('Not available'));

    echo $one->getResult(), ' ', $two->getResult(), "\n"; // 1 two
    echo $done->isFulfilled() ? 'done' : 'pending', "\n";  // done
    echo $failed->getState()->value, "\n";                 // rejected
}
```

Already-settled promises are useful for satisfying a `Promise<T>` return type from a cache hit, in test doubles, and when implementing [`AsyncIterator::current()`](#async-iteration-contracts).

### Chaining handlers

`await` is usually clearer than handler chains, but the chaining methods are useful for adapting a promise in an expression or from PHP. Every handler runs inside a new fiber after the source promise settles, and every method returns a new promise.

`then()` is declared as a set of three [source overloads](tyhp_1200_functionOverloads.md), and callers see only these signatures. The first signature that accepts the arguments is used:

```tyhp
<?tyhp

async public function then(null $onFulfilled = null, null $onRejected = null): TReturn;
async public function then(null $onFulfilled, callable(\Throwable): TReturn $onRejected): TReturn;
async public function then<TThenReturn>(callable(TReturn): TThenReturn $onFulfilled, ?callable(\Throwable): TThenReturn $onRejected = null): TThenReturn;
```

:::member[public async function then(...)]
Waits for this promise to settle, then:

- if it fulfilled, calls `$onFulfilled` with the value and fulfills with the handler's return value (or passes the original value through when `$onFulfilled` is `null`);
- if it rejected, calls `$onRejected` with the reason and fulfills with the handler's return value (or passes the rejection through when `$onRejected` is `null`).

An exception thrown by either handler rejects the returned promise. The three overloads give these results:

- `then()` and `then(null, null)` return a `Promise<TReturn>` that settles like this promise.
- `then(null, $onRejected)` takes a handler that returns `TReturn` and returns a `Promise<TReturn>`.
- `then($onFulfilled, $onRejected = null)` takes a handler for the value; the result is a `Promise` of whatever the handler returns (`TThenReturn`, read as a settled type). A rejection handler passed with it must return the same type.
:::

:::member[public function catch(callable(\Throwable): TReturn $onRejected): Promise<TReturn>]
Shorthand for `then(null, $onRejected)`. If this promise rejects, the returned promise fulfills with the handler's result; if it fulfills, the original value passes through unchanged. The handler returns this promise's own value type, so the result keeps the type of the promise `catch()` was called on.
:::

:::member[public async function finally(callable(): void|mixed $onFinally): TReturn]
Calls `$onFinally` once this promise settles, whichever way, then settles the returned promise exactly like the original (same value or same rejection reason). The callback's return value is ignored and is not awaited. If `$onFinally` throws, that exception replaces the original outcome. Returns `Promise<TReturn>` to the caller.
:::

:::member[public async function continueWith<TContinueReturn>(callable(?TReturn, ?\Throwable): TContinueReturn $continuation): TContinueReturn]
Waits for this promise to settle, then calls `$continuation($value, null)` if it fulfilled or `$continuation(null, $error)` if it rejected, and fulfills with the continuation's return value. Use it when one function should handle both outcomes. An exception thrown by the continuation rejects the returned promise. Returns `Promise<TContinueReturn>` to the caller.
:::

```tyhp
<?tyhp

namespace App;

async function priceLabel(string $sku): string {
    string $label = await fetchPrice($sku)
        ->then(fn(int $cents): string => \number_format($cents / 100, 2))
        ->catch(fn(\Throwable $e): string => 'n/a')
        ->finally(function (): void { echo "price lookup finished\n"; });
    return $label;
}

async function describeLookup(string $sku): string {
    return await fetchPrice($sku)->continueWith(
        fn(?int $cents, ?\Throwable $error): string => $error !== null
            ? 'failed: ' . $error->getMessage()
            : 'ok: ' . ($cents ?? 0)
    );
}
```

### Inspecting and blocking

:::member[public function wait(int $timeoutMs = -1): mixed]
Runs the event loop until this promise settles, then returns its value or throws its rejection reason. Use it only from synchronous code. When `$timeoutMs` is greater than zero and the promise is still pending after that many milliseconds, throws `TimeoutException` and leaves the promise pending; zero or a negative value waits without a limit.

Throws `\LogicException` if the loop is already running. Equivalent to `EventLoop::getInstance()->runUntilSettled($this, $timeoutMs)`.
:::

:::member[public function getResult(): TReturn]
Returns the fulfillment value without waiting. Throws the rejection reason if the promise rejected, and `InvalidPromiseStateException` if it is still pending.
:::

:::member[public function getState(): PromiseState]
Returns `PromiseState::Pending`, `PromiseState::Fulfilled`, or `PromiseState::Rejected`.
:::

:::member[public function isCompleted(): bool]
Returns `true` once the promise has fulfilled or rejected.
:::

:::member[public function isFulfilled(): bool]
Returns `true` if the promise fulfilled.
:::

:::member[public function isFaulted(): bool]
Returns `true` if the promise rejected.
:::

:::member[public function getError(): ?\Throwable]
Returns the rejection reason, or `null` if the promise is pending or fulfilled.
:::

### Timing and yielding

:::member[public static async function delay(int $ms, ?CancellationToken $token = null): void]
Returns a `Promise<void>` that fulfills after `$ms` milliseconds, using a timer on the event loop. Rejects with `\InvalidArgumentException` if `$ms` is negative.

If `$token` is already cancelled, the promise rejects with `OperationCancelledException`. If the token is cancelled while the delay is pending, the timer is cancelled and the promise rejects with `OperationCancelledException` straight away.

`await Promise::delay(...)` is the non-blocking replacement for `\sleep()` and `\usleep()`.
:::

:::member[public static function yield(): Promise<void>]
Returns a promise that settles after other already-queued fibers have had a chance to run. `await Promise::yield();` lets sibling tasks make progress during a long CPU-bound loop. It does not wait for timers or I/O; use `yieldTick()` for that.
:::

:::member[public static function yieldTick(): Promise<void>]
Equivalent to `Promise::delay(0)`. Awaiting it lets queued fibers run **and** lets the loop process due timers and poll I/O before the current fiber resumes. Use it when a long-running task should also let timers and streams make progress.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

async function checksum(array<int> $values): int {
    int $sum = 0;
    foreach ($values as $i => $value) {
        $sum = ($sum + $value * 31) % 1_000_003;
        if ($i % 1000 === 0) {
            await Promise::yield(); // let other tasks run every 1000 items
        }
    }
    return $sum;
}
```

:::member[public static function timeout<T extends __Awaited<void|mixed>>(Promise<T> $promise, int $ms, ?CancellationToken $token = null): Promise<__Awaited<T>>]
Returns a promise that settles like `$promise` if it settles within `$ms` milliseconds, and otherwise rejects with `TimeoutException` (message `Operation timed out`, `getTimeoutMs()` returning `$ms`).

A timeout does not stop the underlying operation; it keeps running and its outcome is ignored. Pass a [`CancellationToken`](#cancellation) to the operation itself when it should stop. If `$token` is cancelled first, the returned promise rejects with `OperationCancelledException`. The internal timer stays scheduled until `$ms` elapses even when `$promise` wins; it has no further effect.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Exceptions\TimeoutException;
use Tyhp\Promise;

async function priceOrNull(string $sku): ?int {
    try {
        return await Promise::timeout(fetchPrice($sku), 500);
    } catch (TimeoutException $e) {
        echo 'Price lookup timed out after ', $e->getTimeoutMs(), " ms\n";
        return null;
    }
}
```

### Combining promises

The combinators wait on promises that are **already running**. Passing promises to `all()` or `race()` does not start them or make them concurrent — creating them did that. The combinators only decide how to collect the outcomes.

| Combinator | Fulfills when | Rejects when | Token |
|---|---|---|---|
| `all()` / `whenAll()` | every input fulfilled | an input rejects | `all()` only |
| `allSettled()` | every input settled | never | — |
| `race()` / `whenAny()` | the first input to settle fulfilled | the first input to settle rejected | `race()` only |
| `any()` | the first input fulfills | every input rejected | yes |
| `batch()` | every item processed | an item's promise rejects | yes |

:::member[public static async function all<T extends __Awaited<void|mixed> = mixed>(array<Promise<T>> $promises, ?CancellationToken $token = null): array<T>]
Waits for every promise and fulfills with an array of their values. **Keys are preserved**, so a list gives a list in the same order and a string-keyed array gives the same string keys. An empty array fulfills with `[]`.

`all()` awaits the inputs one at a time in key order. If an input rejects, `all()` rejects with that reason when it reaches that input, which means it first waits for every input before it. The other inputs keep running.

The token is checked before each input is awaited; cancellation is noticed between inputs, not while `all()` is waiting on one. Cancellation rejects with `OperationCancelledException`. Returns `Promise<array<T>>`; the static key type is `int|string` even when you pass a string-keyed array, so assign the result to `array<T>`.
:::

:::member[public static function whenAll<T extends __Awaited<void|mixed> = mixed>(Promise<T> ...$promises): Promise<array<int|string, T>>]
Variadic form of `all()` without a token: `Promise::whenAll($a, $b, $c)`.
:::

:::member[public static async function allSettled<T extends __Awaited<void|mixed> = mixed, TKey extends int|string = int|string>(array<TKey, Promise<T>> $promises): array<TKey, PromiseSettledResult<T>>]
Waits for every promise to settle and fulfills with one [`PromiseSettledResult<T>`](#promisesettledresult) per input, under the same key. It never rejects. Use it when partial success is acceptable and you want to report each failure.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;
use Tyhp\PromiseSettledResult;

async function stockReport(): void {
    array<string, Promise<int>> $requests = [
        'A-1' => fetchStock('A-1'),
        'B-2' => fetchStock('B-2'),
    ];

    array<string, PromiseSettledResult<int>> $outcomes = await Promise::allSettled($requests);

    foreach ($outcomes as $sku => $outcome) {
        if ($outcome->status === 'fulfilled') {
            echo "{$sku}: ", $outcome->value ?? 0, " in stock\n";
        } else {
            echo "{$sku} failed: ", $outcome->reason?->getMessage() ?? 'unknown error', "\n";
        }
    }
}
```

:::member[public static async function race<T extends __Awaited<void|mixed>>(array<Promise<T>> $promises, ?CancellationToken $token = null): __Awaited<T>]
Settles the same way as the first input to settle: fulfills with its value or rejects with its reason. The remaining inputs keep running, and their outcomes are ignored.

Rejects with `\InvalidArgumentException` for an empty array (such a race could never settle). If `$token` is cancelled before any input settles, rejects with `OperationCancelledException` immediately. Returns `Promise<T>`.
:::

:::member[public static function whenAny<T extends __Awaited<void|mixed>>(Promise<T> ...$promises): Promise<__Awaited<T>>]
Variadic form of `race()` without a token: `Promise::whenAny($primary, $fallback)`.
:::

:::member[public static async function any<T extends __Awaited<void|mixed>>(array<Promise<T>> $promises, ?CancellationToken $token = null): __Awaited<T>]
Fulfills with the value of the first input to **fulfill**, ignoring rejections as long as another input can still succeed. If every input rejects, rejects with `\Tyhp\Exceptions\AggregateException` (message `All promises were rejected`) whose `getInnerExceptions()` holds each reason under its input's key. An empty array rejects with an `AggregateException` that has no inner exceptions.

If `$token` is cancelled before an input fulfills, rejects with `OperationCancelledException` immediately. Returns `Promise<T>`.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Exceptions\AggregateException;
use Tyhp\Promise;

async function fastestMirror(): string {
    string $winner = await Promise::race([
        Promise::delay(200)->then(fn(): string => 'eu-west'),
        Promise::delay(10)->then(fn(): string => 'us-east'),
    ]);
    return $winner; // 'us-east'
}

async function firstAvailableStock(): int {
    try {
        return await Promise::any([fetchStock('warehouse-1'), fetchStock('warehouse-2')]);
    } catch (AggregateException $e) {
        foreach ($e->getInnerExceptions() as $reason) {
            echo $reason->getMessage(), "\n";
        }
        return 0;
    }
}
```

:::member[public static async function batch<TItem, TBatchReturn extends __Awaited<void|mixed>>(array<TItem> $items, callable(TItem): Promise<TBatchReturn> $processor, int $concurrency = 5, ?CancellationToken $token = null): array<int, TBatchReturn>]
Calls `$processor` for each item and fulfills with the results, indexed `0, 1, 2, …` in input order (input keys are not kept). Use it to process a large collection without starting every operation at once.

Items are processed in **waves** of up to `$concurrency`: `batch()` starts that many processors, waits until every promise in the wave has settled, then starts the next wave. One slow item therefore holds up the start of the next wave. `$concurrency` must be at least 1; with a smaller value no item ever starts and the call never completes (it also never yields to other tasks). An empty `$items` array fulfills with `[]`.

If a promise in a wave rejects, `batch()` rejects with that reason (the lowest-index failure in the wave) after the wave settles, and later items are never started. If `$processor` returns something other than a `Promise`, `batch()` rejects with `\InvalidArgumentException`. The token is checked before each wave; cancellation rejects with `OperationCancelledException`. Returns `Promise<array<int, TBatchReturn>>`.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

async function stockLevels(array<string> $skus): array<int, int> {
    // At most three lookups in flight at a time.
    return await Promise::batch(
        $skus,
        fn(string $sku): Promise<int> => fetchStock($sku),
        concurrency: 3
    );
}
```

### Adapting generators

:::member[public static async function fromGenerator(\Generator $generator): mixed]
Runs a coroutine-style generator to completion. Each time the generator yields a `Promise`, `fromGenerator()` awaits it and sends the value back into the generator as the result of the `yield` expression; if the promise rejects, the reason is thrown into the generator at that `yield`. Values that are not promises are sent straight back. Fulfills with the generator's return value. Returns `Promise<mixed>`.

Use it to run existing generator-based code (as written for older PHP coroutine libraries) on the Tyhp event loop. New code should use `async` functions.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

function legacyStockCheck(): \Generator {
    int $first = yield fetchStock('A-1');
    int $second = yield fetchStock('B-2');
    return $first + $second;
}

async function runLegacy(): mixed {
    return await Promise::fromGenerator(legacyStockCheck());
}
```

### Running from synchronous code

:::member[public static function run<T extends void|mixed>(callable(): T $fn, ?CancellationToken $token = null): __Awaited<T>]
Creates a promise that runs `$fn` in a fiber, runs the event loop until it settles (see [`EventLoop::run()`](#eventloop-run)), and returns its settled value or throws its rejection reason. `$fn` may be a plain closure, an `async` closure or arrow function, or any callable that returns a `Promise`; a returned promise is awaited, so the result is its value, not the promise. An exception thrown by `$fn`, or the rejection reason of the promise it returns, is rethrown from `run()`.

If `$token` is already cancelled, throws `OperationCancelledException` before `$fn` is called. Otherwise the loop watches the token: cancelling it while the work is still pending shuts the whole event loop down and `run()` throws `OperationCancelledException` (see [`EventLoop::run()`](#eventloop-run) for exactly what is cancelled). Work that has already settled keeps its own result or error. Throws `\LogicException` when called while the loop is running.

`$fn` runs inside a fiber, so PHP code inside it can await with `\Tyhp\Promise::_await()`; this is the form the compiler generates for top-level `await`.
:::

The result is typed as the settled value, so it can be assigned to a plain `T` variable or returned as `T` whether `$fn` is a plain closure or an `async` one. The type argument is inferred from the closure; `Promise::run<int>(…)` is accepted when you want to state it.

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

function answer(): int {
    return Promise::run(async function(): int {
        await Promise::delay(10);
        return 42;
    });
}
```

### Compiler entry points

:::member[public static function _async<T extends void|mixed>(callable(): T $fn): Promise<__Awaited<T>>]
The target the compiler lowers `async` functions, closures, and blocks to. Equivalent to `new Promise<__Awaited<T>>($fn)`. Do not call it from Tyhp code; write `async` instead.
:::

:::member[public static function _await<T extends __Awaited<void|mixed>>(Promise<T> $promise): __Awaited<T>]
The target the compiler lowers `await` to. Returns the value of a fulfilled promise or throws the reason of a rejected one immediately. For a pending promise it suspends the current fiber until the promise settles; outside a fiber it throws `AsyncContextException`. Do not call it from Tyhp code; write `await` instead.
:::

## PromiseState

`enum PromiseState: string` in namespace `Tyhp`. Returned by `Promise::getState()`.

| Case | Value | Meaning |
|---|---|---|
| `PromiseState::Pending` | `'pending'` | Not settled yet |
| `PromiseState::Fulfilled` | `'fulfilled'` | Completed with a value |
| `PromiseState::Rejected` | `'rejected'` | Completed with an exception |

## PromiseSettledResult

`final class PromiseSettledResult<T extends void|mixed = mixed>` in namespace `Tyhp`. One outcome from `Promise::allSettled()`, shaped like the result objects of JavaScript's `Promise.allSettled`.

:::member[public string $status]
`'fulfilled'` or `'rejected'`.
:::

:::member[public ?T $value]
The fulfillment value when `$status` is `'fulfilled'`; otherwise `null`.
:::

:::member[public ?\Throwable $reason]
The rejection reason when `$status` is `'rejected'`; otherwise `null`.
:::

:::member[public function __construct(string $status, ?T $value = null, ?\Throwable $reason = null)]
Creates an outcome. `allSettled()` creates these for you; construct them yourself only in test doubles.
:::

## Deferred

`final class Deferred<T extends __Awaited<void|mixed> = void>` in namespace `Tyhp`.

A `Deferred` pairs a pending promise with the methods that settle it. It is the bridge from callback-style code — timers, stream callbacks, event emitters, message handlers — to promises that async code can `await`. Hand out `getPromise()`, keep the `Deferred`, and call `resolve()` or `reject()` when the outcome is known.

:::member[public function __construct()]
Creates a `Deferred` whose promise stays pending until `resolve()` or `reject()` is called.
:::

:::member[public function getPromise(): Promise<T>]
Returns the promise. Every call returns the same instance.
:::

:::member[public function resolve(?T $value = null): void]
Fulfills the promise with `$value`. Omit the value only when `T` is `void` or nullable. Fibers awaiting the promise are queued to resume on the loop's next queue drain. Throws `InvalidPromiseStateException` if the `Deferred` has already been resolved or rejected.
:::

:::member[public function reject(\Throwable $reason): void]
Rejects the promise with `$reason`. Throws `InvalidPromiseStateException` if the `Deferred` has already been resolved or rejected.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Deferred;
use Tyhp\EventLoop;
use Tyhp\Exceptions\TimeoutException;
use Tyhp\Promise;

interface MessageSubscriber {
    public function onMessage(string $channel, callable(string): void $handler): void;
    public function off(string $channel): void;
}

/**
 * Resolves with the next message published on $channel.
 */
function nextMessage(MessageSubscriber $bus, string $channel, int $timeoutMs): Promise<string> {
    Deferred<string> $deferred = new Deferred<string>();
    EventLoop $loop = EventLoop::getInstance();

    string $timerId = $loop->delay($timeoutMs, function () use ($deferred, $bus, $channel, $timeoutMs): void {
        $bus->off($channel);
        $deferred->reject(new TimeoutException("No message on {$channel}", $timeoutMs));
    });

    $bus->onMessage($channel, function (string $payload) use ($deferred, $bus, $channel, $loop, $timerId): void {
        $loop->cancelTimer($timerId);
        $bus->off($channel);
        $deferred->resolve($payload);
    });

    return $deferred->getPromise();
}
```

Settle each `Deferred` exactly once, and make sure some path always settles it: a promise that nobody settles keeps any code awaiting it suspended forever. Pairing the success path with a timeout timer, as above, guarantees that.

## Cancellation

Cancellation in Tyhp is cooperative. A `CancellationTokenSource` owns the decision to cancel; the `CancellationToken` it hands out is passed down to the code that does the work, which checks it or registers a callback on it. Nothing is ever stopped forcibly: an operation stops only if it observes the token.

```tyhp
<?tyhp

namespace App;

use Tyhp\CancellationToken;
use Tyhp\CancellationTokenSource;
use Tyhp\Exceptions\OperationCancelledException;
use Tyhp\Promise;

async function fetchStock(string $sku, ?CancellationToken $token = null): int {
    await Promise::delay(30, $token); // stands in for a cancellable request
    return \strlen($sku);
}

async function stockWithin(string $sku, int $deadlineMs): ?int {
    $cts := new CancellationTokenSource($deadlineMs); // cancels itself after the deadline
    try {
        return await fetchStock($sku, $cts->getToken());
    } catch (OperationCancelledException $e) {
        return null;
    }
}
```

`CancellationTokenSource` implements `\Tyhp\Contracts\IsDisposable`, so `:=` disposes it — and stops its auto-cancel timer — when the scope ends. See [Disposables and the := Operator](tyhp_2300_disposables.md).

### How package APIs observe a token

Every member of this package that accepts a token rejects with (or, for `run()`, throws) `OperationCancelledException` when it sees cancellation. They differ in *when* they look:

| API | Checks before starting | Reacts while waiting |
|---|---|---|
| `Promise::delay()` | yes | yes — cancels its timer and rejects immediately |
| `Promise::race()`, `Promise::any()` | yes | yes — rejects immediately; the inputs keep running |
| `Promise::timeout()` | yes | yes (passes the token to its delay and race) |
| `Promise::all()` | before each input | no — noticed only between inputs |
| `Promise::batch()` | before each wave | no — noticed only between waves |
| `Promise::run()` | yes (throws synchronously, before `$fn` is called) | yes — shuts the whole event loop down and throws |
| `EventLoop::run()` | no — first checked at the end of the first loop pass | yes — same shutdown, then throws |
| `Promise::allSettled()` | takes no token | — |

The I/O methods in [`tyhp/io`](package_io.md) and the worker calls in [`tyhp/parallel`](package_parallel.md) accept the same token and abort the underlying work when it is cancelled.

### CancellationTokenSource

`final class CancellationTokenSource implements \Tyhp\Contracts\IsDisposable` in namespace `Tyhp`.

:::member[public function __construct(?int $cancelAfterMs = null)]
Creates a source with a fresh token. When `$cancelAfterMs` is given, schedules automatic cancellation after that many milliseconds (see `cancelAfter()`). Throws `\InvalidArgumentException` if `$cancelAfterMs` is negative.
:::

:::member[public function getToken(): CancellationToken]
Returns the source's token. Every call returns the same instance.
:::

:::member[public function cancel(): void]
Cancels the token and cancels any pending auto-cancel timer. Registered callbacks run synchronously, before `cancel()` returns (see `CancellationToken::register()`). Calling it again, or after `dispose()`, has no effect.
:::

:::member[public function cancelAfter(int $ms): void]
Schedules `cancel()` to run after `$ms` milliseconds, replacing any previously scheduled auto-cancel. The timer lives on the event loop, so it fires only while the loop is running. Throws `\InvalidArgumentException` if `$ms` is negative. Has no effect after `dispose()`.
:::

:::member[public function isCancellationRequested(): bool]
Returns `true` once the token has been cancelled.
:::

:::member[public function dispose(): void]
Cancels the pending auto-cancel timer, if any, without cancelling the token. Afterwards `cancel()` and `cancelAfter()` do nothing. Safe to call more than once.
:::

### CancellationToken

`final class CancellationToken` in namespace `Tyhp`.

:::member[public function isCancellationRequested(): bool]
Returns `true` once the token has been cancelled. Poll it in loops when you want to stop gracefully rather than throw.
:::

:::member[public function throwIfCancellationRequested(): void]
Throws `OperationCancelledException` (whose `getToken()` returns this token) if the token has been cancelled; otherwise does nothing.
:::

:::member[public function register(callable(): void $callback): \Closure]
Registers `$callback` to run when the token is cancelled and returns a closure that unregisters it. If the token is already cancelled, `$callback` runs immediately, before `register()` returns, and the returned closure does nothing.

Callbacks run synchronously inside the `cancel()` call, in registration order. If callbacks throw, the remaining callbacks still run, and then the first exception is rethrown from `cancel()`. Callbacks run outside any fiber, so they cannot `await`; typical callbacks cancel a timer, remove a stream watcher, or reject a `Deferred`.

Always call the returned closure when the operation finishes, so a long-lived token does not accumulate callbacks for work that is already done.
:::

:::member[public static function none(): CancellationToken]
Returns a shared token that is never cancelled. Use it where an API requires a token but the caller has none.
:::

:::member[public function __construct()]
Creates a token that is not cancelled. A token created this way has no source, so nothing can cancel it; obtain tokens from a `CancellationTokenSource` instead.
:::

### Writing cancellable code

Accept an optional `?CancellationToken $token = null` as the last parameter, pass it to every awaited call that accepts one, and check it between steps of your own work:

```tyhp
<?tyhp

namespace App;

use Tyhp\CancellationToken;
use Tyhp\Promise;

async function importAll(array<string> $rows, CancellationToken $token): int {
    int $imported = 0;
    foreach ($rows as $row) {
        $token->throwIfCancellationRequested(); // stop between rows
        await Promise::delay(\strlen($row), $token); // stands in for a cancellable write
        $imported++;
    }
    return $imported;
}
```

To combine a caller's token with your own deadline, create a source for the deadline and cancel it from a callback on the caller's token. Unregister the callback when you are done. `OperationCancelledException::getToken()` and `isCancellationRequested()` tell you which side cancelled:

```tyhp
<?tyhp

namespace App;

use Tyhp\CancellationToken;
use Tyhp\CancellationTokenSource;
use Tyhp\Exceptions\OperationCancelledException;
use Tyhp\Promise;

async function syncInventory(CancellationToken $token): int {
    await Promise::delay(500, $token);
    return 42;
}

/**
 * Returns null when our own deadline expires; rethrows when the caller cancelled.
 */
async function syncWithDeadline(CancellationToken $callerToken, int $deadlineMs): ?int {
    $deadline := new CancellationTokenSource($deadlineMs);
    \Closure $unlink = $callerToken->register(function () use ($deadline): void {
        $deadline->cancel();
    });
    try {
        return await syncInventory($deadline->getToken());
    } catch (OperationCancelledException $e) {
        if ($callerToken->isCancellationRequested()) {
            throw $e;
        }
        return null;
    } finally {
        $unlink();
    }
}
```

## Timeouts

There are three ways to bound how long something may take. All of them report expiry with [`TimeoutException`](#exceptions) or `OperationCancelledException`:

- **`Promise::timeout($promise, $ms)`** stops *waiting* after `$ms` and rejects with `TimeoutException`, but the operation itself continues in the background.
- **`new CancellationTokenSource($ms)`** cancels a token after `$ms`. Operations that observe the token stop their work and reject with `OperationCancelledException`. Prefer this when the work should actually stop.
- **`$promise->wait($ms)`** and **`EventLoop::runUntilSettled($promise, $ms)`** bound how long *synchronous* code blocks, throwing `TimeoutException` with a message such as `Promise did not settle within 100ms timeout`. The promise stays pending and its work stays queued.

## The Event Loop

`final class EventLoop` in namespace `Tyhp`.

Most applications never call the event loop directly: `await`, `Promise`, and `tyhp/io` use it for you. Use it to run async code from synchronous code, to schedule timers and microtasks, to watch your own streams, and in tests.

### Lifecycle

:::member[public static function getInstance(): EventLoop]
Returns the process-wide loop, creating it on first use. Every promise, timer, and stream watcher in the process uses this instance.
:::

<a id="eventloop-run"></a>

:::member[public function run<T extends __Awaited<void|mixed> = mixed>(Promise<T> $rootPromise, ?CancellationToken $token = null): T]
Runs the loop until `$rootPromise` has settled and no work is immediately runnable, then returns the root's value or throws its rejection reason. Timers that are not yet due, intervals, and stream watchers do not keep it running after the root has settled; they stay registered for the next time the loop runs.

Throws `\LogicException` when the loop is already running. Exceptions thrown by timer, microtask, and stream callbacks propagate out of `run()`. If `stop()` ends the loop while the root is still pending, `run()` throws `InvalidPromiseStateException`.

When `$token` is given, it is checked once per loop iteration, after the microtask, timer, and I/O phases. If it is cancelled while the root promise is still pending, `run()` shuts the whole loop down and throws `OperationCancelledException`; if the root settled in that same iteration, its own result or error wins and nothing is shut down. Shutting down:

- drops queued microtasks and fiber starts; the promise of a fiber that never started is rejected with `OperationCancelledException`;
- cancels every timer and interval and removes every stream watcher (the streams are not closed);
- unwinds every fiber that is suspended on a pending promise by throwing `OperationCancelledException` into it, so its `finally` blocks run and its own promise rejects with that exception. A fiber that catches the exception and waits again is rejected and abandoned. Nothing the loop gave up on is started or resumed again, even if the promise it was waiting on settles later;
- attaches an exception thrown by that cleanup code as the `previous` exception of the one `run()` throws.

The loop can be used again afterwards.

What the shutdown rejects and what it leaves alone:

- **Rejected with `OperationCancelledException`:** every promise that was still pending and is backed by a fiber the loop knows about. That covers async functions, closures, and blocks, `Promise::delay()`, and a [`Deferred`](#deferred)'s promise, because a pending `Deferred` is itself a suspended fiber. Code awaiting a `Deferred` is unwound the same way. A later `resolve()` or `reject()` on such a `Deferred` does not throw and changes nothing, because its promise is already rejected.
- **Left unchanged:** a promise that had already settled keeps its result or error, and the root promise keeps its own outcome when it settles in the same iteration as the cancellation.
- **Not interrupted:** a callback that never returns control to the loop (cancellation is noticed at the next iteration), and any stream the loop was watching, which is unregistered but not closed.
:::

:::member[public function runUntilSettled(Promise $promise, int $timeoutMs = -1): mixed]
Runs the loop until `$promise` settles, then immediately returns its value or throws its rejection reason, leaving any other queued work in place. When `$timeoutMs` is greater than zero, throws `TimeoutException` if the promise is still pending after that many milliseconds; otherwise waits without a limit. Throws `\LogicException` when the loop is already running. `Promise::wait()` calls this method.
:::

:::member[public function tick(): bool]
Runs one pass of the cycle — fibers and microtasks, due timers, and a non-blocking I/O poll — and returns `true` if any work is still pending (queued fibers or microtasks, active timers, or registered streams). `tick()` never sleeps, so a `while ($loop->tick())` loop spins until pending timers come due. Use it in tests or when embedding the loop in another scheduler.
:::

:::member[public function stop(): void]
Asks a running `run()` or `runUntilSettled()` to return at the end of the current pass. Pending work stays queued.
:::

:::member[public function isRunning(): bool]
Returns `true` while `run()` or `runUntilSettled()` is executing. Check it before choosing between `await` and a blocking entry point in code that can be called from both places.
:::

:::member[public static function resetInstance(): void]
Discards the process-wide loop so the next `getInstance()` call creates a fresh one, abandoning all queued fibers, timers, microtasks, and stream watchers. Intended for test teardown only.
:::

### Timers

Timer callbacks run on the loop, outside any fiber: they cannot `await`, and an exception they throw stops the loop (see [Errors](#errors)). Timers use PHP's monotonic `\hrtime()` clock.

:::member[public function delay(int $ms, callable(): void $callback): string]
Schedules `$callback` to run once, `$ms` milliseconds from now, and returns a timer ID for `cancelTimer()`. In async code, prefer `await Promise::delay($ms)`.
:::

:::member[public function interval(int $ms, callable(): void $callback): string]
Schedules `$callback` to run every `$ms` milliseconds until cancelled and returns a timer ID. Each next run is scheduled `$ms` after the previous callback finishes.
:::

:::member[public function cancelTimer(string $id): void]
Cancels a timer or interval. Cancelling a timer that has already fired, or an unknown ID, does nothing.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\CancellationToken;
use Tyhp\Deferred;
use Tyhp\EventLoop;
use Tyhp\Promise;

/**
 * Prints a heartbeat every second until $token is cancelled.
 */
function heartbeat(CancellationToken $token): Promise<void> {
    Deferred<void> $stopped = new Deferred<void>();
    EventLoop $loop = EventLoop::getInstance();

    string $intervalId = $loop->interval(1000, function (): void {
        echo 'tick ', \date('H:i:s'), "\n";
    });

    $token->register(function () use ($loop, $intervalId, $stopped): void {
        $loop->cancelTimer($intervalId);
        $stopped->resolve();
    });

    return $stopped->getPromise();
}
```

### Microtasks

:::member[public function queueMicrotask(callable(): void $callback): void]
Queues `$callback` to run in the fibers-and-microtasks phase, before timers and I/O. The loop drains the whole queue — including microtasks queued while it is draining — before moving on, so a microtask that keeps queuing microtasks starves timers and I/O.
:::

:::member[public function defer(callable(): void $callback): void]
Queues `$callback` on the same microtask queue as `queueMicrotask()`; the two methods behave identically.
:::

### Stream watchers

The loop can watch PHP stream resources (sockets, pipes, process streams) and call you back when they are ready, using `\stream_select()`. Put the streams in non-blocking mode with `\stream_set_blocking($stream, false)` so a read or write inside the callback cannot stall the loop. For HTTP, sockets, processes, and databases, the ready-made clients in [`tyhp/io`](package_io.md) are usually the better choice.

:::member[public function addReadStream(mixed $stream, callable(resource): void $callback): void]
Calls `$callback($stream)` on every loop pass in which `$stream` has data to read (or has reached end-of-file), until `removeReadStream()` is called. A stream has one read callback; adding another replaces it. Throws `\InvalidArgumentException` if `$stream` is not a stream resource. If the callback throws, the watcher is removed and the exception propagates out of the loop.
:::

:::member[public function addWriteStream(mixed $stream, callable(resource): void $callback): void]
Calls `$callback($stream)` on every loop pass in which `$stream` can accept writes, until `removeWriteStream()` is called. A stream has one write callback; adding another replaces it. Throws `\InvalidArgumentException` if `$stream` is not a stream resource. If the callback throws, the watcher is removed and the exception propagates out of the loop.
:::

:::member[public function removeReadStream(mixed $stream): void]
Stops watching `$stream` for reads. Remove a watcher before closing its stream.
:::

:::member[public function removeWriteStream(mixed $stream): void]
Stops watching `$stream` for writes. Remove a watcher before closing its stream.
:::

The pattern for turning a stream into a promise is a `Deferred`, a watcher that settles it, and a timer that guarantees it settles:

```tyhp
<?tyhp

namespace App;

use Tyhp\Deferred;
use Tyhp\EventLoop;
use Tyhp\Exceptions\TimeoutException;
use Tyhp\Promise;

/**
 * Resolves with the next line read from a non-blocking stream.
 */
function readLineAsync(resource $stream, int $timeoutMs = 5000): Promise<string> {
    Deferred<string> $deferred = new Deferred<string>();
    EventLoop $loop = EventLoop::getInstance();
    string $buffer = '';
    ?string $timerId = null;

    $loop->addReadStream($stream, function (resource $ready) use ($deferred, $loop, &$buffer, &$timerId): void {
        string|false $chunk = \fread($ready, 8192);
        if ($chunk === false || $chunk === '') {
            $loop->removeReadStream($ready);
            if ($timerId !== null) {
                $loop->cancelTimer($timerId);
            }
            $deferred->reject(new \RuntimeException('Stream closed before a full line arrived'));
            return;
        }
        $buffer .= $chunk;
        int|false $newline = \strpos($buffer, "\n");
        if ($newline !== false) {
            $loop->removeReadStream($ready);
            if ($timerId !== null) {
                $loop->cancelTimer($timerId);
            }
            $deferred->resolve(\substr($buffer, 0, $newline));
        }
    });

    $timerId = $loop->delay($timeoutMs, function () use ($deferred, $loop, $stream, $timeoutMs): void {
        $loop->removeReadStream($stream);
        $deferred->reject(new TimeoutException('No line within ' . $timeoutMs . 'ms', $timeoutMs));
    });

    return $deferred->getPromise();
}
```

Async code can then write `string $line = await readLineAsync($socket);`.

### Fiber scheduling

These methods queue raw `\Fiber` operations for the loop's next fibers-and-microtasks phase. Promises use them internally. Application code should use `async` and `await` instead; managing fibers by hand alongside the loop is error-prone. An exception thrown by a fiber that does not belong to a promise propagates out of the loop.

:::member[public function scheduleFiber(\Fiber<mixed, callable(): void> $fiber): void]
Queues `$fiber` to be started.
:::

:::member[public function scheduleFiberResume(\Fiber<mixed, callable> $fiber, mixed $value = null): void]
Queues a suspended `$fiber` to be resumed with `$value`.
:::

:::member[public function scheduleFiberThrow(\Fiber<mixed, callable> $fiber, \Throwable $error): void]
Queues a suspended `$fiber` to be resumed by throwing `$error` into it.
:::

### Queue entry classes

`EventLoopTimerItem` and `EventLoopFiberItem` are the loop's internal queue entries. They are public classes only so the loop's queues can be typed; applications do not create or receive them.

:::member[final class EventLoopTimerItem]
A scheduled timer: `public string $id`, `public callable(): void $callback`, `public int $interval` (0 for one-shot timers), and `public int $fireAt` (due time in `\hrtime()` nanoseconds). Constructor: `__construct(string $id, callable(): void $callback, int $interval, int $fireAt)`.
:::

:::member[final class EventLoopFiberItem]
A queued fiber operation: `public \Fiber<mixed, callable(): void>|\Fiber<mixed, callable> $fiber`, `public string $action` (`'start'`, `'resume'`, or `'throw'`), `public mixed $value`, and `public ?\Throwable $error`. Constructor: `__construct(\Fiber<mixed, callable(): void>|\Fiber<mixed, callable> $fiber, string $action, mixed $value = null, ?\Throwable $error = null)`.
:::

## Async Iteration Contracts

These interfaces in namespace `Tyhp\Contracts` back `foreach (await $source as ...)`, described in [Async Iteration](tyhp_2600_asyncAndAwait.md#async-iteration). Implement them to expose a sequence whose items arrive over time — lines of a large file, pages of an API, rows of a query.

:::member[interface AsyncIterable<T extends __Awaited<void|mixed>>]
`public function getAsyncIterator(): AsyncIterator<T>` — returns a fresh iterator positioned before the first item. `foreach (await $source as $item)` calls it once per loop.
:::

:::member[interface AsyncIterator<T extends __Awaited<void|mixed>>]
`public function next(): Promise<bool>` — advances to the next item and fulfills with `true` if there is one, or `false` when the sequence is finished.

`public function current(): Promise<T>` — returns the item `next()` moved to.

The compiled loop calls `next()` first and `current()` only after `next()` fulfilled with `true`, so `current()` is never called before the first `next()`. Rejecting either promise ends the loop by throwing the reason at the `foreach`.
:::

:::member[interface AsyncKeyValueIterator<TKey extends __Awaited<void|mixed>, TValue extends __Awaited<void|mixed>> extends AsyncIterator<TValue>]
`public function currentKey(): Promise<TKey>` and `public function currentValue(): Promise<TValue>` — the key and value of the current item. The key-value form `foreach (await $source as $key => $value)` calls these instead of `current()`, so the iterator returned by `getAsyncIterator()` must implement this interface. Declare `getAsyncIterator()` as returning `AsyncKeyValueIterator<TKey, TValue>` and iterate a value whose static type is your class, so the loop knows the key type.
:::

A countdown that produces one number every 100 ms:

```tyhp
<?tyhp

namespace App;

use Tyhp\Contracts\AsyncIterable;
use Tyhp\Contracts\AsyncIterator;
use Tyhp\Promise;

final class Countdown implements AsyncIterable<int> {
    public function __construct(private readonly int $from) {}

    public function getAsyncIterator(): AsyncIterator<int> {
        return new CountdownIterator($this->from);
    }
}

final class CountdownIterator implements AsyncIterator<int> {
    private int $current;

    public function __construct(int $from) {
        $this->current = $from + 1; // positioned before the first item
    }

    public function next(): Promise<bool> {
        return async {
            if ($this->current <= 1) {
                return false;
            }
            await Promise::delay(100);
            $this->current--;
            return true;
        };
    }

    public function current(): Promise<int> {
        return Promise::resolved<int>($this->current);
    }
}

function countdown(int $from): AsyncIterable<int> {
    return new Countdown($from);
}

async function launch(): void {
    foreach (await countdown(3) as int $n) {
        echo $n, "...\n"; // 3...  2...  1...
    }
    echo "Liftoff!\n";
}
```

`next()` does the asynchronous work and `current()` returns an already-settled promise; that split keeps the iterator simple and is the shape `tyhp/io`'s line reader uses. Returning the iterable from a function typed `AsyncIterable<int>`, as `countdown()` does, gives `foreach (await ...)` the element type.

A key-value iterator implements `AsyncKeyValueIterator` and the iterable declares it as the return type of `getAsyncIterator()`. Because the loop takes its key type from that declaration, `inventory()` returns the `Inventory` class rather than `AsyncIterable<int>`:

```tyhp
<?tyhp

namespace App;

use Tyhp\Contracts\AsyncIterable;
use Tyhp\Contracts\AsyncKeyValueIterator;
use Tyhp\Promise;

final class InventoryIterator implements AsyncKeyValueIterator<string, int> {
    private int $position = -1;

    public function __construct(private readonly array<int, string> $skus) {}

    public function next(): Promise<bool> {
        return async {
            await Promise::delay(10); // stands in for fetching the next record
            $this->position++;
            return $this->position < \count($this->skus);
        };
    }

    public function current(): Promise<int> {
        return $this->currentValue();
    }

    public function currentKey(): Promise<string> {
        return Promise::resolved<string>($this->skus[$this->position]);
    }

    public function currentValue(): Promise<int> {
        return Promise::resolved<int>(\strlen($this->skus[$this->position]));
    }
}

final class Inventory implements AsyncIterable<int> {
    public function __construct(private readonly array<int, string> $skus) {}

    public function getAsyncIterator(): AsyncKeyValueIterator<string, int> {
        return new InventoryIterator($this->skus);
    }
}

function inventory(array<int, string> $skus): Inventory {
    return new Inventory($skus);
}

async function printInventory(): void {
    foreach (await inventory(['A-1', 'B-22']) as string $sku => int $stock) {
        echo "{$sku}: {$stock}\n"; // A-1: 3, then B-22: 4
    }
}
```

## Async Disposal

`tyhp/async` provides the async half of Tyhp's disposal support and the runtime behind the `:=` operator. The language features — `:=`, `using` blocks, and the synchronous `\Tyhp\Contracts\IsDisposable` interface from `tyhp/core` — are described in [Disposables and the := Operator](tyhp_2300_disposables.md).

:::member[interface AsyncIsDisposable]
`public function disposeAsync(): Promise<void>` — releases the resource asynchronously, for example by sending a close command and waiting for the acknowledgement. Declared in namespace `Tyhp\Contracts`. Implementations usually declare it as `public async function disposeAsync(): void`.
:::

### DisposableHelper

`final class DisposableHelper` in namespace `Tyhp`. It cannot be instantiated.

:::member[public static async function dispose(IsDisposable|AsyncIsDisposable ...$disposables): void]
Disposes the given resources in reverse order (last argument first). Calls `dispose()` on `IsDisposable` resources and awaits `disposeAsync()` on `AsyncIsDisposable` resources. Every resource is attempted even if an earlier one fails. Each failure raises an `E_USER_WARNING`; then the returned promise rejects with the single failure, or with `\Tyhp\Exceptions\AggregateException` (message `One or more errors during disposal`) when several failed. Returns `Promise<void>`.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Contracts\AsyncIsDisposable;
use Tyhp\DisposableHelper;
use Tyhp\Promise;

final class RemoteSession implements AsyncIsDisposable {
    public function __construct(private readonly string $id) {}

    public async function disposeAsync(): void {
        await Promise::delay(20); // stands in for a close handshake
        echo "closed {$this->id}\n";
    }
}

async function closeSessions(): void {
    RemoteSession $a = new RemoteSession('a');
    RemoteSession $b = new RemoteSession('b');
    await DisposableHelper::dispose($a, $b); // prints "closed b", then "closed a"
}
```

### DisposableScope

`final class DisposableScope implements \Tyhp\Contracts\IsDisposable` in namespace `Tyhp`.

The compiler lowers `:=` variables to a `DisposableScope`: `$x := new R()` becomes `$x = $__scope_0->using(new R())`, and the scope disposes its resources when PHP destroys the scope object, which happens when the function returns. You normally interact with it only through `:=`.

:::member[public static function create(): DisposableScope]
Creates an empty scope. The constructor is private.
:::

:::member[public function using(IsDisposable|AsyncIsDisposable $resource): mixed]
Registers `$resource` for disposal and returns it unchanged.
:::

:::member[public function dispose(): void]
Disposes every registered resource that has not been released, in reverse registration order. Calls `dispose()` on `IsDisposable` resources and waits for `disposeAsync()` on `AsyncIsDisposable` resources (see below). Every resource is attempted even if an earlier one fails; each failure raises an `E_USER_WARNING`, and then `dispose()` throws the single failure or an `AggregateException` (message `One or more errors during disposal`). Calling it again does nothing.
:::

:::member[public function release(IsDisposable|AsyncIsDisposable $resource): void]
Excludes `$resource` from disposal, for example after you have disposed it yourself, so it is not disposed twice.
:::

:::member[public function __destruct()]
Runs `dispose()` if it has not run yet. A failure during destruction is reported as an `E_USER_WARNING` and is not rethrown — use a `using` block when disposal errors must propagate.
:::

When a scope disposes an `AsyncIsDisposable` resource, it waits for `disposeAsync()` as follows:

- If the returned promise has already settled, its outcome is used immediately.
- Inside a fiber (that is, in async code), the scope awaits the promise, so the loop keeps running other work meanwhile.
- Outside a fiber with the loop idle, the scope blocks with `Promise::wait()`.
- Outside a fiber while the loop is running (for example in a timer or stream callback), a pending promise cannot be waited for, and the scope throws `AsyncContextException`. Dispose such resources from async code instead.

## Exceptions

| Exception | Extends | Thrown by |
|---|---|---|
| `Tyhp\Exceptions\TimeoutException` | `\RuntimeException` | `Promise::timeout()`, `Promise::wait()` and `EventLoop::runUntilSettled()` with a timeout, `tyhp/io` timeouts |
| `Tyhp\Exceptions\OperationCancelledException` | `\RuntimeException` | Any API that observes a cancelled `CancellationToken` |
| `Tyhp\Exceptions\InvalidPromiseStateException` | `\LogicException` | Reading a pending promise, settling a `Deferred` twice, a missing value for a non-nullable type |
| `Tyhp\Exceptions\AsyncContextException` | `\RuntimeException` | Awaiting a pending promise outside a fiber; async disposal from a loop callback |
| `Tyhp\Exceptions\AggregateException` (from `tyhp/core`) | `\RuntimeException` | `Promise::any()` when every input rejects; disposal with several failures |

Errors in how the API is called use standard PHP exceptions: `\InvalidArgumentException` for negative delays, an empty `race()`, a `batch()` processor that does not return a promise, or a non-stream passed to a stream watcher; `\LogicException` for re-entrant loop entry points and for resolving a promise with itself.

### TimeoutException

`final class TimeoutException extends \RuntimeException`. You can throw it from your own code to report a deadline.

:::member[public function __construct(string $message = 'The operation timed out', int $timeoutMs = 0, ?\Throwable $previous = null)]
Creates the exception with the timeout that expired, in milliseconds.
:::

:::member[public function getTimeoutMs(): int]
Returns the timeout that expired, in milliseconds.
:::

### OperationCancelledException

`final class OperationCancelledException extends \RuntimeException`.

:::member[public function __construct(CancellationToken $token, string $message = 'The operation was cancelled', ?\Throwable $previous = null)]
Creates the exception for the token that was cancelled. Throw it from your own cancellable code, or call `$token->throwIfCancellationRequested()`, which does this for you.
:::

:::member[public function getToken(): CancellationToken]
Returns the token whose cancellation caused the exception. Compare it with the tokens you hold to tell your own deadline apart from a caller's cancellation.
:::

### InvalidPromiseStateException

`final class InvalidPromiseStateException extends \LogicException`. Signals a programming error in how a promise or `Deferred` is used: calling `getResult()` on a pending promise, resolving or rejecting a `Deferred` a second time, or resolving without a value when the promise's type is neither `void` nor nullable.

### AsyncContextException

`final class AsyncContextException extends \RuntimeException`. Thrown when code tries to wait for a pending promise where no fiber can be suspended: `\Tyhp\Promise::_await()` called from plain PHP or from a timer, microtask, or stream callback, and the `DisposableScope` case described in [Async Disposal](#async-disposal).

## Testing Async Code

Tyhp code is tested through its emitted PHP, for example with PHPUnit. Drive async functions with `EventLoop::getInstance()->run(...)` or `runUntilSettled(...)`, and reset the process-wide loop after each test so leftover timers and abandoned work from one test cannot leak into the next:

```php
<?php

declare(strict_types=1);

namespace App\Tests;

use PHPUnit\Framework\TestCase;
use Tyhp\Deferred;
use Tyhp\EventLoop;
use Tyhp\Exceptions\TimeoutException;

final class PriceServiceTest extends TestCase
{
    protected function tearDown(): void
    {
        EventLoop::resetInstance();
    }

    public function testTotalAddsEveryPrice(): void
    {
        $total = EventLoop::getInstance()->run(\App\totalFor(['A-1', 'B-22']));

        self::assertSame(700, $total);
    }

    public function testUnresolvedPromiseTimesOut(): void
    {
        $this->expectException(TimeoutException::class);

        $never = (new Deferred())->getPromise();
        EventLoop::getInstance()->runUntilSettled($never, 100);
    }
}
```

Tips:

- Give every wait in a test an upper bound (`runUntilSettled($promise, $ms)` or `wait($ms)`), so a promise that never settles fails the test instead of hanging the suite.
- Keep delays in tests short; `Promise::delay()` really waits.
- To test loop-level behaviour step by step, call `tick()` and assert between passes. `tick()` does not sleep.
- Rejections surface as exceptions from `run()`, `runUntilSettled()`, and `wait()`, so `expectException()` works directly.

## Worked Examples

### Retrying with exponential backoff

A generic helper that retries an operation on transient failures, waiting 200 ms, 400 ms, 800 ms, … between attempts, and that stops promptly when cancelled:

```tyhp
<?tyhp

namespace App;

use Tyhp\CancellationToken;
use Tyhp\Promise;

final class TransientException extends \RuntimeException {}

/**
 * Runs $operation until it succeeds, waiting longer after each TransientException.
 * The last attempt's exception propagates unchanged.
 */
async function retry<T extends __Awaited<void|mixed>>(
    callable(): Promise<T> $operation,
    int $maxAttempts = 4,
    int $baseDelayMs = 200,
    ?CancellationToken $token = null
): T {
    for (int $attempt = 1; $attempt < $maxAttempts; $attempt++) {
        $token?->throwIfCancellationRequested();
        try {
            return await $operation();
        } catch (TransientException $e) {
            int $backoffMs = $baseDelayMs * (2 ** ($attempt - 1));
            await Promise::delay($backoffMs, $token);
        }
    }
    $token?->throwIfCancellationRequested();
    return await $operation();
}

final class QuoteClient {
    private int $calls = 0;

    public async function fetch(string $symbol): float {
        await Promise::delay(20);
        $this->calls++;
        if ($this->calls < 3) {
            throw new TransientException("Upstream busy ({$this->calls})");
        }
        return 101.25;
    }
}

async function currentQuote(): float {
    QuoteClient $client = new QuoteClient();
    return await retry<float>(
        fn(): Promise<float> => $client->fetch('ACME'),
        maxAttempts: 5,
        baseDelayMs: 50
    );
}
```

`retry()` takes a callable that *creates* the promise rather than a promise, because each attempt needs a fresh operation — a settled promise cannot be run again. `T` is bounded by `__Awaited<void|mixed>` because it appears inside `Promise<T>`; see [Settled types](#settled-types).

### Fan-out with a shared deadline and partial results

Start every request at once, give the whole group one deadline, and report which requests succeeded, failed, or ran out of time:

```tyhp
<?tyhp

namespace App;

use Tyhp\CancellationToken;
use Tyhp\CancellationTokenSource;
use Tyhp\Exceptions\OperationCancelledException;
use Tyhp\Promise;

final class Report {
    public function __construct(
        public readonly array<string, int> $sizes,
        public readonly array<string, string> $failures,
    ) {}
}

async function measure(string $url, CancellationToken $token): int {
    await Promise::delay(\strlen($url) * 10, $token); // stands in for a cancellable download
    if (\str_contains($url, 'broken')) {
        throw new \RuntimeException("Could not fetch {$url}");
    }
    return \strlen($url) * 1024;
}

async function buildReport(array<string> $urls, int $deadlineMs): Report {
    $cts := new CancellationTokenSource($deadlineMs);
    CancellationToken $token = $cts->getToken();

    array<string, Promise<int>> $pending = [];
    foreach ($urls as $url) {
        $pending[$url] = measure($url, $token);
    }

    array<string, int> $sizes = [];
    array<string, string> $failures = [];
    foreach (await Promise::allSettled($pending) as $url => $outcome) {
        if ($outcome->status === 'fulfilled') {
            $sizes[$url] = $outcome->value ?? 0;
        } else if ($outcome->reason instanceof OperationCancelledException) {
            $failures[$url] = 'deadline exceeded';
        } else {
            $failures[$url] = $outcome->reason?->getMessage() ?? 'unknown error';
        }
    }
    return new Report($sizes, $failures);
}
```

With a 300 ms deadline, a short URL succeeds, a URL containing `broken` fails with its own message, and a long URL whose simulated download takes more than 300 ms is reported as `deadline exceeded`. Because the token is passed into each request, the slow request actually stops at the deadline instead of running on in the background.

### Bounded parallel processing

Process a large list with at most a few operations in flight, stopping between waves if the caller cancels:

```tyhp
<?tyhp

namespace App;

use Tyhp\CancellationToken;
use Tyhp\Promise;

async function resizeImage(string $path, CancellationToken $token): int {
    await Promise::delay(25, $token); // stands in for a call to an image service
    return \strlen($path);
}

async function resizeAll(array<string> $paths, CancellationToken $token): array<int, int> {
    return await Promise::batch(
        $paths,
        fn(string $path): Promise<int> => resizeImage($path, $token),
        concurrency: 4,
        token: $token
    );
}
```

`resizeAll()` returns the results in the same order as `$paths`. Because `batch()` works in waves, keep the processor's running times similar, or split very slow items into their own call.

## Gotchas

:::warning
**An async call does not start until the caller yields.** Validation errors, early token checks, and the first lines of an async function's body run only when the caller awaits something or returns control to the loop. Expect such errors when you `await`, not when you call.
:::

:::warning
**Blocking calls freeze every task.** `\sleep()`, `\file_get_contents()` on a URL, PDO, synchronous curl, and long CPU loops stop the whole loop. Use `Promise::delay()`, the `tyhp/io` clients, or `Promise::yield()` in long loops.
:::

:::warning
**Fire-and-forget work is cut short.** `EventLoop::run()` returns once the root promise settles, without waiting for promises nobody awaited, pending timers, or stream watchers. Await everything that must finish.
:::

:::warning
**Unobserved rejections disappear.** A promise that rejects while nobody awaits it, and without a `catch()` handler, loses its exception silently.
:::

:::warning
**Never enter the loop from inside the loop.** `EventLoop::run()`, `runUntilSettled()`, `Promise::wait()`, and `Promise::run()` throw `\LogicException` when called from async code or from a loop callback. Use `await`.
:::

:::warning
**Loop callbacks are not async.** Timer, interval, microtask, stream, and cancellation callbacks run outside any fiber. They cannot `await`, and an exception they throw stops the loop. Settle a `Deferred` from them instead.
:::

:::warning
**A promise nobody settles hangs its awaiters.** Every `Deferred` needs a path that always settles it, typically paired with a timeout timer. Bound synchronous waits with `wait($ms)` or `runUntilSettled($promise, $ms)`.
:::

:::warning
**Timeouts and races do not stop the losers.** `Promise::timeout()`, `race()`, and `any()` stop waiting, but the other operations keep running. Pass a `CancellationToken` into the work when it should stop.
:::

:::warning
**`all()` reports rejections in key order.** If an earlier input is still pending, `all()` waits for it before reporting a later input's rejection. Use a token, `race()`, or `allSettled()` when you need to react to the first failure immediately.
:::

:::warning
**`batch()` runs in waves.** The next group starts only when every promise in the current group has settled, and `$concurrency` must be at least 1.
:::

## Related Pages

- [Async and Await](tyhp_2600_asyncAndAwait.md) — `async` functions, `await`, async closures and blocks, and `foreach (await ...)`.
- [Disposables and the := Operator](tyhp_2300_disposables.md) — `IsDisposable`, `AsyncIsDisposable`, `:=`, and `using`.
- [The tyhp/io Package](package_io.md) — non-blocking HTTP, processes, files, sockets, Redis, and databases on this event loop.
- [The tyhp/parallel Package](package_parallel.md) — CPU-bound work in worker processes, awaited as promises.
- [The tyhp/core Package](package_core.md) — `IsDisposable`, `AggregateException`, and the runtime type system.
- [Runtime Packages Overview](package_intro.md) — all runtime packages at a glance.
- [Composer Runtime Packages](project_composerPackages.md) — installing and pinning `tyhp/*` packages.
