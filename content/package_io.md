---
title: 'The tyhp/io Package'
---

`tyhp/io` gives Tyhp programs non-blocking I/O on the `tyhp/async` event loop. It covers HTTP requests, external processes, local files, TCP, TLS, and Unix-domain sockets, Redis, PostgreSQL, MySQL/MariaDB, any PDO driver, DNS lookups, and a general way to move blocking work out of the way. While one fiber waits for a response, a query, or a child process, every other fiber keeps running.

Everything lives under the `Tyhp\Io` namespace. You write ordinary sequential code with `await`, and you combine independent operations with `Promise::all()` or `Promise::batch()` from `tyhp/async`. This page is the reference for the package API. The language features it relies on are covered in [Async and Await](tyhp_2600_asyncAndAwait.md), [Structs](tyhp_0400_structs.md), and [Generics](tyhp_0500_generics.md).

## Overview

### The `Async` naming convention

Every public method that returns a `Promise` ends in `Async`, for example `HttpClient::getAsync()`, `File::linesAsync()`, and `DbConnection::queryAsync()`. When you see the suffix, the call starts work and hands back a `Promise<T>`: `await` it inside async code to get the `T`, or collect several and await them together. Methods without the suffix (`close()`, `isClosed()`, `header()`, `rowsAs()`, `Offload::usesWorkers()`, and so on) return their value directly.

Methods that implement an interface contract keep the contract's name. `OffloadJob::run()` is the blocking method you write for `Offload::runAsync()`, and the iterator returned by `File::linesAsync()` uses the standard `AsyncIterator` methods `next()` and `current()`, which `foreach (await ...)` calls for you.

:::note
The signatures on this page show what a caller receives. A method shown as returning `Promise<T>` may be declared `async` with return type `T` in the package source; the two are the same to the caller. Static methods are marked `static`.
:::

### What is in the package

| Area | Namespace | Main types | Needs |
|------|-----------|------------|-------|
| HTTP client | `Tyhp\Io\Http` | `HttpClient`, `HttpRequest`, `HttpResponse` | `ext-curl` |
| Processes | `Tyhp\Io\Process` | `Process`, `ProcessOptions`, `ProcessResult` | — |
| Files | `Tyhp\Io\File` | `File` | — |
| Sockets | `Tyhp\Io\Socket` | `Socket`, `SocketConnection` | `ext-openssl` for `tls://` |
| Redis | `Tyhp\Io\Redis` | `RedisClient`, `RedisOptions` | — |
| Databases | `Tyhp\Io\Db` | `DbConnection`, `DbResult`, `DbStatement`, `DbValue`, `PostgresConnection`, `MySqlConnection`, `MySqlOptions`, `PdoConnection`, `PdoOptions` | `ext-pgsql`, `ext-mysqli`, or `ext-pdo` plus a PDO driver |
| Blocking work | `Tyhp\Io` | `Offload`, `OffloadJob` | `tyhp/parallel` (optional) |
| DNS | `Tyhp\Io\Dns` | `Dns` | — |
| Errors | `Tyhp\Io\Exceptions` | `IoException` and its subclasses | — |

### How each area waits

PHP does not offer non-blocking versions of every kind of I/O, so the package uses the best mechanism available for each area. This table tells you what still blocks the event loop.

| Area | How it waits | What can still block the loop |
|------|--------------|-------------------------------|
| `HttpClient` | One curl multi handle per client, driven from the event loop | Nothing during transfers |
| `Process` | Non-blocking stdin/stdout/stderr pipes | Nothing while the command runs |
| `File` | Reads and writes in 256 KiB chunks and yields to other fibers between chunks | Each single chunk, briefly |
| `Socket` / `SocketConnection` | Non-blocking streams registered with the event loop | Host-name resolution inside PHP's socket connect call |
| `RedisClient` | A `SocketConnection` | Same as sockets |
| `PostgresConnection` | libpq's asynchronous connect and query API | Nothing |
| `MySqlConnection` | `MYSQLI_ASYNC` queries polled from the event loop | The connection handshake |
| `PdoConnection`, `Dns`, `Offload` | A `tyhp/parallel` worker process when available | The whole call, when no worker is available |

## Installation

`tyhp/io` is a compiled runtime package. The compiler does not add it for you; require it explicitly:

```bash
composer require tyhp/io
```

Version pins follow the same `80N.X.Y` scheme as the other compiled `tyhp/*` helpers, where `80N` is the PHP version your project targets (`output.phpVersion`) and `X.Y` is the package's own version (currently `0.1`). A project targeting PHP 8.4 therefore pins `"tyhp/io": "804.0.1"` or `"804.0.*"`. See [Composer Runtime Packages](project_composerPackages.md) for how these versions work. The package requires PHP 8.2 or later, `tyhp/core`, and `tyhp/async`.

### PHP extensions

The package installs without any optional extension. Each component checks for the extension it needs when you first use it and fails with `IoUnavailableException` when it is missing:

| Component | Extension |
|-----------|-----------|
| `HttpClient` | `ext-curl` |
| `PostgresConnection` | `ext-pgsql` |
| `MySqlConnection` | `ext-mysqli` |
| `PdoConnection` | `ext-pdo` and the driver for your DSN (for example `pdo_sqlite`, `pdo_mysql`, `pdo_pgsql`) |

`tls://` sockets and `RedisOptions::$tls` use PHP's OpenSSL stream support.

The package's public API uses only its own types and builtins, so you do not need any `tyhpdef/php-ext-*` package to call it. Add one only when your own code calls that extension directly, for example `tyhpdef/php-ext-pdo` to write `\PDO::ATTR_TIMEOUT` in `PdoOptions::$attributes`.

### Optional: `tyhp/parallel`

