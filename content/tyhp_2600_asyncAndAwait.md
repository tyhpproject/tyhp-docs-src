---
title: 'Async and Await in Tyhp'
status:
  tier: 0
  story: '04'
  state: complete
---

Tyhp provides first-class `async` and `await` keywords for asynchronous programming. An async function returns a `Promise<T>`, and `await` suspends the current async code until a promise settles, returning its value. The compiler lowers `async` functions to `\Tyhp\Promise::_async(...)` and `await` to `\Tyhp\Promise::_await(...)`. The runtime is the `tyhp/async` Composer package: it uses PHP Fibers for cooperative scheduling and a single-process event loop with non-blocking timers and stream I/O. Blocking PHP I/O (`\file_get_contents()`, PDO, curl without async wrappers, and similar) blocks that loop — every other fiber waits until the call returns.

This page covers the language constructs. The full runtime API (`Promise`, `Deferred`, `EventLoop`, `CancellationToken`, and the contracts) is documented in the [`tyhp/async` package reference](package_async.md).

## Async Function Declaration

An async function is declared by adding the `async` keyword before `function`. The declared return type is the type you get when you `await` the function — the compiler makes the call return a `Promise` of it for you. Write the return type as if the function were synchronous.

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

final class User {
    public function __construct(
        public readonly int $id,
        public readonly string $name,
    ) {}
}

final class UserRepository {
    public async function find(int $id): User {
        await Promise::delay(5);
        return new User($id, "user{$id}");
    }

    public async function delete(int $id): void {
        await Promise::delay(5);
        echo "deleted {$id}\n";
    }
}

// Async standalone function — declared return type is User,
// actual return type is Promise<User>
async function fetchUser(UserRepository $repo, int $id): User {
    User $user = await $repo->find($id);
    return $user;
}

// Async method in a class
final class UserService {
    public function __construct(private readonly UserRepository $repository) {}

    public async function getUser(int $id): User {
        return await $this->repository->find($id);
    }

    // Async void — returns Promise<void>
    public async function deleteUser(int $id): void {
        await $this->repository->delete($id);
    }
}

async function main(): void {
    $repo = new UserRepository();
    $user = await fetchUser($repo, 1);
    echo $user->name, "\n";

    $service = new UserService($repo);
    echo (await $service->getUser(2))->name, "\n";
    await $service->deleteUser(3);
}

// Prints:
// user1
// user2
// deleted 3
```

The compiler emits:

```php
<?php

namespace App;

function fetchUser(\App\UserRepository $repo, int $id): \Tyhp\Promise
{
    return \Tyhp\Promise::_async(function () use ($repo, $id): \App\User {
        $user = \Tyhp\Promise::_await($repo->find($id));
        return $user;
    });
}

class UserService
{
    public function __construct(private readonly \App\UserRepository $repository) {}

    public function getUser(int $id): \Tyhp\Promise
    {
        return \Tyhp\Promise::_async(function () use ($id): \App\User {
            return \Tyhp\Promise::_await($this->repository->find($id));
        });
    }

    public function deleteUser(int $id): \Tyhp\Promise
    {
        return \Tyhp\Promise::_async(function () use ($id): void {
            \Tyhp\Promise::_await($this->repository->delete($id));
        });
    }
}
```

### The Declared Return Type Is the Settled Type

For every `async` function, method, closure, arrow function, interface or abstract method, and tyhpdef signature, the declared return type `R` is read as `__Awaited<R>` — the type with every `Promise` layer settled (see [`__Awaited<T>`](tyhp_0150_newTypes.md#type-utility-types)). A call has type `Promise<__Awaited<R>>`, and `await` gives `__Awaited<R>`. In particular:

- `async function f(): Promise<int>` yields `int` when awaited, not `Promise<int>`. It is the same function as `async function f(): int`.
- Writing `__Awaited<R>` yourself is not wrapped a second time.
- A `return` of a promise inside the body is allowed: the function's own promise adopts the outcome of the returned one, so `async function g(): int { return f(); }` is valid.
- The PHP signature of the emitted function is always `\Tyhp\Promise`; the settled type appears only on the inner closure.

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

async function loadCount(): int {
    await Promise::delay(5);
    return 3;
}

async function loadCountAgain(): Promise<int> { // read as: int
    return 3;
}

async function main(): void {
    Promise<int> $pending = loadCount(); // a call is a Promise of the settled type
    int $a = await $pending;
    int $b = await loadCountAgain();     // int, not Promise<int>
}
```

