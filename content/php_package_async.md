---
title: 'tyhp/async for PHP'
---

`tyhp/async` starts work that returns a `\Tyhp\Promise`, waits for it from synchronous PHP or from other async work, cancels it, and combines several promises. The namespace is `Tyhp\`. It depends on `tyhp/core`.

Shared call syntax is on [Packages for PHP](php_packages.md).

## Install

PHP 8.2 or newer. No extension is required. The package version is `0.4`. Pick the `80N` prefix for the PHP you run:

```bash
composer require tyhp/async:805.0.4
```

Composer also installs `tyhp/core`.

## Quick start

`async` returns a promise. `await` returns the value. From ordinary PHP, `await` runs the event loop until that work finishes.

```php
use function Tyhp\async;
use function Tyhp\await;

require 'vendor/autoload.php';

echo await(async(fn (): int => 42)), "\n";
```

## Which calls take types first

Ordinary calls: `Tyhp\async`, `Tyhp\await`, `Promise::then`, `catch`, `finally`, `resolve`, `resolved`, `run`, `all`, `race`, `any`, `timeout`, `whenAll`, `whenAny`, `delay`, and `$promise->wait`.

Types first: `Promise::reject`, `Promise::rejected`, `Promise::withResolvers`, `Promise::allSettled`, and `Promise::batch`.

```php
use Tyhp\Type as T;

$failed = \Tyhp\Promise::reject()(new \RuntimeException('no'));
$deferred = \Tyhp\Promise::withResolvers(T::int)();
```

## async and await

`async(callable(): T $fn): \Tyhp\Promise` runs `$fn` on the event loop. The callable's return type is the settled type.

`await(\Tyhp\Promise $promise, ?int $timeoutMs = null, ?\Tyhp\CancellationToken $token = null): mixed` waits until the promise settles and returns its value, or throws its rejection.

Inside `async`, `await` suspends. From synchronous PHP it runs the event loop until the promise has settled and no immediate work is left. A `$timeoutMs` of zero or greater is a deadline in milliseconds and throws `\Tyhp\Exceptions\TimeoutException` when it elapses. `null` or a negative timeout waits with no deadline. An already-cancelled token throws `\Tyhp\Exceptions\OperationCancelledException`.

`$promise->wait(?int $timeoutMs = null, ?\Tyhp\CancellationToken $token = null): mixed` is the same call.

Called from a loop callback that is not itself inside `async`, both throw `\LogicException`: `EventLoop::run() called re-entrantly — use await instead of run() inside an async context`.

## Continuations

`$promise->then(?callable $onFulfilled = null, ?callable $onRejected = null)` returns a new promise. The handler's return type is the new result type. This is an ordinary call.

`$promise->catch(callable(\Throwable) $onRejected)` registers a rejection handler and returns a promise of the original result type.

`$promise->finally(callable(): mixed $onFinally)` runs when the promise settles, then forwards the original value or error.

```php
use function Tyhp\async;
use function Tyhp\await;

$length = await(
    async(fn (): int => 42)->then(fn (int $v): string => (string) $v)
);
```

`$promise->getState(): \Tyhp\PromiseState` is `Pending`, `Fulfilled`, or `Rejected`. `$promise->isCompleted()`, `isFulfilled()`, and `isFaulted()` read that state. `$promise->getError(): ?\Throwable` is the rejection, or `null`.

`$promise->getResult()` returns the value. It throws `\Tyhp\Exceptions\InvalidPromiseStateException` (`Cannot get result of a pending Promise`) when the promise is still pending, and rethrows the rejection when it failed.

## Factories

| Call | Shape |
|------|--------|
| `Promise::resolve($value = null)` | Ordinary. Adopts a promise, or returns a fulfilled promise for a value. |
| `Promise::resolved($value = null)` | Ordinary. Always a new fulfilled promise. |
| `Promise::run(callable $fn, ?\Tyhp\CancellationToken $token = null)` | Ordinary. From synchronous PHP, runs `$fn` and returns its value. |
| `Promise::reject()(\Throwable $reason)` | Types first. An already-rejected promise. |
| `Promise::rejected()(\Throwable $error)` | Types first. Same idea. `reject` forwards to `rejected`. |
| `Promise::withResolvers(T::int)()` | Types first. Returns a `\Tyhp\Deferred`. |
| `Promise::delay(int $ms, ?\Tyhp\CancellationToken $token = null)` | Ordinary. A promise that fulfills after `$ms` milliseconds. `$ms` must be zero or greater. |

```php
use Tyhp\Type as T;
use function Tyhp\await;