`tyhp/parallel` is not required. When it is installed and `\Tyhp\Parallel::isAvailable()` returns `true`, `Offload`, `PdoConnection`, and `Dns` run their blocking work in worker processes and the event loop stays free. Without it, the same calls run in your process and block the loop until they finish. Your code does not change either way. See [With and without tyhp/parallel](#with-and-without-tyhpparallel) below.

```bash
composer require tyhp/parallel
```

## Getting started

An application entry script can use `await` at the top level; the compiler starts the event loop for it. Put the work in an `async` function and await it:

```tyhp
<?tyhp

use Tyhp\Io\File\File;
use Tyhp\Io\Http\HttpClient;

type Release = struct {
    string $tag_name = '';
    string $published_at = '';
};

async function mainAsync(): void {
    HttpClient $github = new HttpClient(['User-Agent' => 'release-watch/1.0']);

    Release $release = await $github->getJsonAsync<Release>(
        'https://api.github.com/repos/composer/composer/releases/latest'
    );

    await File::writeAsync(__DIR__ . '/latest-release.txt', $release->tag_name . ' ' . $release->published_at . "\n");
    echo 'Latest Composer release: ' . $release->tag_name . "\n";
}

await mainAsync();
```

`getJsonAsync<Release>()` sends the request, requires a 2xx status, and decodes the JSON body into the `Release` struct. `File::writeAsync()` writes the file without holding up other fibers. If any step fails, the exception is thrown at its `await`, exactly like a synchronous call.

From synchronous code, such as a framework controller, a console command, or a library function, run a promise to completion with the event loop:

```tyhp
<?tyhp

namespace App\Console;

use Tyhp\EventLoop;
use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpResponse;

final class StatusCommand {
    public function execute(string $url): int {
        HttpResponse $response = EventLoop::getInstance()->run(HttpClient::shared()->getAsync($url));
        echo $url . ' answered ' . $response->status . "\n";
        return $response->isSuccess() ? 0 : 1;
    }
}
```

`EventLoop::run()` blocks until the promise settles and returns its value, or throws its error. To run several awaits in one go, wrap them in an `async` closure and pass it to `Promise::run()`, which returns the closure's settled value (the type argument is inferred from the closure):

```tyhp
<?tyhp

namespace App\Console;

use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpResponse;
use Tyhp\Promise;

function statusOf(string $url): int {
    HttpResponse $response = Promise::run(async fn(): HttpResponse => await HttpClient::shared()->getAsync($url));
    return $response->status;
}
```

## Concepts

### Awaiting and running work concurrently

Awaiting one call after another runs them in sequence. To run independent operations at the same time, start them all and await the combined promise:

```tyhp
<?tyhp

namespace App\Dashboard;

use Tyhp\Io\Db\DbResult;
use Tyhp\Io\Db\PostgresConnection;
use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpResponse;
use Tyhp\Promise;

async function loadDashboardAsync(HttpClient $api, PostgresConnection $db, int $userId): string {
    // All three start immediately; await waits for the slowest one.
    Promise<HttpResponse> $profile = $api->getAsync('https://api.example.com/users/' . $userId);
    Promise<HttpResponse> $notices = $api->getAsync('https://api.example.com/users/' . $userId . '/notices');
    Promise<DbResult> $orders = $db->queryAsync('SELECT id, total FROM orders WHERE user_id = $1', [$userId]);

    HttpResponse $profileResponse = await $profile;
    HttpResponse $noticesResponse = await $notices;
    DbResult $orderRows = await $orders;

    return $profileResponse->body . $noticesResponse->body . $orderRows->count();
}
```

`Promise::all()` collects many promises of the same type, and `Promise::batch()` limits how many run at once, which matters when you fan out over hundreds of URLs, files, or commands. Both come from `tyhp/async`; see [Promise Combinators](tyhp_2600_asyncAndAwait.md#promise-combinators).

Concurrency has limits inside some components:

- One `HttpClient` runs any number of requests at once.
- One `RedisClient` pipelines commands from every fiber over its single connection.
- One `DbConnection` runs **one statement at a time**, in call order. Open several connections to run queries in parallel.
- One `SocketConnection` allows one pending read at a time; writes may overlap and are sent in call order.

### Cancellation and timeouts

Most `Async` methods take an optional trailing `?CancellationToken $token`. Create the token with a `CancellationTokenSource` from `tyhp/async`, optionally with an automatic deadline in milliseconds. When the token is cancelled, the operation stops and its promise rejects with `Tyhp\Exceptions\OperationCancelledException`. A token that is already cancelled when you make the call rejects right away.

```tyhp
<?tyhp

namespace App\Deadline;

use Tyhp\CancellationTokenSource;
use Tyhp\Exceptions\OperationCancelledException;
use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpResponse;
use Tyhp\Promise;

async function fetchBothAsync(HttpClient $client): ?array<HttpResponse> {
    // One deadline for the whole operation: cancelled automatically after 3 seconds.
    $cts := new CancellationTokenSource(3000);
    try {
        array<HttpResponse> $responses = await Promise::all([
            $client->getAsync('https://a.example.com/', [], $cts->getToken()),
            $client->getAsync('https://b.example.com/', [], $cts->getToken()),
        ]);
        return $responses;
    } catch (OperationCancelledException $e) {
        return null;
    }
}
```

What cancellation does depends on the component:

| Component | On cancellation |
|-----------|-----------------|
| `HttpClient` | Aborts the transfer |
| `Process` | Kills the command (signal 9), then rejects |
| `File` | Stops at the next 256 KiB chunk; an interrupted write or copy leaves a partial file |
| `Socket::connectAsync()` | Closes the half-open connection |
| `SocketConnection` reads and writes | Stops waiting; data already buffered stays buffered |
| `RedisClient::connectAsync()` | Stops connecting (commands themselves take no token) |
| `PostgresConnection` | Sends a cancel request for the running statement, waits for the server to stop it |
| `MySqlConnection` | Runs `KILL QUERY` on a second, short-lived connection |
| `PdoConnection`, `Dns`, `Offload` | With a worker: stops that worker. Without: checked only before the work starts |

Timeouts are separate settings that reject with `Tyhp\Exceptions\TimeoutException` (which has `getTimeoutMs()`): `HttpRequest::$timeoutMs` and `$connectTimeoutMs`, `ProcessOptions::$timeoutMs`, the `$timeoutMs` argument of `Socket::connectAsync()`, `RedisOptions::$connectTimeoutMs`, and `MySqlOptions::$connectTimeoutSeconds`. For anything without its own timeout, wrap the promise in `Promise::timeout()` or pass a token from `new CancellationTokenSource($ms)`.

### Errors

All package-specific failures extend `Tyhp\Io\Exceptions\IoException`, which extends `\RuntimeException`. The subclasses tell you which component failed and carry extra data: `HttpStatusException::getResponse()`, `ProcessFailedException::getResult()`, and `DbException::getSqlState()`. The full list is in [Exceptions](#exceptions-tyhpioexceptions).

A few errors come from outside the package and do **not** extend `IoException`:

| Exception | When |
|-----------|------|
| `Tyhp\Exceptions\TimeoutException` (`tyhp/async`) | A configured timeout elapsed |
| `Tyhp\Exceptions\OperationCancelledException` (`tyhp/async`) | The token was cancelled |
| `Tyhp\Exceptions\IncompatibleTypeException` (`tyhp/core`) | Decoded JSON or a database row did not match the requested struct |
| `\JsonException` | Invalid JSON in `json()`, `getJsonAsync()`, `readJsonAsync()`, or an unencodable `postJsonAsync()` payload |
| `\InvalidArgumentException` | Invalid input: unsupported URL or address scheme, a header containing a line break, an empty command, an unknown hash algorithm, a placeholder count mismatch, an empty PDO DSN |
| `\LogicException` | A second read started on a `SocketConnection` while one is pending |
| `Tyhp\Exceptions\ParallelException` (`tyhp/parallel`) | An `Offload` job threw inside a worker process |

Failures are reported by rejecting the returned promise, so they are thrown where you `await`. Two calls throw immediately instead: `HttpClient::postJsonAsync()` throws `\JsonException` before returning when the payload cannot be encoded, and the `PdoConnection` constructor throws `\InvalidArgumentException` for an empty DSN.

### With and without tyhp/parallel

`Offload::runAsync()` sends work to `tyhp/parallel` when two things are true: the `Tyhp\Parallel` class exists (the package is installed) and `Parallel::isAvailable()` returns `true`. That is the case in a CLI process with `ext-pcntl` and `ext-posix`, or in any process (such as php-fpm) whose `TYHP_PARALLEL_SOCKET` environment variable names a running worker service. `Offload::usesWorkers()` reports the result. `PdoConnection` and `Dns` go through `Offload`, so they follow the same rule.

| | With workers | Without workers |
|-|--------------|-----------------|
| Where the job runs | A worker process | This process |
| Event loop while it runs | Free; other fibers keep running | Blocked until the job returns |
| A job that throws | Rejects with `ParallelException` (the original class is in `getRemoteClass()`) | Rejects with the original exception |
| Cancellation | Stops the worker running the job | Checked once, before the job starts |
| Job requirements | Serializable job object and result; the worker must be able to autoload the job class | None beyond `OffloadJob` |
| `PdoConnection` connections | One connection per worker for each DSN, user, and password | One cached connection in this process |

In a CLI program that never calls `Parallel::start()`, the first offloaded job starts a pool of four worker processes. Those workers are forked from your process, so start the pool before you open long-lived connections. See [The tyhp/parallel Package](package_parallel.md).

## HTTP client (`Tyhp\Io\Http`)

`HttpClient` sends HTTP and HTTPS requests through `ext-curl`. Every request made through one client shares a curl multi handle, so any number of requests run at the same time on the event loop. Every response status resolves normally, including 4xx and 5xx; call `ensureSuccess()` (or use `getJsonAsync()`) when a non-2xx status should be an error.

Only `http://` and `https://` URLs are accepted, including on redirects. Compressed responses are decoded automatically, so `HttpResponse::$body` is always the plain body.

### HttpClient

```tyhp
<?tyhp
namespace Tyhp\Io\Http;

final class HttpClient { /* ... */ }
```

:::member[HttpClient::__construct(array<string, string> $defaultHeaders = [])]
Creates a client with its own curl multi handle.

- `$defaultHeaders` — headers sent with every request. A request that sets the same header name (compared case-insensitively) replaces the default.

Create one client per set of default headers (for example one per API you talk to) and reuse it. Requests on a client run concurrently.
:::

:::member[static HttpClient::shared(): HttpClient]
Returns a process-wide client with no default headers, creating it on first use. Use it for one-off requests where you do not need default headers.
:::

:::member[HttpClient::sendAsync(HttpRequest $request, ?CancellationToken $token = null): Promise<HttpResponse>]
Starts the request described by `$request` and resolves with the response once the whole body has arrived.

- `$request` — an [`HttpRequest`](#httprequest) struct. `url` is required.
- `$token` — cancelling it aborts the transfer.

**Resolves with** an `HttpResponse` for any HTTP status.

**Rejects with**

- `\InvalidArgumentException` — the URL is not `http://` or `https://`, or a header name or value contains a line break.
- `IoUnavailableException` — `ext-curl` is not loaded.
- `HttpException` — the request failed before a response arrived: DNS, connection, TLS, too many redirects, or a transfer error. `getCode()` is the curl error number.
- `TimeoutException` — `timeoutMs` elapsed, or `connectTimeoutMs` elapsed before the connection was established. The message says `timed out connecting after {connectTimeoutMs}ms` in the second case, and `getTimeoutMs()` returns the limit that expired.
- `OperationCancelledException` — `$token` was cancelled.

How the method and body are sent:

- `HEAD` sends no body and receives none.
- `GET` with an empty body is a plain GET.
- Any other method, or a `GET` with a body, sends `body` as the request body with that method.

Request headers are merged over the client's default headers. The client sends an empty `Expect` header unless you set one, so curl does not wait for `100 Continue` before sending a body. A header whose value is `''` is sent as `Name:`, which tells curl to drop that header. When you send a body, set `Content-Type` yourself; `postJsonAsync()` does it for you.
:::

:::member[HttpClient::getAsync(string $url, array<string, string> $headers = [], ?CancellationToken $token = null): Promise<HttpResponse>]
Sends a `GET` request with the default `HttpRequest` settings (30 s timeout, 10 s connect timeout, up to 5 redirects, TLS verification on). Resolves and rejects like `sendAsync()`.

- `$headers` — extra headers for this request.
:::

:::member[HttpClient::postAsync(string $url, string $body, array<string, string> $headers = [], ?CancellationToken $token = null): Promise<HttpResponse>]
Sends a `POST` request with `$body` as the request body and the default `HttpRequest` settings. Resolves and rejects like `sendAsync()`.

Set a `Content-Type` header that describes `$body`, for example `'Content-Type' => 'application/x-www-form-urlencoded'` for `\http_build_query()` output.
:::

:::member[HttpClient::postJsonAsync(string $url, mixed $payload, array<string, string> $headers = [], ?CancellationToken $token = null): Promise<HttpResponse>]
Encodes `$payload` with `\json_encode()` and sends it as a `POST` body with `Content-Type: application/json`. Structs and arrays encode as JSON objects or arrays. Resolves and rejects like `sendAsync()`.

**Throws** `\JsonException` immediately, before a promise is returned, when `$payload` cannot be encoded.
:::

:::member[HttpClient::getJsonAsync<T extends struct>(string $url, array<string, string> $headers = [], ?CancellationToken $token = null): Promise<T>]
Sends a `GET` request, requires a 2xx status, and decodes the JSON body into the struct type `T`. Adds `Accept: application/json` unless `$headers` contains an `Accept` header; the name is matched case-insensitively, so `accept` also counts.

`T` must be a struct type, and the decoded value is checked against it the same way as `\Tyhp\Json::decode<T>()`.

**Rejects with** everything `sendAsync()` can reject with, plus:

- `HttpStatusException` — the status is outside 200–299.
- `\JsonException` — the body is not valid JSON.
- `IncompatibleTypeException` — the JSON does not match `T`.
:::

### HttpRequest

`HttpRequest` is a struct describing one request for `sendAsync()`. Build it with `new HttpRequest() with [...]` and set only the fields you need.

```tyhp
<?tyhp
namespace Tyhp\Io\Http;

type HttpRequest = struct {
    string $url = '';
    string $method = 'GET';
    array<string, string> $headers = [];
    string $body = '';
    int $timeoutMs = 30000;
    int $connectTimeoutMs = 10000;
    bool $followRedirects = true;
    int $maxRedirects = 5;
    bool $verifyTls = true;
};
```

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `url` | `string` | `''` | Absolute `http://` or `https://` URL. Required. |
| `method` | `string` | `'GET'` | HTTP method, case-insensitive. |
| `headers` | `array<string, string>` | `[]` | Header name ⇒ value. Merged over the client's default headers. |
| `body` | `string` | `''` | Request body. A non-empty body is sent with any method except `HEAD`. |
| `timeoutMs` | `int` | `30000` | Limit for the whole transfer in milliseconds. `0` means no limit. |
| `connectTimeoutMs` | `int` | `10000` | Limit for establishing the connection in milliseconds. `0` uses curl's built-in default. |
| `followRedirects` | `bool` | `true` | Follow `3xx` responses. When `false`, the redirect response itself resolves. |
| `maxRedirects` | `int` | `5` | Most redirects to follow before failing with `HttpException`. |
| `verifyTls` | `bool` | `true` | Verify the server certificate and host name. Turn off only for local testing. |

### HttpResponse

`HttpResponse` is the completed response. After redirects, `headers` and `url` describe the final response.

:::member[HttpResponse::__construct(int $status, array<string, array<int, string>> $headers, string $body, string $url)]
Creates a response. The client builds responses for you; the public constructor is useful for test doubles. Pass header names in lower case so `header()` and `headerValues()` find them.
:::

:::member[readonly int HttpResponse::$status]
The HTTP status code of the final response, for example `200` or `404`.
:::

:::member[readonly array<string, array<int, string>> HttpResponse::$headers]
Response headers keyed by lower-case name. Each name maps to every value received for it, in order, so repeated headers such as `set-cookie` keep all their values.
:::

:::member[readonly string HttpResponse::$body]
The response body, already decompressed. Empty for `HEAD` requests.
:::

:::member[readonly string HttpResponse::$url]
The URL that produced this response, after any redirects.
:::

:::member[HttpResponse::isSuccess(): bool]
Returns `true` when `status` is between 200 and 299.
:::

:::member[HttpResponse::header(string $name): ?string]
Returns the first value of header `$name` (case-insensitive), or `null` when the response does not have it.
:::

:::member[HttpResponse::headerValues(string $name): array<int, string>]
Returns every value of header `$name` (case-insensitive) in the order received, or `[]` when absent.
:::

:::member[HttpResponse::json<T extends struct>(): T]
Decodes `body` as JSON into the struct type `T`. JSON objects decode to struct-shaped arrays.

**Throws** `\JsonException` for invalid JSON and `IncompatibleTypeException` when the value does not match `T`.
:::

:::member[HttpResponse::ensureSuccess(): HttpResponse]
Returns the same response when the status is 2xx, so you can chain it: `$response->ensureSuccess()->json<User>()`.

**Throws** `HttpStatusException` for any other status. `getCode()` is the status and `getResponse()` returns this response.
:::

### HTTP examples

Calling a JSON API with default headers and typed responses:

```tyhp
<?tyhp

namespace App\Billing;

use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpResponse;

type Invoice = struct {
    string $id = '';
    int $amount_due = 0;
    string $status = '';
};

final class BillingApi {
    private HttpClient $http;

    public function __construct(private readonly string $baseUrl, string $apiKey) {
        $this->http = new HttpClient([
            'Authorization' => 'Bearer ' . $apiKey,
            'User-Agent' => 'shop-backend/2.3',
        ]);
    }

    public async function invoiceAsync(string $id): Invoice {
        return await $this->http->getJsonAsync<Invoice>($this->baseUrl . '/invoices/' . \rawurlencode($id));
    }

    public async function createInvoiceAsync(string $customerId, int $amountCents): Invoice {
        HttpResponse $response = await $this->http->postJsonAsync(
            $this->baseUrl . '/invoices',
            ['customer' => $customerId, 'amount' => $amountCents],
            ['Idempotency-Key' => \bin2hex(\random_bytes(16))]
        );
        return $response->ensureSuccess()->json<Invoice>();
    }
}
```

Building a custom request and telling the failure modes apart:

```tyhp
<?tyhp

namespace App\Sync;

use Tyhp\Exceptions\TimeoutException;
use Tyhp\Io\Exceptions\HttpException;
use Tyhp\Io\Exceptions\HttpStatusException;
use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpRequest;
use Tyhp\Io\Http\HttpResponse;

async function putDocumentAsync(HttpClient $client, string $url, string $json): bool {
    HttpRequest $request = new HttpRequest() with [
        url => $url,
        method => 'PUT',
        headers => ['Content-Type' => 'application/json'],
        body => $json,
        timeoutMs => 5000,
        followRedirects => false,
    ];

    try {
        HttpResponse $response = await $client->sendAsync($request);
        $response->ensureSuccess();
        return true;
    } catch (HttpStatusException $e) {
        // The server answered, but not with 2xx.
        HttpResponse $failed = $e->getResponse();
        \error_log('PUT ' . $url . ' returned ' . $failed->status . ': ' . $failed->body);
        return false;
    } catch (TimeoutException $e) {
        \error_log('PUT ' . $url . ' timed out after ' . $e->getTimeoutMs() . 'ms');
        return false;
    } catch (HttpException $e) {
        // No response at all: DNS, connect, TLS, or transfer failure.
        \error_log('PUT ' . $url . ' failed (curl error ' . $e->getCode() . '): ' . $e->getMessage());
        return false;
    }
}
```

`HttpStatusException` extends `HttpException`, so catch it first when you handle both.

## Processes (`Tyhp\Io\Process`)

`Process` runs external commands without blocking the event loop. The command is an argument list passed straight to the program, with no shell in between, so arguments never need quoting and cannot be interpreted as shell syntax. stdout and stderr are collected in full and returned when the command exits.

### Process

```tyhp
<?tyhp
namespace Tyhp\Io\Process;

final class Process { /* ... */ }
```

:::member[static Process::runAsync(array<int, string> $command, ?ProcessOptions $options = null, ?CancellationToken $token = null): Promise<ProcessResult>]
Starts `$command` and resolves with a [`ProcessResult`](#processresult) once it exits, **whatever its exit code**. Check `exitCode` yourself, or use `mustRunAsync()`.

- `$command` — the program followed by its arguments, for example `['git', 'log', '-1', '--format=%H']`. The program is looked up on `PATH` unless it is a path.
- `$options` — working directory, environment, stdin, and timeout. `null` uses the defaults.
- `$token` — cancelling it kills the command.

**Rejects with**

- `\InvalidArgumentException` — `$command` is empty.
- `IoException` — the command could not start, for example because the program does not exist.
- `TimeoutException` — `timeoutMs` elapsed. The command is killed first.
- `OperationCancelledException` — `$token` was cancelled. The command is killed first.

Commands run concurrently: start several and await them together. Both output streams are read as they are produced, so a command that writes a lot of output does not stall.
:::

:::member[static Process::mustRunAsync(array<int, string> $command, ?ProcessOptions $options = null, ?CancellationToken $token = null): Promise<ProcessResult>]
Like `runAsync()`, but rejects with `ProcessFailedException` when the exit code is not `0`. The exception's message includes the command, the exit code, and the trimmed stderr; `getCode()` is the exit code and `getResult()` returns the full `ProcessResult`.

Use it for commands whose failure should stop your program, such as build or deploy steps.
:::

### ProcessOptions

```tyhp
<?tyhp
namespace Tyhp\Io\Process;

type ProcessOptions = struct {
    ?string $cwd;
    ?array<string, string> $env;
    string $input = '';
    int $timeoutMs = 0;
};
```

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `cwd` | `?string` | `null` | Working directory for the command. `null` uses this process's working directory. |
| `env` | `?array<string, string>` | `null` | The command's complete environment. `null` inherits this process's environment. A non-null array **replaces** the environment, so include variables such as `PATH` or `HOME` if the command needs them. |
| `input` | `string` | `''` | Written to the command's stdin, which is then closed. With `''`, stdin is closed immediately. |
| `timeoutMs` | `int` | `0` | Kill the command and reject with `TimeoutException` after this many milliseconds. `0` means no limit. |

### ProcessResult

```tyhp
<?tyhp
namespace Tyhp\Io\Process;

type ProcessResult = struct {
    array<int, string> $command = [];
    int $exitCode = 0;
    int $signal = 0;
    string $stdout = '';
    string $stderr = '';
};
```

| Field | Type | Meaning |
|-------|------|---------|
| `command` | `array<int, string>` | The command that ran. |
| `exitCode` | `int` | The exit code. When a signal ended the command, this is `128 + signal`, as a shell reports it. |
| `signal` | `int` | The number of the signal that ended the command, or `0` when it exited normally. |
| `stdout` | `string` | Everything the command wrote to stdout. |
| `stderr` | `string` | Everything the command wrote to stderr. |

### Process examples

Running a command in a directory, with a timeout, and treating failure as an error:

```tyhp
<?tyhp

namespace App\Git;

use Tyhp\Io\Process\Process;
use Tyhp\Io\Process\ProcessOptions;
use Tyhp\Io\Process\ProcessResult;

async function currentCommitAsync(string $repoDir): string {
    ProcessResult $result = await Process::mustRunAsync(
        ['git', 'rev-parse', 'HEAD'],
        new ProcessOptions() with [cwd => $repoDir, timeoutMs => 5000]
    );
    return \trim($result->stdout);
}
```

Feeding stdin and distinguishing the ways a command can fail:

```tyhp
<?tyhp

namespace App\Json;

use Tyhp\Exceptions\TimeoutException;
use Tyhp\Io\Exceptions\IoException;
use Tyhp\Io\Exceptions\ProcessFailedException;
use Tyhp\Io\Process\Process;
use Tyhp\Io\Process\ProcessOptions;
use Tyhp\Io\Process\ProcessResult;

async function prettyPrintAsync(string $json): string {
    try {
        ProcessResult $result = await Process::mustRunAsync(
            ['jq', '.'],
            new ProcessOptions() with [input => $json, timeoutMs => 2000]
        );
        return $result->stdout;
    } catch (ProcessFailedException $e) {
        ProcessResult $failed = $e->getResult();
        throw new \RuntimeException('jq exited with ' . $failed->exitCode . ': ' . $failed->stderr, 0, $e);
    } catch (TimeoutException $e) {
        throw new \RuntimeException('jq did not finish within 2 seconds.', 0, $e);
    } catch (IoException $e) {
        // ProcessFailedException is also an IoException, so it is caught above first.
        throw new \RuntimeException('Could not start jq: ' . $e->getMessage(), 0, $e);
    }
}
```

Running many commands with bounded concurrency:

```tyhp
<?tyhp

namespace App\Lint;

use Tyhp\Io\Process\Process;
use Tyhp\Io\Process\ProcessResult;
use Tyhp\Promise;

async function lintFilesAsync(array<int, string> $files): int {
    // At most four `php -l` processes at a time.
    array<int, ProcessResult> $results = await Promise::batch(
        $files,
        fn(string $file): Promise<ProcessResult> => Process::runAsync([\PHP_BINARY, '-l', $file]),
        4
    );

    int $failures = 0;
    foreach ($results as $result) {
        if ($result->exitCode !== 0) {
            $failures++;
            echo $result->stdout . $result->stderr;
        }
    }
    return $failures;
}
```

## Files (`Tyhp\Io\File`)

PHP has no non-blocking file I/O, so `File` reads and writes in 256 KiB chunks and lets other fibers, timers, and sockets run between chunks. Each chunk still blocks briefly, but a large file no longer freezes your server while it is read or written. A cancelled token stops the operation at the next chunk; a write or copy stopped that way leaves a partial file.

Every method fails with `IoException` when a file cannot be opened, read, or written; the message includes the path and PHP's reason.

### File

```tyhp
<?tyhp
namespace Tyhp\Io\File;

final class File { /* ... */ }
```

:::member[static File::readAsync(string $path, ?CancellationToken $token = null): Promise<string>]
Reads the whole file and resolves with its contents.

**Rejects with** `IoException` when the file cannot be opened or read, and `OperationCancelledException` when `$token` is cancelled.
:::

:::member[static File::readJsonAsync<T extends struct>(string $path, ?CancellationToken $token = null): Promise<T>]
Reads the file and decodes it as JSON into the struct type `T`.

**Rejects with** everything `readAsync()` can, plus `\JsonException` for invalid JSON and `IncompatibleTypeException` when the value does not match `T`.
:::

:::member[static File::writeAsync(string $path, string $contents, ?CancellationToken $token = null): Promise<void>]
Creates the file, or truncates it if it exists, then writes `$contents`. A token that is already cancelled rejects before the file is touched.

**Rejects with** `IoException` and `OperationCancelledException`.
:::

:::member[static File::appendAsync(string $path, string $contents, ?CancellationToken $token = null): Promise<void>]
Appends `$contents` to the file, creating it if it does not exist.

**Rejects with** `IoException` and `OperationCancelledException`.
:::

:::member[static File::copyAsync(string $from, string $to, ?CancellationToken $token = null): Promise<void>]
Copies `$from` to `$to`, replacing `$to` when it exists. The source is opened first, so a missing source fails without touching `$to`.

**Rejects with** `IoException` and `OperationCancelledException`.
:::

:::member[static File::hashAsync(string $path, string $algorithm = 'sha256', ?CancellationToken $token = null): Promise<string>]
Resolves with the lower-case hex digest of the file. `$algorithm` may be any name returned by `\hash_algos()`, such as `'sha256'`, `'sha1'`, `'md5'`, or `'xxh128'`.

**Rejects with** `\InvalidArgumentException` for an unknown algorithm, plus `IoException` and `OperationCancelledException`.
:::

:::member[static File::linesAsync(string $path): AsyncIterable<string>]
Returns an async iterable over the file's lines, without loading the whole file. Iterate it with `foreach (await ...)` inside async code:

```tyhp
foreach (await File::linesAsync($path) as string $line) { /* ... */ }
```

- Lines are split on `"\n"`; the trailing `"\n"` or `"\r\n"` is removed. An empty line yields `''`, and a final line without a newline is still yielded.
- The call itself does not open the file. It opens when iteration starts, so a missing file throws `IoException` from the `foreach`, and it closes when iteration reaches the end.
- Each new iteration over the returned value reads the file again from the start.
- Other fibers run every 1,000 lines or 256 KiB, whichever comes first.

There is no token parameter. To stop early, check a token in the loop body or `break`.
:::

### File examples

Loading a typed configuration file:

```tyhp
<?tyhp

namespace App\Config;

use Tyhp\Io\File\File;

type AppConfig = struct {
    string $name = '';
    bool $debug = false;
    array<string, string> $database = [];
};

async function loadConfigAsync(string $path): AppConfig {
    return await File::readJsonAsync<AppConfig>($path);
}
```

Scanning a large log file line by line, with cancellation:

```tyhp
<?tyhp

namespace App\Logs;

use Tyhp\CancellationToken;
use Tyhp\Io\File\File;

async function countErrorsAsync(string $logPath, ?CancellationToken $token = null): int {
    int $errors = 0;
    foreach (await File::linesAsync($logPath) as string $line) {
        $token?->throwIfCancellationRequested();
        if (\str_contains($line, ' ERROR ')) {
            $errors++;
        }
    }
    return $errors;
}
```

Backing up a file under a content-addressed name and recording it:

```tyhp
<?tyhp

namespace App\Backup;

use Tyhp\Io\File\File;

async function backupAsync(string $path): string {
    string $digest = await File::hashAsync($path);
    string $target = $path . '.' . \substr($digest, 0, 12) . '.bak';
    await File::copyAsync($path, $target);
    await File::appendAsync($path . '.log', \date('c') . ' backed up to ' . $target . "\n");
    return $target;
}
```

## Sockets (`Tyhp\Io\Socket`)

`Socket::connectAsync()` opens a client connection over TCP, TLS, or a Unix-domain socket and returns a `SocketConnection` whose reads and writes wait on the event loop. Use it to speak line-based or framed protocols that have no dedicated client in this package.

### Socket

:::member[static Socket::connectAsync(string $address, int $timeoutMs = 10000, ?CancellationToken $token = null): Promise<SocketConnection>]
Connects to `$address` and resolves with an open `SocketConnection`.

- `$address` — `tcp://host:port`, `tls://host:port`, or `unix:///path/to/socket`.
- `$timeoutMs` — limit for establishing the TCP connection. `0` means no limit.
- `$token` — cancelling it abandons the attempt and closes the half-open connection.

`tls://` connects over TCP and then performs a TLS handshake that verifies the server certificate against `host`, using PHP's default OpenSSL trust settings. The `$timeoutMs` limit applies to the connection itself; to bound the TLS handshake as well, pass a token from `new CancellationTokenSource($ms)`.

**Rejects with**

- `\InvalidArgumentException` — the address does not start with `tcp://`, `tls://`, or `unix://`.
- `IoException` — the connection was refused or failed, or the TLS handshake failed.
- `TimeoutException` — `$timeoutMs` elapsed.
- `OperationCancelledException` — `$token` was cancelled.

Host names in `tcp://` and `tls://` addresses are resolved by PHP's socket connect call, which blocks briefly. For `tcp://`, you can resolve the name first with [`Dns::resolveAsync()`](#dns-tyhpiodns) and connect to an IP address.
:::

### SocketConnection

A connected, non-blocking stream. You get instances from `Socket::connectAsync()`; there is no public constructor.

One read may be pending at a time. Data that arrives beyond what a read returns stays in an internal buffer for the next read, so you can mix `readLineAsync()`, `readExactlyAsync()`, and `readAsync()` freely. Writes may overlap; they are sent in the order you called `writeAsync()`.

:::member[SocketConnection::readAsync(int $maxBytes = 65536, ?CancellationToken $token = null): Promise<string>]
Resolves with up to `$maxBytes` bytes, waiting until at least one byte is available. Resolves with `''` once the peer has closed the connection and the buffer is empty, which is how you detect end of stream.

**Rejects with** `\LogicException` when another read is pending, `IoException` when the connection is closed locally while waiting, and `OperationCancelledException`.
:::

:::member[SocketConnection::readLineAsync(int $maxBytes = 1048576, ?CancellationToken $token = null): Promise<?string>]
Resolves with the next line without its `"\n"` or `"\r\n"`. At end of stream it resolves with the final unterminated line, if any, and then with `null`.

**Rejects with** `IoException` when more than `$maxBytes` bytes arrive without a newline, plus the errors of `readAsync()`.
:::

:::member[SocketConnection::readExactlyAsync(int $length, ?CancellationToken $token = null): Promise<string>]
Resolves with exactly `$length` bytes. Use it for length-prefixed frames and fixed-size headers.

**Rejects with** `IoException` when the connection closes before `$length` bytes arrive (the bytes already received stay buffered), plus the errors of `readAsync()`.
:::

:::member[SocketConnection::writeAsync(string $data, ?CancellationToken $token = null): Promise<void>]
Resolves once every byte of `$data` has been handed to the operating system. Large writes are sent in pieces as the socket accepts them. Writes started while an earlier one is still sending wait their turn, so bytes from separate calls never interleave.

**Rejects with** `IoException` when the connection is closed or the write fails, and `OperationCancelledException` (part of `$data` may already have been sent).
:::

:::member[SocketConnection::close(): void]
Closes the connection. A read or write that is waiting rejects with `IoException`. Calling `close()` again does nothing.
:::

:::member[SocketConnection::isClosed(): bool]
Returns `true` after `close()` has been called.
:::

### Socket examples

A request/response exchange over a line protocol (here, memcached's `version` command):

```tyhp
<?tyhp

namespace App\Memcached;

use Tyhp\Io\Exceptions\IoException;
use Tyhp\Io\Socket\Socket;
use Tyhp\Io\Socket\SocketConnection;

async function memcachedVersionAsync(string $host, int $port = 11211): string {
    SocketConnection $conn = await Socket::connectAsync('tcp://' . $host . ':' . $port, 2000);
    try {
        await $conn->writeAsync("version\r\n");
        ?string $line = await $conn->readLineAsync();
        if ($line === null || !\str_starts_with($line, 'VERSION ')) {
            throw new IoException('Unexpected reply: ' . ($line ?? '(connection closed)'));
        }
        return \substr($line, 8);
    } finally {
        $conn->close();
    }
}
```

Reading length-prefixed frames (a 4-byte big-endian length followed by the payload):

```tyhp
<?tyhp

namespace App\Frames;

use Tyhp\Io\Socket\SocketConnection;

async function readFrameAsync(SocketConnection $conn): string {
    string $header = await $conn->readExactlyAsync(4);
    int $length = (\ord($header[0]) << 24) | (\ord($header[1]) << 16) | (\ord($header[2]) << 8) | \ord($header[3]);
    return await $conn->readExactlyAsync($length);
}

async function readUntilClosedAsync(SocketConnection $conn): string {
    string $all = '';
    string $chunk = await $conn->readAsync();
    while ($chunk !== '') {
        $all .= $chunk;
        $chunk = await $conn->readAsync();
    }
    return $all;
}
```

## Redis (`Tyhp\Io\Redis`)

`RedisClient` speaks the RESP2 protocol over one connection. Commands from concurrent fibers are **pipelined**: each is written as soon as you call it, without waiting for earlier replies, and each promise resolves with its own reply in order. A single client can therefore serve a whole application.

An error reply from Redis (for example `WRONGTYPE` or `ERR value is not an integer`) rejects only that command with `RedisException`; the connection stays usable. A transport failure, such as the server closing the connection, rejects every pending command and closes the client.

### RedisOptions

```tyhp
<?tyhp
namespace Tyhp\Io\Redis;

type RedisOptions = struct {
    string $host = '127.0.0.1';
    int $port = 6379;
    bool $tls = false;
    ?string $username;
    ?string $password;
    int $database = 0;
    int $connectTimeoutMs = 10000;
};
```

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `host` | `string` | `'127.0.0.1'` | Server host name or IP address. |
| `port` | `int` | `6379` | Server port. |
| `tls` | `bool` | `false` | Connect with TLS and verify the server certificate against `host`. |
| `username` | `?string` | `null` | ACL user name. Used only together with `password`. |
| `password` | `?string` | `null` | When set, the client sends `AUTH password`, or `AUTH username password` when `username` is also set. |
| `database` | `int` | `0` | When not `0`, the client sends `SELECT database` after connecting. |
| `connectTimeoutMs` | `int` | `10000` | Limit for opening the connection, in milliseconds. `0` means no limit. |

### RedisClient

:::member[static RedisClient::connectAsync(?RedisOptions $options = null, ?CancellationToken $token = null): Promise<RedisClient>]
Opens the connection, then sends `AUTH` and `SELECT` when the options ask for them. `null` options connect to `127.0.0.1:6379` without authentication.

**Rejects with** `IoException` when the connection fails, `TimeoutException` after `connectTimeoutMs`, `OperationCancelledException` when `$token` is cancelled, and `RedisException` when `AUTH` or `SELECT` is refused (the client is closed in that case).
:::

:::member[RedisClient::commandAsync(string $name, string|int|float ...$arguments): Promise<mixed>]
Sends any Redis command and resolves with its decoded reply. Arguments are converted to strings.

| Redis reply | Resolves with |
|-------------|---------------|
| Simple string (`+OK`) or bulk string | `string` |
| Integer | `int` |
| Nil bulk string or nil array | `null` |
| Array | `array<int, mixed>`, decoded recursively; an error reply nested inside becomes a `RedisException` value in the array |
| Error | rejects with `RedisException` |

Every command must produce exactly one reply. Do not send `SUBSCRIBE`, `PSUBSCRIBE`, or `MONITOR` through this client.

**Rejects with** `RedisException` for an error reply, a closed client, or a transport failure.
:::

:::member[RedisClient::pingAsync(): Promise<string>]
Sends `PING` and resolves with the reply, normally `'PONG'`.
:::

:::member[RedisClient::getAsync(string $key): Promise<?string>]
Sends `GET` and resolves with the value, or `null` when the key does not exist. Rejects with `RedisException` when the key holds a non-string type.
:::

:::member[RedisClient::setAsync(string $key, string $value, int $ttlMs = 0): Promise<void>]
Sends `SET`. A positive `$ttlMs` makes the key expire after that many milliseconds (`SET key value PX ttlMs`); `0` stores it without expiry.
:::

:::member[RedisClient::delAsync(string $key, string ...$keys): Promise<int>]
Deletes one or more keys and resolves with how many of them existed.
:::

:::member[RedisClient::existsAsync(string $key): Promise<bool>]
Resolves with `true` when `$key` exists.
:::

:::member[RedisClient::incrAsync(string $key, int $by = 1): Promise<int>]
Increments the integer stored at `$key` by `$by` (`INCRBY`) and resolves with the new value. A missing key counts as `0`. Rejects with `RedisException` when the value is not an integer.
:::

:::member[RedisClient::expireAsync(string $key, int $seconds): Promise<bool>]
Sets a time-to-live of `$seconds` on `$key`. Resolves with `false` when the key does not exist.
:::

:::member[RedisClient::hSetAsync(string $key, array<string, string> $fields): Promise<int>]
Sets the given hash fields (`HSET`) and resolves with how many of them were new.
:::

:::member[RedisClient::hGetAsync(string $key, string $field): Promise<?string>]
Resolves with one hash field's value, or `null` when the field or key does not exist.
:::

:::member[RedisClient::hGetAllAsync(string $key): Promise<array<string, string>>]
Resolves with every field and value of the hash, or `[]` when the key does not exist.
:::

:::member[RedisClient::lPushAsync(string $key, string $value, string ...$values): Promise<int>]
Prepends one or more values to a list (`LPUSH`) and resolves with the new list length.
:::

:::member[RedisClient::rPushAsync(string $key, string $value, string ...$values): Promise<int>]
Appends one or more values to a list (`RPUSH`) and resolves with the new list length.
:::

:::member[RedisClient::lRangeAsync(string $key, int $start = 0, int $stop = -1): Promise<array<int, string>>]
Resolves with the list elements from `$start` to `$stop`, both inclusive (`LRANGE`). Negative indexes count from the end; the defaults return the whole list.
:::

:::member[RedisClient::publishAsync(string $channel, string $message): Promise<int>]
Publishes `$message` on `$channel` and resolves with the number of subscribers that received it.
:::

:::member[RedisClient::close(): void]
Closes the connection. Commands still waiting for a reply reject with `RedisException`, and later commands reject immediately.
:::

:::member[RedisClient::isClosed(): bool]
Returns `true` after `close()`, or after a transport failure closed the client.
:::

### Redis examples

Using the typed helpers and falling back to `commandAsync()` for anything else:

```tyhp
<?tyhp

namespace App\Cache;

use Tyhp\Io\Exceptions\RedisException;
use Tyhp\Io\Redis\RedisClient;
use Tyhp\Io\Redis\RedisOptions;

async function sessionDemoAsync(string $password): void {
    RedisClient $redis = await RedisClient::connectAsync(new RedisOptions() with [
        host => 'cache.internal',
        password => $password,
        database => 2,
    ]);
    try {
        await $redis->hSetAsync('session:abc', ['user' => '42', 'role' => 'admin']);
        await $redis->expireAsync('session:abc', 1800);

        array<string, string> $session = await $redis->hGetAllAsync('session:abc');
        echo 'User ' . ($session['user'] ?? '?') . "\n";

        mixed $ttl = await $redis->commandAsync('TTL', 'session:abc');
        if (\is_int($ttl)) {
            echo 'Expires in ' . $ttl . " seconds\n";
        }

        try {
            await $redis->incrAsync('session:abc');
        } catch (RedisException $e) {
            // WRONGTYPE: the connection is still usable afterwards.
            echo 'Redis refused: ' . $e->getMessage() . "\n";
        }
    } finally {
        $redis->close();
    }
}
```

A fixed-window rate limiter:

```tyhp
<?tyhp

namespace App\RateLimit;

use Tyhp\Io\Redis\RedisClient;

async function allowRequestAsync(RedisClient $redis, string $clientId, int $limitPerMinute): bool {
    string $key = 'rate:' . $clientId . ':' . \intdiv(\time(), 60);
    int $count = await $redis->incrAsync($key);
    if ($count === 1) {
        await $redis->expireAsync($key, 120);
    }
    return $count <= $limitPerMinute;
}
```

## Databases (`Tyhp\Io\Db`)

The database layer has one interface, `DbConnection`, and three implementations:

| Class | Driver | Placeholders | Non-blocking? |
|-------|--------|--------------|---------------|
| `PostgresConnection` | `ext-pgsql`, libpq's asynchronous API | `$1`, `$2`, … | Connect and statements |
| `MySqlConnection` | `ext-mysqli` with `MYSQLI_ASYNC` | `?` | Statements; the connection handshake blocks |
| `PdoConnection` | Any PDO driver, run through `Offload` | `?` | Only with `tyhp/parallel` workers |

All three share these rules:

- Statements on one connection run **one at a time**, in the order you call them. Calls made while a statement is running queue up. Open more connections to run queries concurrently.
- Each `queryAsync()` runs **one** SQL statement. Use `transactionAsync()` to run several together.
- Parameters are positional `DbValue`s: `int`, `float`, `string`, `bool`, or `null`.
- Failures reject with `DbException`, whose `getSqlState()` returns the five-character SQLSTATE (for example `23505` for a unique violation in PostgreSQL) when the driver reports one.

### DbConnection

```tyhp
<?tyhp
namespace Tyhp\Io\Db;

interface DbConnection { /* ... */ }
```

Type your services against `DbConnection` when they do not care which driver is behind it. The placeholder syntax still differs between drivers.

:::member[DbConnection::queryAsync(string $sql, array<int, DbValue> $params = [], ?CancellationToken $token = null): Promise<DbResult>]
Runs one statement with positional parameters and resolves with its [`DbResult`](#dbresult).

**Rejects with** `DbException` when the statement fails (and, for `PostgresConnection` and `MySqlConnection`, when the connection has been closed), `OperationCancelledException` when `$token` is cancelled, and `\InvalidArgumentException` (`MySqlConnection`) when the number of `?` placeholders does not match `$params`.

A cancelled token on a call that is still queued behind another statement takes effect when that call's turn comes.
:::

:::member[DbConnection::transactionAsync(array<int, DbStatement> $statements, ?CancellationToken $token = null): Promise<array<int, DbResult>>]
Runs `$statements` inside one transaction and resolves with one `DbResult` per statement, in order. The first failure rolls the transaction back and rejects with that error, so either every statement takes effect or none does.

No other statement on the same connection can run between the statements of the transaction.
:::

:::member[DbConnection::close(): void]
Releases the connection. For `PostgresConnection` and `MySqlConnection`, this closes the server connection, later statements reject with `DbException`, and calling it again does nothing. For `PdoConnection`, see [its `close()`](#pdoconnection).
:::

### DbValue

:::member[type DbValue = int|float|string|bool|null]
A value bound to a statement parameter. `bool` binds as the database's boolean (or `1`/`0` where there is none) and `null` binds as SQL `NULL`.
:::

### DbStatement

```tyhp
<?tyhp
namespace Tyhp\Io\Db;

type DbStatement = struct {
    string $sql = '';
    array<int, DbValue> $params = [];
};
```

One statement for `transactionAsync()`. `params` use the connection's placeholder style.

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `sql` | `string` | `''` | One SQL statement. |
| `params` | `array<int, DbValue>` | `[]` | Positional parameter values. |

### DbResult

The rows and counts from one statement.

:::member[DbResult::__construct(array<int, array<string, mixed>> $rows = [], int $affectedRows = 0, ?string $lastInsertId = null)]
Creates a result. The connections build results for you; the public constructor is useful for test doubles.
:::

:::member[readonly array<int, array<string, mixed>> DbResult::$rows]
The returned rows, each keyed by column name. Empty for statements that return no rows.

How column values are typed depends on the driver:

- **PostgreSQL**: `int2`, `int4`, `int8`, and `oid` columns arrive as `int`; `float4` and `float8` as `float`; `bool` as `bool`; every other type (including `numeric`, dates, and `json`) as `string`.
- **MySQL**: integer and floating-point columns arrive as `int` and `float`; other columns, including `DECIMAL`, as `string`. MySQL's `BOOLEAN` is `TINYINT(1)`, so it arrives as `int`.
- **PDO**: whatever the PDO driver returns.

SQL `NULL` is always `null`.
:::

:::member[readonly int DbResult::$affectedRows]
The number of rows the statement changed. `MySqlConnection` and `PdoConnection` set it to the number of returned rows for statements that return rows; `PostgresConnection` reports libpq's row count for the command.
:::

:::member[readonly ?string DbResult::$lastInsertId]
The generated ID of the inserted row when the driver reports one: `MySqlConnection` for `AUTO_INCREMENT` columns, and `PdoConnection` when the driver's `lastInsertId()` returns one. `PostgresConnection` never sets it; add `RETURNING id` to the statement and read the returned row instead.
:::

:::member[DbResult::count(): int]
Returns the number of rows in `rows`.
:::

:::member[DbResult::first(): ?array<string, mixed>]
Returns the first row, or `null` when there are none.
:::

:::member[DbResult::scalar(): mixed]
Returns the first column of the first row, or `null` when there are no rows. Handy for `SELECT COUNT(*)` and `RETURNING id`.
:::

:::member[DbResult::rowsAs<T extends struct>(): array<int, T>]
Returns every row as the struct type `T`. Each row must have `T`'s properties with matching types; extra columns are allowed, and nullable properties may be missing.

**Throws** `IncompatibleTypeException` for the first row that does not match. Match the struct's property types to the driver's column types above; for example, a PostgreSQL `numeric` or `bigint` cast to text arrives as `string`.
:::

:::member[DbResult::firstAs<T extends struct>(): ?T]
Returns the first row as the struct type `T`, or `null` when there are no rows.

**Throws** `IncompatibleTypeException` when the row does not match `T`.
:::

### PostgresConnection

PostgreSQL over `ext-pgsql`'s asynchronous libpq API. Connecting, sending statements, and waiting for results all run on the event loop. Placeholders are `$1`, `$2`, …

Parameters are sent as text and PostgreSQL infers their types from the statement. Where it cannot, such as a bare `SELECT $1`, add a cast like `$1::int`. A `bool` parameter is sent as `t`/`f`, and non-finite floats as `NaN`, `Infinity`, or `-Infinity`.

:::member[static PostgresConnection::connectAsync(string $connectionString, ?CancellationToken $token = null): Promise<PostgresConnection>]
Opens a new connection using a libpq connection string, for example `"host=127.0.0.1 port=5432 dbname=app user=app password=secret"`. Every call opens a separate connection.

**Rejects with** `IoUnavailableException` when `ext-pgsql` is not loaded, `DbException` when the connection fails, and `OperationCancelledException` when `$token` is cancelled.
:::

:::member[PostgresConnection::queryAsync(string $sql, array<int, DbValue> $params = [], ?CancellationToken $token = null): Promise<DbResult>]
Runs one statement. See [`DbConnection::queryAsync()`](#dbconnection).

Cancelling `$token` while the statement runs sends a cancel request to the server, waits for it to stop the statement, and then rejects with `OperationCancelledException`. The connection stays usable.
:::

:::member[PostgresConnection::transactionAsync(array<int, DbStatement> $statements, ?CancellationToken $token = null): Promise<array<int, DbResult>>]
Runs the statements between `BEGIN` and `COMMIT`, and sends `ROLLBACK` when any of them fails or is cancelled. See [`DbConnection::transactionAsync()`](#dbconnection).
:::

:::member[PostgresConnection::close(): void]
Closes the connection.
:::

### MySqlConnection

MySQL and MariaDB over `ext-mysqli` with `MYSQLI_ASYNC` queries. The connection handshake blocks the event loop; statements do not.

Placeholders are `?`. They are replaced on the client with escaped literals before the statement is sent: strings are escaped and quoted, `bool` becomes `1` or `0`, and `null` becomes `NULL`. A `?` inside a quoted string, a backtick-quoted identifier, or a comment (`#`, `-- `, `/* */`) is not a placeholder.

### MySqlOptions

```tyhp
<?tyhp
namespace Tyhp\Io\Db;

type MySqlOptions = struct {
    string $host = '127.0.0.1';
    int $port = 3306;
    string $user = 'root';
    string $password = '';
    string $database = '';
    string $charset = 'utf8mb4';
    ?string $socket;
    int $connectTimeoutSeconds = 10;
};
```

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `host` | `string` | `'127.0.0.1'` | Server host name or IP address. |
| `port` | `int` | `3306` | Server port. |
| `user` | `string` | `'root'` | User name. |
| `password` | `string` | `''` | Password. |
| `database` | `string` | `''` | Default database. `''` selects none. |
| `charset` | `string` | `'utf8mb4'` | Connection character set. |
| `socket` | `?string` | `null` | Unix socket path. `mysqli` uses it only when `host` is `localhost`; any other `host` connects over TCP and ignores it. |
| `connectTimeoutSeconds` | `int` | `10` | Connection timeout in seconds. |

:::member[static MySqlConnection::connectAsync(?MySqlOptions $options = null, ?CancellationToken $token = null): Promise<MySqlConnection>]
Opens a new connection and sets its character set. `null` options use the defaults above. The handshake blocks the event loop until it completes or `connectTimeoutSeconds` elapses.

**Rejects with** `IoUnavailableException` when `ext-mysqli` is not loaded, `DbException` when the connection or `charset` fails, and `OperationCancelledException` when `$token` was already cancelled.
:::

:::member[MySqlConnection::queryAsync(string $sql, array<int, DbValue> $params = [], ?CancellationToken $token = null): Promise<DbResult>]
Runs one statement. See [`DbConnection::queryAsync()`](#dbconnection).

**Rejects with** `\InvalidArgumentException` when the number of `?` placeholders does not match `$params` or a float parameter is `NAN` or infinite, in addition to the common errors.

Cancelling `$token` while the statement runs opens a second, short-lived connection with the same options, runs `KILL QUERY` for this connection's statement, and then rejects with `OperationCancelledException`.
:::

:::member[MySqlConnection::transactionAsync(array<int, DbStatement> $statements, ?CancellationToken $token = null): Promise<array<int, DbResult>>]
Runs the statements between `START TRANSACTION` and `COMMIT`, and sends `ROLLBACK` when any of them fails or is cancelled. Use a transactional storage engine such as InnoDB. See [`DbConnection::transactionAsync()`](#dbconnection).
:::

:::member[MySqlConnection::close(): void]
Closes the connection.
:::

### PdoConnection

Any PDO driver, with each call run through [`Offload`](#offloading-blocking-work-tyhpio). With `tyhp/parallel` workers available, statements run in a worker process that keeps one PDO connection per DSN, user name, and password, so the event loop stays free. Without workers, they run in this process and block the loop.

Placeholders are `?`, bound in order: `null` as `PDO::PARAM_NULL`, `bool` as `PDO::PARAM_BOOL`, `int` as `PDO::PARAM_INT`, and anything else as a string. `PDO::ATTR_ERRMODE` is always `PDO::ERRMODE_EXCEPTION`, and every `\PDOException` is reported as `DbException` with the SQLSTATE from PDO's error info.

### PdoOptions

```tyhp
<?tyhp
namespace Tyhp\Io\Db;

type PdoOptions = struct {
    string $dsn = '';
    ?string $username;
    ?string $password;
    array<int, int|string|bool> $attributes = [];
};
```

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `dsn` | `string` | `''` | PDO data source name, for example `'sqlite:/var/lib/app/app.sqlite'` or `'mysql:host=db;dbname=shop'`. Required. |
| `username` | `?string` | `null` | User name passed to `\PDO`. |
| `password` | `?string` | `null` | Password passed to `\PDO`. |
| `attributes` | `array<int, int\|string\|bool>` | `[]` | Driver attributes passed to the `\PDO` constructor, keyed by `\PDO::ATTR_*` constant. |

:::member[PdoConnection::__construct(PdoOptions $options)]
Creates the connection object. No connection is opened until the first statement runs.

**Throws** `\InvalidArgumentException` immediately when `dsn` is empty.
:::

:::member[PdoConnection::queryAsync(string $sql, array<int, DbValue> $params = [], ?CancellationToken $token = null): Promise<DbResult>]
Prepares and runs one statement. See [`DbConnection::queryAsync()`](#dbconnection).

Each call may run in a different worker. Session state set by one call (for example `SET` variables, temporary tables, or `BEGIN` / `COMMIT`) is not guaranteed to be visible to the next one; use `transactionAsync()` for anything that must run on the same connection.

**Rejects with** `DbException` for any PDO error, `OperationCancelledException`, and, without workers, `IoUnavailableException` when `ext-pdo` is missing. With workers, a failure that is not a PDO error (such as a missing extension in the worker) rejects with `ParallelException`.
:::

:::member[PdoConnection::transactionAsync(array<int, DbStatement> $statements, ?CancellationToken $token = null): Promise<array<int, DbResult>>]
Runs the whole transaction in a single offloaded call: `beginTransaction()`, every statement, then `commit()`, with `rollBack()` on the first failure. See [`DbConnection::transactionAsync()`](#dbconnection).
:::

:::member[PdoConnection::close(): void]
Forgets this process's cached PDO connection for these options. Connections held by workers stay open for later calls with the same options. The object stays usable: a later statement opens a new connection.
:::

### Database examples

A repository that maps rows to structs, with a transaction:

```tyhp
<?tyhp

namespace App\Orders;

use Tyhp\Io\Db\DbConnection;
use Tyhp\Io\Db\DbResult;
use Tyhp\Io\Db\DbStatement;
use Tyhp\Io\Exceptions\DbException;

type OrderRow = struct {
    int $id = 0;
    string $status = '';
    ?string $note;
};

final class OrderRepository {
    public function __construct(private readonly DbConnection $db) {}

    public async function openOrdersAsync(int $customerId): array<int, OrderRow> {
        DbResult $result = await $this->db->queryAsync(
            'SELECT id, status, note FROM orders WHERE customer_id = $1 AND status <> $2 ORDER BY id',
            [$customerId, 'closed']
        );
        return $result->rowsAs<OrderRow>();
    }

    public async function createAsync(int $customerId, string $note): int {
        DbResult $result = await $this->db->queryAsync(
            'INSERT INTO orders (customer_id, status, note) VALUES ($1, $2, $3) RETURNING id',
            [$customerId, 'open', $note]
        );
        mixed $id = $result->scalar();
        return \is_int($id) ? $id : throw new \UnexpectedValueException('No id returned.');
    }

    public async function transferAsync(int $fromAccount, int $toAccount, int $cents): void {
        try {
            array<int, DbResult> $results = await $this->db->transactionAsync([
                new DbStatement() with [
                    sql => 'UPDATE accounts SET balance = balance - $1 WHERE id = $2 AND balance >= $1',
                    params => [$cents, $fromAccount],
                ],
                new DbStatement() with [
                    sql => 'UPDATE accounts SET balance = balance + $1 WHERE id = $2',
                    params => [$cents, $toAccount],
                ],
            ]);
        } catch (DbException $e) {
            if ($e->getSqlState() === '40001') {
                throw new \RuntimeException('Serialization failure; retry the transfer.', 0, $e);
            }
            throw $e;
        }
        if ($results[0]->affectedRows !== 1) {
            throw new \DomainException('Insufficient funds.');
        }
    }
}
```

Note that the insufficient-funds check runs after the transaction has committed both updates; in a real system, enforce the rule inside the database (for example with a `CHECK (balance >= 0)` constraint) so a violation rolls the transaction back.

Running queries in parallel on separate connections:

```tyhp
<?tyhp

namespace App\Reports;

use Tyhp\Io\Db\DbResult;
use Tyhp\Io\Db\PostgresConnection;
use Tyhp\Promise;

async function countsAsync(string $dsn): string {
    PostgresConnection $a = await PostgresConnection::connectAsync($dsn);
    PostgresConnection $b = await PostgresConnection::connectAsync($dsn);
    try {
        array<DbResult> $results = await Promise::all([
            $a->queryAsync('SELECT count(*)::int FROM orders'),
            $b->queryAsync('SELECT count(*)::int FROM customers'),
        ]);
        return 'orders=' . (string) $results[0]->scalar() . ' customers=' . (string) $results[1]->scalar();
    } finally {
        $a->close();
        $b->close();
    }
}
```

MySQL and PDO use `?` placeholders and report generated IDs through `lastInsertId`:

```tyhp
<?tyhp

namespace App\Catalog;

use Tyhp\Io\Db\DbResult;
use Tyhp\Io\Db\MySqlConnection;
use Tyhp\Io\Db\MySqlOptions;
use Tyhp\Io\Db\PdoConnection;
use Tyhp\Io\Db\PdoOptions;

async function addProductAsync(string $name, float $price): ?string {
    MySqlConnection $db = await MySqlConnection::connectAsync(new MySqlOptions() with [
        host => 'db.internal',
        user => 'shop',
        password => 'secret',
        database => 'shop',
    ]);
    try {
        DbResult $insert = await $db->queryAsync(
            'INSERT INTO products (name, price, active) VALUES (?, ?, ?)',
            [$name, $price, true]
        );
        return $insert->lastInsertId;
    } finally {
        $db->close();
    }
}

async function recordVisitAsync(string $path): void {
    PdoConnection $db = new PdoConnection(new PdoOptions() with [dsn => 'sqlite:/var/lib/app/stats.sqlite']);
    await $db->queryAsync('CREATE TABLE IF NOT EXISTS visits (path TEXT, at INTEGER)');
    await $db->queryAsync('INSERT INTO visits (path, at) VALUES (?, ?)', [$path, \time()]);
}
```

## Offloading blocking work (`Tyhp\Io`)

Some work blocks no matter what: CPU-heavy computation, a third-party SDK that uses blocking I/O, or a PHP extension without an asynchronous API. `Offload` runs that work in a `tyhp/parallel` worker process when one is available, so the event loop keeps serving other fibers. Without workers it runs the job in your process, so the same code works everywhere and only the blocking behavior changes. See [With and without tyhp/parallel](#with-and-without-tyhpparallel).

### OffloadJob

:::member[interface OffloadJob<T extends void|mixed = mixed>]
The blocking work for `Offload::runAsync()`. Implement it in a small class that holds the job's inputs as properties.

When the job runs in a worker, it follows the rules of `ParallelTask` from `tyhp/parallel`: the job object and its result must be serializable, and the worker must be able to autoload the job's class. Keep inputs and results to plain data (scalars, arrays, structs, and simple value objects); do not capture open connections, resources, or closures.
:::

:::member[OffloadJob::run(): T]
Does the work and returns its result. It runs synchronously, either in a worker or in your process. Exceptions it throws reject the `runAsync()` promise.
:::

### Offload

:::member[static Offload::runAsync<T extends void|mixed>(OffloadJob<T> $job, ?CancellationToken $token = null): Promise<__Awaited<T>>]
Runs `$job->run()` and resolves with its result.

- With workers: the job is serialized and queued to the worker pool, and this process keeps running other fibers. Cancelling `$token` stops the worker running the job.
- Without workers: the job runs immediately in this process and blocks the event loop until it returns. `$token` is checked only before the job starts.

`T` is inferred from the job class, so `Offload::runAsync(new HashPasswordJob($password))` needs no type argument.

**Rejects with**

- `OperationCancelledException` — `$token` was cancelled.
- With workers: `ParallelException` when the job throws or the worker fails; `getRemoteClass()` and `getRemoteError()` describe the exception from the worker. `IoException` when the job's result does not match `T`.
- Without workers: whatever the job throws.
:::

:::member[static Offload::usesWorkers(): bool]
Returns `true` when `runAsync()` sends jobs to `tyhp/parallel` workers: the package is installed and `\Tyhp\Parallel::isAvailable()` is `true`. Use it for logging or to decide whether offloading a very small job is worth it.
:::

### Offload example

Hashing passwords without stalling other requests:

```tyhp
<?tyhp

namespace App\Auth;

use Tyhp\Exceptions\ParallelException;
use Tyhp\Io\Offload;
use Tyhp\Io\OffloadJob;

final class HashPasswordJob implements OffloadJob<string> {
    public function __construct(private readonly string $password) {}

    public function run(): string {
        return \password_hash($this->password, \PASSWORD_BCRYPT, ['cost' => 12]);
    }
}

async function hashPasswordAsync(string $password): string {
    try {
        return await Offload::runAsync(new HashPasswordJob($password));
    } catch (ParallelException $e) {
        \error_log('Hashing failed in worker (' . $e->getRemoteClass() . '): ' . $e->getMessage());
        throw $e;
    }
}
```

## DNS (`Tyhp\Io\Dns`)

### Dns

:::member[static Dns::resolveAsync(string $host, ?CancellationToken $token = null): Promise<array<int, string>>]
Resolves `$host` through the system resolver, run with `Offload`. Resolves with its IPv4 addresses (including `/etc/hosts` entries) followed by any IPv6 addresses from DNS, without duplicates. An IP address resolves to itself.

**Rejects with** `IoException` when nothing resolves and the lookup runs in this process. When `Offload` runs the lookup in a worker (see `Offload::usesWorkers()`), every failure, including nothing resolving, rejects with `ParallelException`; `getRemoteClass()` names `IoException` for that case.

Without `tyhp/parallel` workers, the lookup blocks the event loop like any other blocking resolver call.
:::

```tyhp
<?tyhp

namespace App\Net;

use Tyhp\Io\Dns\Dns;

async function printAddressesAsync(string $host): void {
    array<int, string> $addresses = await Dns::resolveAsync($host);
    foreach ($addresses as $address) {
        echo $host . ' => ' . $address . "\n";
    }
}
```

## Exceptions (`Tyhp\Io\Exceptions`)

```text
\RuntimeException
└── IoException
    ├── IoUnavailableException
    ├── HttpException
    │   └── HttpStatusException
    ├── ProcessFailedException
    ├── DbException
    └── RedisException
```

Catch `IoException` to handle any failure from this package in one place. Remember that timeouts, cancellation, JSON errors, and struct mismatches use the exception types listed under [Errors](#errors), which are not `IoException`s.

### IoException

:::member[class IoException extends \RuntimeException]
Base class for failures reported by `tyhp/io`. Thrown directly for file errors, socket errors, a command that cannot start, a failed DNS lookup, and an offloaded result of the wrong type.
:::

:::member[IoException::__construct(string $message, int $code = 0, ?\Throwable $previous = null)]
Creates the exception. Useful when your own code wraps lower-level I/O failures.
:::

### IoUnavailableException

:::member[final class IoUnavailableException extends IoException]
Thrown when this PHP process lacks the extension an operation needs, for example `HttpClient requires the PHP curl extension.`
:::

:::member[IoUnavailableException::__construct(string $message, ?\Throwable $previous = null)]
Creates the exception.
:::

### HttpException

:::member[class HttpException extends IoException]
Thrown when an HTTP request fails before a response arrives: DNS, connection, TLS, too many redirects, or transfer errors. `getCode()` is the curl error number.
:::

:::member[HttpException::__construct(string $message, int $code = 0, ?\Throwable $previous = null)]
Creates the exception.
:::

### HttpStatusException

:::member[final class HttpStatusException extends HttpException]
Thrown by `HttpResponse::ensureSuccess()` (and therefore by `HttpClient::getJsonAsync()`) for a status outside 200–299. The message is `HTTP <status> from <url>` and `getCode()` is the status.
:::

:::member[HttpStatusException::__construct(HttpResponse $response)]
Creates the exception for `$response`.
:::

:::member[HttpStatusException::getResponse(): HttpResponse]
Returns the response that failed, so you can read its body and headers (for example an API's error document or a `retry-after` header).
:::

### ProcessFailedException

:::member[final class ProcessFailedException extends IoException]
Thrown by `Process::mustRunAsync()` when the command exits with a non-zero code. The message includes the command, the exit code, and the trimmed stderr; `getCode()` is the exit code.
:::

:::member[ProcessFailedException::__construct(ProcessResult $result)]
Creates the exception for `$result`.
:::

:::member[ProcessFailedException::getResult(): ProcessResult]
Returns the finished command's result, including its complete stdout and stderr.
:::

### DbException

:::member[final class DbException extends IoException]
Thrown when a database connection or statement fails, or a statement is sent on a closed connection.
:::

:::member[DbException::__construct(string $message, string $sqlState = '', ?\Throwable $previous = null)]
Creates the exception.
:::

:::member[DbException::getSqlState(): string]
Returns the five-character SQLSTATE when the driver reports one (for example `23505` or `23000` for a duplicate key, `42601` for a syntax error), or `''`.
:::

### RedisException

:::member[final class RedisException extends IoException]
Thrown for a Redis error reply, a command on a closed client, or a connection failure while commands are pending. Error replies nested in an array reply appear as `RedisException` values inside the array instead of being thrown.
:::

:::member[RedisException::__construct(string $message, ?\Throwable $previous = null)]
Creates the exception.
:::

## Worked examples

### Checking a list of links

This command reads URLs from a file, checks them with at most eight requests in flight, stops everything after two minutes, and writes a report of broken links.

```tyhp
<?tyhp

namespace App\LinkCheck;

use Tyhp\CancellationToken;
use Tyhp\CancellationTokenSource;
use Tyhp\Exceptions\TimeoutException;
use Tyhp\Io\Exceptions\HttpException;
use Tyhp\Io\File\File;
use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpRequest;
use Tyhp\Io\Http\HttpResponse;
use Tyhp\Promise;

type LinkStatus = struct {
    string $url = '';
    int $status = 0;
    string $error = '';
};

async function checkLinkAsync(HttpClient $client, string $url, CancellationToken $token): LinkStatus {
    HttpRequest $request = new HttpRequest() with [url => $url, method => 'HEAD', timeoutMs => 10_000];
    try {
        HttpResponse $response = await $client->sendAsync($request, $token);
        return new LinkStatus() with [url => $url, status => $response->status];
    } catch (TimeoutException $e) {
        return new LinkStatus() with [url => $url, error => 'timed out'];
    } catch (HttpException $e) {
        return new LinkStatus() with [url => $url, error => $e->getMessage()];
    } catch (\InvalidArgumentException $e) {
        return new LinkStatus() with [url => $url, error => 'not an http(s) URL'];
    }
}

async function checkLinksAsync(string $listPath, string $reportPath): int {
    array<int, string> $urls = [];
    foreach (await File::linesAsync($listPath) as string $line) {
        string $url = \trim($line);
        if ($url !== '' && !\str_starts_with($url, '#')) {
            $urls[] = $url;
        }
    }

    HttpClient $client = new HttpClient(['User-Agent' => 'link-checker/1.0']);
    $cts := new CancellationTokenSource(120_000);
    CancellationToken $token = $cts->getToken();

    array<int, LinkStatus> $results = await Promise::batch(
        $urls,
        fn(string $url): Promise<LinkStatus> => checkLinkAsync($client, $url, $token),
        8
    );

    string $report = '';
    int $broken = 0;
    foreach ($results as $result) {
        if ($result->error !== '' || $result->status >= 400) {
            $broken++;
            $report .= $result->url . "\t" . ($result->error !== '' ? $result->error : (string) $result->status) . "\n";
        }
    }
    await File::writeAsync($reportPath, $report);
    return $broken;
}
```

If the two-minute deadline passes, the requests still in flight reject with `OperationCancelledException`, which `checkLinkAsync()` does not catch, so `checkLinksAsync()` fails with it as well.

### A cache-aside repository with Redis and PostgreSQL

Reads go to Redis first and fall back to PostgreSQL. Cache problems are logged and never fail the request, because the database remains the source of truth.

```tyhp
<?tyhp

namespace App\Products;

use Tyhp\Io\Db\DbResult;
use Tyhp\Io\Db\PostgresConnection;
use Tyhp\Io\Exceptions\RedisException;
use Tyhp\Io\Redis\RedisClient;
use Tyhp\Json;

type Product = struct {
    int $id = 0;
    string $name = '';
    int $price_cents = 0;
};

final class ProductRepository {
    public function __construct(
        private readonly PostgresConnection $db,
        private readonly RedisClient $cache
    ) {}

    public async function findAsync(int $id): ?Product {
        string $key = 'product:' . $id;
        try {
            ?string $cached = await $this->cache->getAsync($key);
            if ($cached !== null) {
                return Json::decode<Product>($cached);
            }
        } catch (RedisException $e) {
            \error_log('cache read failed: ' . $e->getMessage());
        }

        DbResult $result = await $this->db->queryAsync(
            'SELECT id, name, price_cents FROM products WHERE id = $1',
            [$id]
        );
        ?Product $product = $result->firstAs<Product>();
        if ($product !== null) {
            try {
                await $this->cache->setAsync($key, \json_encode($product, \JSON_THROW_ON_ERROR), 300_000);
            } catch (RedisException $e) {
                \error_log('cache write failed: ' . $e->getMessage());
            }
        }
        return $product;
    }
}
```

Because `price_cents` is declared `int`, the column must be an integer type (`int4`, `int8`, …) for `firstAs<Product>()` to succeed; a `numeric` column would arrive as a string.

### A deploy script

An application entry script that updates a checkout, installs PHP and JavaScript dependencies at the same time, and checks a health endpoint. Any failing step stops the script with a message that includes the command's stderr.

```tyhp
<?tyhp

use Tyhp\Io\Exceptions\ProcessFailedException;
use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpResponse;
use Tyhp\Io\Process\Process;
use Tyhp\Io\Process\ProcessOptions;
use Tyhp\Io\Process\ProcessResult;
use Tyhp\Promise;

async function deployAsync(string $repoDir, string $healthUrl): int {
    ProcessOptions $inRepo = new ProcessOptions() with [cwd => $repoDir, timeoutMs => 300_000];
    try {
        await Process::mustRunAsync(['git', 'pull', '--ff-only'], $inRepo);

        array<ProcessResult> $steps = await Promise::all([
            Process::mustRunAsync(['composer', 'install', '--no-dev', '--no-interaction'], $inRepo),
            Process::mustRunAsync(['npm', 'ci'], $inRepo),
        ]);
        foreach ($steps as $step) {
            echo \implode(' ', $step->command) . " finished\n";
        }
    } catch (ProcessFailedException $e) {
        echo 'Deploy step failed: ' . $e->getMessage() . "\n";
        return 1;
    }

    HttpResponse $health = await HttpClient::shared()->getAsync($healthUrl);
    if (!$health->isSuccess()) {
        echo 'Health check returned ' . $health->status . "\n";
        return 1;
    }
    echo "Deploy complete\n";
    return 0;
}

exit(await deployAsync('/srv/app', 'https://app.example.com/health'));
```

## Gotchas

:::warning Connections run one statement at a time
A `DbConnection` queues statements, so `Promise::all()` over several queries on **one** connection runs them one after another. Open a connection per concurrent query (or keep a small pool of connections) when you need parallel database work.
:::

:::warning Catching `IoException` does not catch timeouts or cancellation
`TimeoutException` and `OperationCancelledException` come from `tyhp/async` and extend `\RuntimeException` directly. Catch them separately, or catch `\Throwable` at the top of a request.
:::

:::warning Everything a `RedisClient` does shares one connection
Commands from every fiber are pipelined on the same connection, so connection state is shared. `SELECT`, `MULTI` / `EXEC`, and `WATCH` sent through `commandAsync()` affect, or are interleaved with, commands from other fibers. A blocking command such as `BLPOP` holds up every command queued behind it. Use a separate client for those.
:::

:::warning Redis commands have no timeout or token
Only `connectAsync()` takes a timeout and a token. To give a command a deadline, wrap it: `await Promise::timeout($redis->getAsync($key), 500)`. The command still completes on the server, and its reply is discarded.
:::

:::warning `PdoConnection` statements may run in different workers
Do not split a transaction across `queryAsync()` calls (`BEGIN`, statements, `COMMIT`) or rely on session state between calls. Use `transactionAsync()`. Connections are cached per DSN, user name, and password, so two `PdoConnection` objects with the same values share a connection, and the `attributes` of the first one to connect apply.
:::

:::warning Without `tyhp/parallel`, PDO, DNS, and `Offload` block
They still work, but the event loop waits for each call. In a server that handles many requests in one process, install `tyhp/parallel` or prefer `PostgresConnection` / `MySqlConnection`, which do not need workers.
:::

:::warning Fork the worker pool before opening connections
In a CLI program, the `tyhp/parallel` pool is forked from your process the first time `Offload`, `PdoConnection`, or `Dns` needs a worker. Call `\Tyhp\Parallel::start()` at startup, before opening database, Redis, or socket connections, so the workers do not inherit them.
:::

:::warning HTTP error statuses resolve
`getAsync()`, `postAsync()`, `postJsonAsync()`, and `sendAsync()` resolve for 404 and 500 responses. Check `isSuccess()` or call `ensureSuccess()`. Only `getJsonAsync()` checks the status for you.
:::

:::warning `ProcessOptions::$env` replaces the environment
Setting `env` gives the command exactly those variables. Start from `\getenv()` and add to it when the command needs the rest of your environment.
:::

:::warning Entire command output is held in memory
`ProcessResult` contains the complete stdout and stderr. For commands that produce very large output, redirect it to a file with the command's own options and read that file with `File::linesAsync()`.
:::

:::tip Reuse clients
Create one `HttpClient` per API and one `RedisClient` per Redis server for your whole process, and share them between fibers. Both are built for concurrent use.
:::

:::tip The struct-typed helpers need struct types
`getJsonAsync<T>()`, `json<T>()`, `readJsonAsync<T>()`, `rowsAs<T>()`, and `firstAs<T>()` accept a struct type for `T`. When an API returns a top-level JSON array, read the body with `HttpResponse::$body` and decode it yourself.
:::

## Related pages

- [Async and Await](tyhp_2600_asyncAndAwait.md) — `async`, `await`, `Promise` combinators, async iteration, and cancellation tokens.
- [The tyhp/async Package](package_async.md) — `Promise`, `EventLoop`, `CancellationTokenSource`, `TimeoutException`, and `OperationCancelledException`.
- [The tyhp/parallel Package](package_parallel.md) — worker pools, `Parallel::start()`, worker services for php-fpm, and `ParallelException`.
- [The tyhp/core Package](package_core.md) — `Json::decode()` and `IncompatibleTypeException`.
- [Structs](tyhp_0400_structs.md) and [The With Keyword](tyhp_2200_withKeyword.md) — building `HttpRequest`, `ProcessOptions`, and the other option structs.
- [Generics](tyhp_0500_generics.md) — type arguments such as `getJsonAsync<Invoice>()`.
- [Disposables](tyhp_2300_disposables.md) — the `:=` operator used with `CancellationTokenSource`.
- [Composer Runtime Packages](project_composerPackages.md) — how `tyhp/*` package versions are published and pinned.
- [Runtime packages overview](package_intro.md) — every `tyhp/*` package at a glance.