A promise never holds another promise, so a `Promise<Promise<int>>` type cannot be written (TYHP4373). To hand a promise to a caller as a *value*, wrap it in an array, a class, or a struct, or settle a [`Deferred`](package_async.md#deferred) from outside.

## Await Expression

`await` is a unary prefix operator. It suspends the current async function, async closure, or async block until the given `Promise<T>` settles, then evaluates to the resolved value of type `T`. It can only be used inside those async contexts. If the promise rejects, the rejection reason is thrown at the `await` point.

```tyhp
<?tyhp

async function greetUser(UserRepository $repo, int $id): string {
    // await unwraps Promise<User> to User
    User $user = await $repo->find($id);

    // Awaits run one after another
    await Promise::delay(5);

    return "Hello, {$user->name}!";
}
```

## The Promise<T> Type

`Promise<T>` is provided by the `tyhp/async` package. It represents a computation that eventually settles with a value of type `T`. The generic parameter is `TReturn extends __Awaited<void|mixed> = __Awaited<mixed>`: `T` must be an already-settled type, so an unparameterized `Promise` is `Promise<mixed>`, `Promise<void>` is the type of async functions that return nothing, and `Promise<Promise<int>>` is rejected (TYHP4373).

## Promise Combinators

`Promise` provides static methods for coordinating several async operations. The common ones are summarized here; each is described in full in the [package reference](package_async.md#the-promise-class).

:::member[Promise::all(array<Promise<T>> $promises, ?CancellationToken $token = null): array<T>]
Waits for every promise and returns their values. Keys are preserved. If an input rejects, `all()` rejects with that reason once it reaches that input in key order. An empty array returns `[]`.
:::

:::member[Promise::allSettled(array<TKey, Promise<T>> $promises): array<TKey, PromiseSettledResult<T>>]
Waits for every promise to settle and returns one outcome object per input (with `status`, and either `value` or `reason`). Never rejects because of an input.
:::

:::member[Promise::race(array<Promise<T>> $promises, ?CancellationToken $token = null): T]
Settles like the first input to settle. The other promises keep running and their outcomes are ignored.
:::

:::member[Promise::resolve(?T $value = null): Promise<T>]
Returns an already-fulfilled promise holding `$value`. If `$value` is already a `Promise`, that same instance is returned.
:::

:::member[Promise::resolved(?T $value = null): Promise<__Awaited<T>>]
Always returns a new already-fulfilled promise. If `$value` is itself a promise, the new promise adopts it and settles when it does. Pass the type argument explicitly: `Promise::resolved<int>(42)`.
:::

:::member[Promise::reject(\Throwable $reason): Promise<T>]
Returns an already-rejected promise. Equivalent to `Promise::rejected()`.
:::

:::member[Promise::delay(int $ms, ?CancellationToken $token = null): void]
Resolves after `$ms` milliseconds. Use it for backoff and throttling. With a token, cancellation rejects the delay with `OperationCancelledException`.
:::

:::member[Promise::timeout(Promise<T> $promise, int $ms, ?CancellationToken $token = null): Promise<T>]
Settles like `$promise` if it does so within `$ms` milliseconds, otherwise rejects with `TimeoutException`. The underlying operation is not stopped.
:::

:::member[Promise::batch(array<TItem> $items, callable(TItem): Promise<TBatchReturn> $processor, int $concurrency = 5, ?CancellationToken $token = null): array<int, TBatchReturn>]
Runs `$processor` over the items in waves of up to `$concurrency` and returns the results in input order.
:::

:::member[Promise::run(callable(): T $fn, ?CancellationToken $token = null): __Awaited<T>]
Runs `$fn` inside the event loop and returns its settled value (or throws its rejection reason). It is the entry point for async code from synchronous code. With a token, cancelling it while the work is still pending shuts the loop down and throws `OperationCancelledException`.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Exceptions\TimeoutException;
use Tyhp\Promise;

async function fetchProfile(int $userId): string {
    await Promise::delay(30);
    return "profile:{$userId}";
}

async function fetchOrders(int $userId): string {
    await Promise::delay(10);
    return "orders:{$userId}";
}

async function fetchNotifications(int $userId): string {
    await Promise::delay(20);
    return "notifications:{$userId}";
}

// Run multiple operations in parallel with Promise::all()
async function fetchDashboard(int $userId): string {
    array<string> $results = await Promise::all([
        fetchProfile($userId),
        fetchOrders($userId),
        fetchNotifications($userId)
    ]);

    return \implode(', ', $results);
}

async function primaryApi(string $url): string {
    await Promise::delay(50);
    return "primary {$url}";
}

async function fallbackApi(string $url): string {
    await Promise::delay(10);
    return "fallback {$url}";
}

// Race: the first to settle wins
async function fetchWithFallback(string $url): string {
    return await Promise::race([
        primaryApi($url),
        fallbackApi($url)
    ]);
}

// Delay for backoff
async function retryWithBackoff(int $attempt): string {
    await Promise::delay($attempt * 10);
    return "attempt {$attempt} done";
}

final class Item {
    public function __construct(public readonly int $value) {}
}

final class Result {
    public function __construct(public readonly int $doubled) {}
}

async function process(Item $item): Result {
    await Promise::delay(5);
    return new Result($item->value * 2);
}

// Batch processing with concurrency control
async function processAll(array<Item> $items): array<int, Result> {
    return await Promise::batch(
        $items,
        fn(Item $item): Promise<Result> => process($item),
        concurrency: 5
    );
}

// Timeout: reject if not settled within the deadline
async function fetchWithTimeout(string $url): string {
    return await Promise::timeout(primaryApi($url), 20);
}

async function main(): void {
    echo await fetchDashboard(1), "\n";
    echo await fetchWithFallback('/data'), "\n";
    echo await retryWithBackoff(2), "\n";
    foreach (await processAll([new Item(1), new Item(2), new Item(3)]) as $result) {
        echo $result->doubled, "\n";
    }
    try {
        await fetchWithTimeout('/slow');
    } catch (TimeoutException $e) {
        echo $e->getMessage(), "\n";
    }
}

// Prints:
// profile:1, orders:1, notifications:1
// fallback /data
// attempt 2 done
// 2
// 4
// 6
// Operation timed out
```

:::note
`Promise::all()` returns `array<T>`, but its static key type is `int|string` even for a list. Assign the result to an `array<T>` variable (or declare the function's return type as `array<T>`), not to `array<int, T>`.
:::

## Instance Methods: then, catch, finally

Promise instances support callback chaining with `then()`, `catch()`, and `finally()`. Each returns a new promise. A `finally()` callback that returns nothing can be an arrow function declared `: void`. The handler passed to `catch()` returns the same value type as the promise it is attached to, so `catch()` keeps the promise's type; `then()` is declared as a set of [overloads](tyhp_1200_functionOverloads.md) (no handlers, only a rejection handler, or a fulfillment handler with an optional rejection handler) and its result type follows the handler you pass. See the [package reference](package_async.md#chaining-handlers).

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

final class Data {
    public function __construct(private readonly string $payload) {}

    public function format(): string {
        return \strtoupper($this->payload);
    }
}

async function fetchData(bool $fail): Data {
    await Promise::delay(5);
    if ($fail) {
        throw new \RuntimeException('upstream down');
    }
    return new Data('payload');
}

function cleanup(): void {
    echo "cleanup\n";
}

async function withHandlers(bool $fail): string {
    string $result = await fetchData($fail)
        ->then(fn(Data $d): string => $d->format())
        ->catch(fn(\Throwable $e): string => 'fallback')
        ->finally(fn(): void => cleanup());

    return $result;
}

// await withHandlers(false) prints "cleanup" and returns "PAYLOAD".
// await withHandlers(true) prints "cleanup" and returns "fallback".
```

## Async Closures and Arrow Functions

The `async` keyword can be applied to closures and arrow functions. Calling one starts the work and gives you a promise to `await`.

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

final class Request {
    public function __construct(public readonly int $userId) {}
}

final class Response {
    public function __construct(public readonly string $body) {}
}

final class Auth {
    public async function getUser(Request $req): User {
        await Promise::delay(5);
        return new User($req->userId, "user{$req->userId}");
    }
}

async function demo(Auth $auth, UserRepository $repo): void {
    // Async closure
    $handler = async function(Request $req) use ($auth): Response {
        User $user = await $auth->getUser($req);
        return new Response("Hello, {$user->name}");
    };
    Response $response = await $handler(new Request(1));
    echo $response->body, "\n";

    // Async arrow function
    $fetch = async fn(int $id): User => await $repo->find($id);
    User $user = await $fetch(2);
    echo $user->name, "\n";

    // An async closure is a callable that returns a Promise, so it works with \array_map()
    array<int> $userIds = [3, 4];
    array<User> $users = await Promise::all(
        \array_map(async fn(int $id): User => await $repo->find($id), $userIds)
    );
    foreach ($users as $found) {
        echo $found->name, "\n";
    }
}

// Prints:
// Hello, user1
// user2
// user3
// user4
```

The compiler emits:

```php
<?php

// Async closure: a closure that returns a started promise
$handler = function (\App\Request $req) use ($auth): \Tyhp\Promise {
    return \Tyhp\Promise::_async(function () use ($auth, $req): \App\Response {
        $user = \Tyhp\Promise::_await($auth->getUser($req));
        return new Response("Hello, $user->name");
    });
};

// Async arrow function
$fetch = fn(int $id): \Tyhp\Promise => \Tyhp\Promise::_async(fn() => \Tyhp\Promise::_await($repo->find($id)));
```

The type of an `async` closure or arrow function is `callable(…): Promise<R>`, where `R` is its declared return type read as a settled type (`__Awaited<R>`), exactly as for an `async` function. You can call it through a variable, pass it to `\array_map()`, or pass it to a generic parameter such as the processor of `Promise::batch(array<TItem> $items, callable(TItem): Promise<TBatchReturn> $processor, …)`, and the compiler infers the result type from it. An ordinary closure declared as `fn(int $id): Promise<User> => $repo->find($id)` has the same type.

## Async Blocks

An `async { ... }` block is an expression that evaluates to a **running** `Promise<T>`, not a callable. An inner `return` completes that promise and an inner `await` is legal. Use it when a method already returns `Promise<T>` and you want sequential await logic without making the method itself `async` (which would wrap a second promise layer).

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

final class Greeter {
    public function greet(string $name): Promise<string> {
        return async {
            await Promise::delay(5);
            return "Hello, {$name}!";
        };
    }
}

// Empty block — Promise<void>
Promise<void> $idle = async {};
```

The compiler emits an already-started promise, not a callable:

```php
<?php

public function greet(string $name): \Tyhp\Promise
{
    return \Tyhp\Promise::_async(function () use ($name) {
        \Tyhp\Promise::_await(\Tyhp\Promise::delay(5));
        return "Hello, $name!";
    });
}
```

`async function () { ... }` remains a **callable** that *returns* a promise when invoked. `(async function () { ... })()` is the equivalent of `async { ... }`. Do not write `return async function () { ... };` from a method typed `Promise<T>` — that returns a callable, not a promise.

## Error Handling in Async Functions

Errors in async functions work with `try`/`catch`. When an awaited promise rejects, the exception is thrown at the `await` point, exactly like a synchronous exception.

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

async function safeGreeting(UserRepository $repo, int $id): ?string {
    try {
        return await greetUser($repo, $id);
    } catch (\InvalidArgumentException $e) {
        echo 'Lookup failed: ', $e->getMessage(), "\n";
        return null;
    }
}

// Errors propagate through await chains
async function pipeline(string $url): string {
    try {
        Data $data = await download($url);
        Data $validated = await validate($data);
        return await transform($validated);
    } catch (ValidationException $e) {
        return 'invalid: ' . $e->getMessage();
    } catch (\Throwable $e) {
        throw new ProcessingException('Pipeline failed', 0, $e);
    }
}
```

If `UserRepository::find()` throws `\InvalidArgumentException("No user -1")` for a negative id, `await safeGreeting($repo, -1)` prints `Lookup failed: No user -1` and returns `null`.

## Running async code from synchronous code

`await` is only legal in async code. Ordinary functions, PHP scripts, and test methods start the event loop explicitly. In an application entry file, a top-level `await` does this for you. `Promise::run()` runs a closure inside the loop and returns its settled value: the closure may be plain or `async`, and the call is typed as the value, not as a `Promise`. The type argument is inferred from the closure; `Promise::run<string>(…)` is accepted too.

```tyhp
<?tyhp

namespace App;

use Tyhp\Promise;

function main(): void {
    // Promise::run() starts the event loop and returns the closure's value
    string $result = Promise::run(async function(): string {
        Data $first = await download('/a');
        return $first->body;
    });
    echo $result, "\n";

    // An async arrow function works too
    int $count = Promise::run(async fn(): int => 3);
    echo $count, "\n";
}

// Prints:
// body of /a
// 3
```

`Promise::run()`, `EventLoop::run()`, and the other entry points throw `\LogicException` when called while the loop is already running; inside async code use `await`. The [package reference](package_async.md#running-async-code-from-synchronous-code) lists every entry point and how the loop starts and stops.

## Async Iteration

`foreach (await $expr as $item)` iterates asynchronously. The expression can be an `AsyncIterable<T>`, a `Promise<array<...>>` (or other iterable), or a `Promise<AsyncIterable<T>>`. `AsyncIterable` is iterated with a loop of awaited `next()` / `current()` calls; a promise of an ordinary iterable is awaited first and then iterated synchronously.

```tyhp
<?tyhp

namespace App;

use Tyhp\Contracts\AsyncIterable;
use Tyhp\Contracts\AsyncIterator;
use Tyhp\Promise;

final class Message {
    public function __construct(public readonly string $text) {}
}

final class MessageStream implements AsyncIterable<Message> {
    public function __construct(private readonly array<int, string> $texts) {}

    public function getAsyncIterator(): AsyncIterator<Message> {
        return new MessageIterator($this->texts);
    }
}

final class MessageIterator implements AsyncIterator<Message> {
    private int $position = -1;

    public function __construct(private readonly array<int, string> $texts) {}

    public function next(): Promise<bool> {
        return async {
            await Promise::delay(5);
            $this->position++;
            return $this->position < \count($this->texts);
        };
    }

    public function current(): Promise<Message> {
        return Promise::resolved<Message>(new Message($this->texts[$this->position]));
    }
}

// Case 1: AsyncIterable<T> — true async iteration;
// each element is awaited as it becomes available
async function processMessages(MessageQueue $queue): void {
    foreach (await $queue->messagesAsync() as Message $message) {
        await $queue->handle($message);
    }
}

// Case 2: Promise<array<int, Message>> — resolve, then iterate synchronously
async function processAll(ApiClient $api): void {
    foreach (await $api->fetchAllAsync() as Message $item) {
        echo "item {$item->text}\n";
    }
}

// Case 3: Promise<AsyncIterable<T>> — resolve, then iterate asynchronously
async function processStream(ApiClient $api): void {
    foreach (await $api->openStream() as Message $item) {
        echo "streamed {$item->text}\n";
    }
}
```

The compiler emits:

```php
<?php

// Case 1: AsyncIterable<T> compiles to a while-loop with _await:
$__asyncIter_1 = $queue->messagesAsync()->getAsyncIterator();
while (\Tyhp\Promise::_await($__asyncIter_1->next())) {
    $message = \Tyhp\Promise::_await($__asyncIter_1->current());
    \Tyhp\Promise::_await($queue->handle($message));
}

// Case 2: Promise<array<...>> compiles to resolve, then foreach:
foreach (\Tyhp\Promise::_await($api->fetchAllAsync()) as $item) {
    echo "item $item->text\n";
}

// Case 3: Promise<AsyncIterable<T>> awaits the promise, then iterates asynchronously:
$__asyncIter_2 = \Tyhp\Promise::_await($api->openStream())->getAsyncIterator();
while (\Tyhp\Promise::_await($__asyncIter_2->next())) {
    $item = \Tyhp\Promise::_await($__asyncIter_2->current());
    echo "streamed $item->text\n";
}
```

### Key-value iteration

`foreach (await $source as $key => $value)` calls `currentKey()` and `currentValue()` instead of `current()`, so the iterator returned by `getAsyncIterator()` must implement `AsyncKeyValueIterator<TKey, TValue>`. Declare `getAsyncIterator()` as returning `AsyncKeyValueIterator<TKey, TValue>` and iterate a value whose static type is your class, so the loop knows the key type:

```php
<?php

$__asyncIter_3 = $source->getAsyncIterator();
while (\Tyhp\Promise::_await($__asyncIter_3->next())) {
    $key = \Tyhp\Promise::_await($__asyncIter_3->currentKey());
    $value = \Tyhp\Promise::_await($__asyncIter_3->currentValue());
    echo "{$key}: {$value}";
}
```

A complete `AsyncKeyValueIterator` implementation is shown in the [package reference](package_async.md#async-iteration-contracts).

## Cancellation

`CancellationTokenSource` and `CancellationToken` provide cooperative cancellation. Operations that accept a `?CancellationToken` (such as `Promise::delay()`, `Promise::all()`, and `Promise::batch()`) reject with `OperationCancelledException` when the token is cancelled. `CancellationTokenSource` implements `IsDisposable`, so `:=` disposes it for you; see [Disposables](tyhp_2300_disposables.md).

```tyhp
<?tyhp

namespace App;

use Tyhp\CancellationToken;
use Tyhp\CancellationTokenSource;
use Tyhp\Exceptions\OperationCancelledException;
use Tyhp\Promise;

final class Data {
    public function __construct(public readonly string $body) {}
}

async function download(string $url, ?CancellationToken $token = null): Data {
    await Promise::delay(50, $token);
    return new Data("body of {$url}");
}

async function fetchWithTimeout(string $url): ?Data {
    // The source cancels its token after 20 ms
    $cts := new CancellationTokenSource(20);
    try {
        return await download($url, $cts->getToken());
    } catch (OperationCancelledException $e) {
        echo "cancelled: {$url}\n";
        return null;
    }
}

async function fetchWithManualCancel(string $url): ?Data {
    $cts := new CancellationTokenSource();
    Promise<Data> $pending = download($url, $cts->getToken());
    $cts->cancel();
    try {
        return await $pending;
    } catch (OperationCancelledException $e) {
        echo "manually cancelled: {$url}\n";
        return null;
    }
}
```

`await fetchWithTimeout('/slow')` prints `cancelled: /slow` and returns `null`; `await fetchWithManualCancel('/slow')` prints `manually cancelled: /slow` and returns `null`.

A token can also be handed to the entry point: `Promise::run($fn, $token)` and `EventLoop::run($promise, $token)` check it once per loop iteration. If it is cancelled while the root work is still pending, the whole event loop is shut down — queued work, timers, intervals, and stream watchers are dropped, and every suspended fiber has `OperationCancelledException` thrown into it so its `finally` blocks run — and the entry point throws `OperationCancelledException`. The loop can be used again afterwards. See [How the loop reacts to cancellation](package_async.md#eventloop-run) in the package reference.

## Awaiting in Loops

`await` works inside loops. Each iteration suspends and resumes independently, so a loop of awaits runs one operation at a time:

```tyhp
<?tyhp

async function fetchSequentially(array<string> $urls): array<Data> {
    array<Data> $results = [];
    foreach ($urls as string $url) {
        $results[] = await download($url);
    }
    return $results;
}

// For parallel execution, start every operation first and use Promise::all():
async function fetchInParallel(array<string> $urls): array<Data> {
    return await Promise::all(
        \array_map(
            fn(string $url): Promise<Data> => download($url),
            $urls
        )
    );
}
```

## Best Practices

:::tip
Use `await` to unwrap promises — it gives sequential-looking code that is easier to read and debug than callback chains.
:::

:::tip
Use `Promise::all()` for independent operations that can run concurrently. This improves performance compared to sequential awaits.
:::

:::tip
Use `Promise::batch()` with a concurrency limit when processing large collections, to avoid overwhelming external services or running out of memory.
:::

:::tip
Handle errors with `try`/`catch` around `await` expressions. A rejected promise that is never awaited and has no `catch()` handler is discarded without any report.
:::

:::tip
Use a `CancellationToken` with `:=` for timeout and cancellation scenarios; the source is disposed when the function exits.
:::

## Common Mistakes

:::danger
Using `await` outside of an async function. The compiler reports error TYHP4028: "`await` can only be used inside an async function". Wrap the code in an async function, or start the loop with `Promise::run()` at the entry point.
:::

:::danger
Forgetting to `await` a promise (fire-and-forget). If the root of the event loop finishes first, the unawaited work is abandoned mid-flight, and a rejection it produces is never reported. Await every promise whose completion or failure matters.
:::

:::danger
Using blocking I/O inside async functions. Blocking PHP I/O (`\file_get_contents()`, PDO, curl without async wrappers, and similar) blocks the entire `tyhp/async` event loop, so other fibers cannot run until the call returns. Use non-blocking facilities instead.
:::

:::danger
Mixing raw Fiber usage with async/await. The `tyhp/async` event loop manages fibers internally; creating and managing fibers directly can interfere with its scheduling.
:::

:::danger
Iterating an `AsyncIterable<T>` without `await` in the `foreach`. The compiler reports error TYHP4046; use `foreach (await $expr as $item)` inside an async function.
:::

## Compiler Errors

```tyhp
<?tyhp

use Tyhp\Contracts\AsyncIterable;

// ERROR TYHP4028: `await` can only be used inside an async function
function notAsync(): int {
    return await \Tyhp\Promise::resolved<int>(1);
}

// ERROR TYHP4046: Cannot iterate `AsyncIterable<string>` synchronously;
// use `foreach (await $expr as ...)` inside an async function
function badIteration(AsyncIterable<string> $msgs): void {
    foreach ($msgs as $m) {
        echo $m;
    }
}

// FIX: use await in the foreach, inside an async function
async function goodIteration(AsyncIterable<string> $msgs): void {
    foreach (await $msgs as string $m) {
        echo $m;
    }
}
```

:::note
The `tyhp/async` Composer package is added as a dependency of your output project automatically when the compiler detects `async`/`await` or disposable features. You do not need to install it manually.
:::