$done = await(\Tyhp\Promise::resolved(42));

$deferred = \Tyhp\Promise::withResolvers(T::int)();
$deferred->resolve(7);
$value = await($deferred->getPromise());
```

`new \Tyhp\Deferred()` is a deferred with no value: call `resolve()` with no argument, because passing a value throws `\InvalidArgumentException`. `\Tyhp\Deferred::new(T::int)()` binds `int`, as in the sample above. `getPromise()` returns the promise. `resolve($value)` and `reject(\Throwable $reason)` settle it once. A second call throws `\Tyhp\Exceptions\InvalidPromiseStateException` (`Deferred has already been settled`).

## Combinators

`all`, `race`, `any`, and `timeout` take an array of promises and are ordinary calls. `whenAll` and `whenAny` are ordinary calls and take the promises as separate arguments. `allSettled` and `batch` take their types first. Every combinator that is itself asynchronous returns a promise, so the sample waits with `await`.

```php
use function Tyhp\async;
use function Tyhp\await;

$a = async(fn (): int => 1);
$b = async(fn (): int => 2);
$both = await(\Tyhp\Promise::all([$a, $b]));
$either = await(\Tyhp\Promise::race([$a, $b]));
$firstOk = await(\Tyhp\Promise::any([$a, $b]));
$variadic = await(\Tyhp\Promise::whenAll($a, $b));
```

| Call | Result |
|------|--------|
| `Promise::all(array $promises, ?\Tyhp\CancellationToken $token = null)` | Array of values, keys preserved. Rejects with the first rejection in key order, after waiting for earlier keys. |
| `Promise::whenAll(\Tyhp\Promise ...$promises)` | The same, as separate arguments. |
| `Promise::race(array $promises, ?\Tyhp\CancellationToken $token = null)` | The first promise to settle, fulfilled or rejected. An empty array throws `\InvalidArgumentException`. |
| `Promise::whenAny(\Tyhp\Promise ...$promises)` | The same, as separate arguments. |
| `Promise::any(array $promises, ?\Tyhp\CancellationToken $token = null)` | The first fulfillment. If every promise rejects, throws `\Tyhp\Exceptions\AggregateException` (`All promises were rejected`). An empty array throws that too. |
| `Promise::timeout($promise, int $ms, ?\Tyhp\CancellationToken $token = null)` | `$promise`, or `\Tyhp\Exceptions\TimeoutException` (`Operation timed out`) after `$ms`. |
| `Promise::allSettled()(array $promises)` | Types first. An array of `\Tyhp\PromiseSettledResult`, keys preserved. This promise does not reject. |
| `Promise::batch()(array $items, callable $processor, int $concurrency = 5, ?\Tyhp\CancellationToken $token = null)` | Types first. `$processor` receives an item and returns a promise. Results keep input order. |

```php
use function Tyhp\await;

$settled = await(\Tyhp\Promise::allSettled()([
    \Tyhp\Promise::resolved(1),
    \Tyhp\Promise::rejected()(new \RuntimeException('no')),
]));

foreach ($settled as $outcome) {
    if ($outcome->status === 'fulfilled') {
        echo $outcome->value, "\n";
    } else {
        echo $outcome->reason->getMessage(), "\n";
    }
}
```

`\Tyhp\PromiseSettledResult` is the object `allSettled` returns. Public properties are `$status` (`'fulfilled'` or `'rejected'`), `$value`, and `$reason`. A fulfilled outcome sets `$value`. A rejected outcome sets `$reason` to the `\Throwable`.

```php
use function Tyhp\await;

$doubled = await(\Tyhp\Promise::batch()(
    [1, 2, 3],
    fn (int $n): \Tyhp\Promise => \Tyhp\Promise::resolved($n * 2),
));
```

`batch` throws `\InvalidArgumentException` when the processor does not return a `\Tyhp\Promise`.

## Cancellation

`new \Tyhp\CancellationTokenSource(?int $cancelAfterMs = null)` creates a source. `getToken(): \Tyhp\CancellationToken` is the token you pass to `await`, `wait`, `all`, `race`, `any`, `timeout`, `batch`, `run`, and `delay`. `cancel(): void` cancels it. `cancelAfter(int $ms): void` cancels later. `isCancellationRequested(): bool` reads the flag. `dispose(): void` releases the source. The class implements `\Tyhp\Contracts\IsDisposable`.

`\Tyhp\CancellationToken::none()` is a token that is never cancelled. `throwIfCancellationRequested(): void` throws `\Tyhp\Exceptions\OperationCancelledException` when it is. `register(callable(): void $callback): \Closure` runs `$callback` on cancel. Calling the returned closure unregisters it.

```php
use function Tyhp\async;
use function Tyhp\await;

$source = new \Tyhp\CancellationTokenSource(500);
try {
    await(async(fn (): int => 1), null, $source->getToken());
} catch (\Tyhp\Exceptions\OperationCancelledException $e) {
    $e->getToken();
} finally {
    $source->dispose();
}
```

`OperationCancelledException::getToken()` returns the token. The default message is `The operation was cancelled`.

## Async iteration

A PHP class implements the contracts by name. Drive them with `async` and `await`.

| Interface | Methods |
|-----------|---------|
| `\Tyhp\Contracts\AsyncIterator` | `next(): \Tyhp\Promise` of `bool`, `current(): \Tyhp\Promise` |
| `\Tyhp\Contracts\AsyncIterable` | `getAsyncIterator(): \Tyhp\Contracts\AsyncIterator` |
| `\Tyhp\Contracts\AsyncKeyValueIterator` | `currentKey(): \Tyhp\Promise`, `currentValue(): \Tyhp\Promise`, plus `AsyncIterator` |

```php
use function Tyhp\async;
use function Tyhp\await;

$iterator = $iterable->getAsyncIterator();
$text = await(async(function () use ($iterator): string {
    $out = '';
    while (await($iterator->next())) {
        $out .= await($iterator->current());
    }
    return $out;
}));
```

## Errors

| Exception | When |
|-----------|------|
| `\Tyhp\Exceptions\OperationCancelledException` | The token was cancelled. `getToken()` returns it. |
| `\Tyhp\Exceptions\TimeoutException` | `await`, `wait`, or `Promise::timeout` hit its deadline. `getTimeoutMs()` returns the milliseconds. |
| `\Tyhp\Exceptions\InvalidPromiseStateException` | `getResult` on a pending promise, or a second `resolve` / `reject` on a `Deferred`. Extends `\LogicException`. |
| `\Tyhp\Exceptions\AggregateException` | `Promise::any` rejected every input. `getInnerExceptions()` returns the list. Defined in `tyhp/core`. |
| `\LogicException` | `await` or `wait` was called from a loop callback outside `async`. |

## Related

- [Packages for PHP](php_packages.md)
- [tyhp/core for PHP](php_package_core.md), [tyhp/io for PHP](php_package_io.md), [tyhp/parallel for PHP](php_package_parallel.md)
- [The tyhp/async Package](package_async.md) — the same package as used from Tyhp
