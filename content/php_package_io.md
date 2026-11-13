---
title: 'tyhp/io for PHP'
---

`tyhp/io` does HTTP, process, file, socket, Redis, PostgreSQL, MySQL, PDO, and DNS work on the `tyhp/async` event loop. When `tyhp/parallel` is installed and a pool is available, PDO and `Offload` run on a worker instead of blocking the loop. DNS uses the `tyhp` module when that module is loaded at `0.1.0` or newer, and uses `Offload` otherwise. The namespace is `Tyhp\Io\`. It depends on `tyhp/core` and `tyhp/async`. `tyhp/parallel` is optional. `ext-tyhp` is optional.

Shared call syntax is on [Packages for PHP](php_packages.md). Waiting, cancellation, and `async` / `await` are on [tyhp/async for PHP](php_package_async.md).

## Install

PHP 8.2 or newer. No extension is required until you call the class that needs one. The package version is `0.4`:

```bash
composer require tyhp/io:805.0.4
```

`ext-tyhp` is not required. `tyhp/io` suggests it. No Tyhp package requires it. Installing it is recommended. It improves the performance and stability of Tyhp runtime code, and DNS lookups use it when it is loaded. The loaded module name is `tyhp`. Install it with PIE, not `composer require`:

```bash
pie install tyhp/ext-tyhp
```

The runtime checks `extension_loaded('tyhp')` once per process, then `phpversion('tyhp') >= 0.1.0`. A missing or older module is ignored. There is no warning. DNS then uses `Offload`.

| Suggested | Used by |
|-----------|---------|
| `ext-curl` | `HttpClient` |
| `ext-pgsql` | `PostgresConnection` |
| `ext-mysqli` | `MySqlConnection` |
| `ext-pdo` | `PdoConnection` |
| `ext-tyhp` | Faster runtime checks, and DNS off the event loop. Install with `pie install tyhp/ext-tyhp` |
| `tyhp/parallel` | PDO and `Offload` run in workers. DNS goes through `Offload`, so it uses a worker, when `ext-tyhp` is not in use |

A missing `ext-curl`, `ext-pgsql`, `ext-mysqli`, or `ext-pdo` throws `\Tyhp\Io\Exceptions\IoUnavailableException` the first time you use that class. The message names the extension, for example `HttpClient requires the PHP curl extension.` A missing `tyhp` module does not throw.

Option values (`HttpRequest`, `ProcessOptions`, `RedisOptions`, `MySqlOptions`, `PdoOptions`) and `ProcessResult` are arrays. A JSON object you decode is an array as well.

## Quick start

`HttpClient::shared()` is a process-wide client. `getAsync` returns a promise. `await` runs the loop and returns the response. A 4xx or 5xx still resolves. Call `ensureSuccess()` when those should throw.

```php
use function Tyhp\await;

require 'vendor/autoload.php';

$response = await(\Tyhp\Io\Http\HttpClient::shared()->getAsync('https://example.com'));
echo $response->status, "\n";
echo $response->body, "\n";
```

## Which calls take types first

`getJsonAsync`, `File::readJsonAsync`, `HttpResponse::json`, `DbResult::rowsAs`, and `DbResult::firstAs` take the struct type first. `Offload::runAsync` takes its result type first. The other methods on this page are ordinary calls and return a promise you `await`, except `File::linesAsync`, which returns an async iterable.

## HTTP

`new \Tyhp\Io\Http\HttpClient(array $defaultHeaders = [])`, or `HttpClient::shared()`.

| Method | Arguments | Returns |
|--------|-----------|---------|
| `sendAsync($request, ?\Tyhp\CancellationToken $token = null)` | An `HttpRequest` array | Promise of `HttpResponse` |
| `getAsync(string $url, array $headers = [], ?\Tyhp\CancellationToken $token = null)` | | Promise of `HttpResponse` |
| `postAsync(string $url, string $body, array $headers = [], ?\Tyhp\CancellationToken $token = null)` | | Promise of `HttpResponse` |
| `postJsonAsync(string $url, mixed $payload, array $headers = [], ?\Tyhp\CancellationToken $token = null)` | Encodes `$payload` as JSON. Throws `\JsonException` when it cannot. | Promise of `HttpResponse` |
| `getJsonAsync($type)(string $url, array $headers = [], ?\Tyhp\CancellationToken $token = null)` | Types first. Sends `Accept: application/json` unless `$headers` already sets `Accept`. | Promise of the decoded array |

An `HttpRequest` array is what `sendAsync` takes. `getAsync`, `postAsync`, and `postJsonAsync` build that array for you. `sendAsync` does not fill missing keys. Pass `url`, `method`, `headers`, `body`, `timeoutMs`, `connectTimeoutMs`, `followRedirects`, `maxRedirects`, and `verifyTls`. `getAsync` uses method `GET`, an empty body, a 30000 ms timeout, a 10000 ms connect timeout, redirects followed (up to 5), and TLS verification on.

Only `http://` and `https://` URLs are accepted.

`HttpResponse` properties are `int $status`, `array $headers` (lower-case names, each value a list), `string $body`, and `string $url` (the final URL after redirects). `header(string $name): ?string` is the first value. `isSuccess(): bool` is a 2xx status. `ensureSuccess()` returns the response or throws `\Tyhp\Io\Exceptions\HttpStatusException`.

```php
use Tyhp\Type as T;
use function Tyhp\await;

$client = \Tyhp\Io\Http\HttpClient::shared();
$user = await($client->getJsonAsync(T::struct([
    'id' => T::int,
    'name' => T::string,
]))('https://example.com/users/1'));

echo $user['name'], "\n";
```

`HttpResponse::json` is the same decode, types first, on a response you already have: `$response->ensureSuccess()->json(T::struct(['id' => T::int]))()`.

## Processes

`\Tyhp\Io\Process\Process::runAsync(array $command, ?array $options = null, ?\Tyhp\CancellationToken $token = null)` returns a promise of a `ProcessResult` array. The command is an argument list with no shell. `mustRunAsync` has the same arguments and throws `\Tyhp\Io\Exceptions\ProcessFailedException` when `exitCode` is not 0.

The result array has `command`, `exitCode`, `signal` (`0` when the process exited normally; otherwise `exitCode` is `128 + signal`), `stdout`, and `stderr`.

Omit `$options` for `input` `''` and `timeoutMs` `0`. An array you pass is used as given, so include `input` and `timeoutMs`. `cwd` and `env` may be omitted. `input` is written to stdin, then the pipe is closed. `timeoutMs` `0` means no limit.

## Files

All of these except `linesAsync` return a promise. Pass an optional `\Tyhp\CancellationToken`. A cancelled read or write stops at the next chunk. A cancelled write can leave a partial file.

| Method | Returns |
|--------|---------|
| `File::readAsync(string $path, ?\Tyhp\CancellationToken $token = null)` | Promise of `string` |
| `File::writeAsync(string $path, string $contents, ?\Tyhp\CancellationToken $token = null)` | Promise that fulfills with `null`. Creates or truncates the file. |
| `File::appendAsync(string $path, string $contents, ?\Tyhp\CancellationToken $token = null)` | Promise that fulfills with `null` |
| `File::copyAsync(string $from, string $to, ?\Tyhp\CancellationToken $token = null)` | Promise that fulfills with `null`. Replaces `$to`. |
| `File::hashAsync(string $path, string $algorithm = 'sha256', ?\Tyhp\CancellationToken $token = null)` | Promise of `string` |
| `File::readJsonAsync($type)(string $path, ?\Tyhp\CancellationToken $token = null)` | Types first. Promise of the decoded array. |
| `File::linesAsync(string $path)` | `\Tyhp\Contracts\AsyncIterable`. Not a promise. |

```php
use Tyhp\Type as T;
use function Tyhp\async;
use function Tyhp\await;

$user = await(\Tyhp\Io\File\File::readJsonAsync(T::struct([
    'id' => T::int,
    'name' => T::string,
]))('/tmp/user.json'));

$lines = \Tyhp\Io\File\File::linesAsync('/tmp/user.json');
$iterator = $lines->getAsyncIterator();
$text = await(async(function () use ($iterator): string {
    $out = '';
    while (await($iterator->next())) {
        $out .= await($iterator->current());
    }
    return $out;
}));
```

## Sockets

`\Tyhp\Io\Socket\Socket::connectAsync(string $address, int $timeoutMs = 10000, ?\Tyhp\CancellationToken $token = null)` returns a promise of `\Tyhp\Io\Socket\SocketConnection`. `$address` is `tcp://host:port`, `tls://host:port`, or `unix:///path`. `tls://` handshakes and verifies the peer certificate, and needs the OpenSSL extension. `$timeoutMs` of `0` means no limit.

`readAsync(int $maxBytes = 65536, ?\Tyhp\CancellationToken $token = null)` returns a promise of `string`. `writeAsync(string $data, ?\Tyhp\CancellationToken $token = null)` returns a promise. `close(): void` closes the stream.

```php
use function Tyhp\await;

$socket = await(\Tyhp\Io\Socket\Socket::connectAsync('tcp://127.0.0.1:6379'));
await($socket->writeAsync("PING\r\n"));
$reply = await($socket->readAsync());
$socket->close();
```

## Redis

`\Tyhp\Io\Redis\RedisClient::connectAsync(?array $options = null, ?\Tyhp\CancellationToken $token = null)` returns a promise of the client. Omit `$options` for host `127.0.0.1`, port `6379`, `tls` false, `database` `0`, and `connectTimeoutMs` `10000`. An array you pass is used as given: include `host`, `port`, `tls`, `database`, and `connectTimeoutMs`. `password` and `username` may be omitted. Set `password`, or `username` and `password`, to send `AUTH`. A non-zero `database` sends `SELECT`. `tls` true connects with `tls://`.

`commandAsync(string $name, string|int|float ...$arguments)` returns a promise of the reply. `getAsync(string $key)` returns a promise of `?string`. `setAsync(string $key, string $value, int $ttlMs = 0)` returns a promise. Do not send `SUBSCRIBE`, `PSUBSCRIBE`, or `MONITOR` through `commandAsync`. An error reply rejects with `\Tyhp\Io\Exceptions\RedisException` and leaves the connection usable.

```php
use function Tyhp\await;

$redis = await(\Tyhp\Io\Redis\RedisClient::connectAsync());
await($redis->setAsync('name', 'Ada'));
echo await($redis->getAsync('name')), "\n";
```

## PostgreSQL

`\Tyhp\Io\Db\PostgresConnection::connectAsync(string $connectionString, ?\Tyhp\CancellationToken $token = null)` needs `ext-pgsql`. The string is a libpq connection string, for example `host=127.0.0.1 port=5432 dbname=app user=app password=secret`. Placeholders in SQL are `$1`, `$2`, and so on. `queryAsync(string $sql, array $params = [], ?\Tyhp\CancellationToken $token = null)` returns a promise of `\Tyhp\Io\Db\DbResult`.

## MySQL

`\Tyhp\Io\Db\MySqlConnection::connectAsync(?array $options = null, ?\Tyhp\CancellationToken $token = null)` needs `ext-mysqli`. Omit `$options` for host `127.0.0.1`, port `3306`, user `root`, empty password and database, charset `utf8mb4`, and `connectTimeoutSeconds` `10`. An array you pass is used as given: include `host`, `port`, `user`, `password`, `database`, `charset`, and `connectTimeoutSeconds`. `socket` may be omitted, and is used only when `host` is `localhost`. Placeholders are `?`. `queryAsync` matches PostgreSQL.

## PDO

`new \Tyhp\Io\Db\PdoConnection(array $options)` needs `ext-pdo`. The options array requires `dsn` and `attributes` (`username` and `password` may be omitted). An empty `dsn` throws `\InvalidArgumentException`. `PDO::ATTR_ERRMODE` is always exceptions. With `tyhp/parallel` available, each query runs on a worker. Without it, the query blocks this process.

```php
use Tyhp\Type as T;
use function Tyhp\await;

$conn = new \Tyhp\Io\Db\PdoConnection([
    'dsn' => 'sqlite::memory:',
    'attributes' => [],
]);
$result = await($conn->queryAsync('select 1 as id'));
$rows = $result->rowsAs(T::struct(['id' => T::int]))();
```

`transactionAsync(array $statements, ?\Tyhp\CancellationToken $token = null)` runs every statement in one call. Each statement is an array with `sql` and `params`.

## Rows

`\Tyhp\Io\Db\DbResult` holds `array $rows` (each row an associative array, SQL `NULL` as `null`), `int $affectedRows`, and `?string $lastInsertId`. `count(): int`, `first(): ?array`, and `scalar(): mixed` are ordinary.

`rowsAs` and `firstAs` take the struct type first. The value is an array. A row that does not match throws `\Tyhp\Exceptions\IncompatibleTypeException`. `firstAs` returns `null` when there are no rows.

```php
use Tyhp\Type as T;

$rows = $result->rowsAs(T::struct(['id' => T::int, 'name' => T::string]))();
$first = $result->firstAs(T::struct(['id' => T::int, 'name' => T::optional(T::string)]))();
```

Integer, float, and boolean columns from PostgreSQL and MySQL are converted to `int`, `float`, and `bool` (MySQL `BOOLEAN` arrives as `int`). Other columns are strings. PDO returns the driver's values unchanged.

## DNS

`\Tyhp\Io\Dns\Dns::resolveAsync(string $host, ?\Tyhp\CancellationToken $token = null)` returns a promise of a list of address strings. When the `tyhp` module is loaded at `0.1.0` or newer, the lookup runs on a thread and the event loop waits on its pipe. A missing or older module uses `Offload`. An unresolved host rejects with `\Tyhp\Io\Exceptions\IoException` and the message `Could not resolve host {host}.` when `Offload::usesWorkers()` is false. When `Offload::usesWorkers()` is true, it rejects with `\Tyhp\Exceptions\ParallelException` and `getRemoteClass()` is `IoException`, on both paths. The `ParallelException` message from `Offload` may also name the worker file and line. A cancelled token rejects with `\Tyhp\Exceptions\OperationCancelledException`.

## Blocking work

Write a named class that implements `\Tyhp\Io\OffloadJob`. `run()` returns the value. The class and the result must be serializable when a worker runs them. Closures are not jobs.

`Offload::runAsync($type)(\Tyhp\Io\OffloadJob $job, ?\Tyhp\CancellationToken $token = null)` takes the result type first and returns a promise. `Offload::usesWorkers(): bool` is true when `tyhp/parallel` is installed and `Parallel::isAvailable()` is true. Otherwise `run()` runs in this process and blocks the loop.

```php
use Tyhp\Type as T;
use function Tyhp\await;

final class HashJob implements \Tyhp\Io\OffloadJob
{
    public function __construct(private string $text) {}

    public function run(): string
    {
        return \hash('sha256', $this->text);
    }
}

$digest = await(\Tyhp\Io\Offload::runAsync(T::string)(new HashJob('Ada')));
```

A job that throws inside a worker rejects with `\Tyhp\Exceptions\ParallelException`.

## Cancel

Build a `\Tyhp\CancellationTokenSource` from `tyhp/async` and pass `$source->getToken()` as `$token`. The HTTP, process, file, socket, database, DNS, and offload methods above accept it.

## Errors

| Exception | When |
|-----------|------|
| `\Tyhp\Io\Exceptions\IoException` | A transport, file, or connection failure. Base class of the `tyhp/io` exceptions below. |
| `\Tyhp\Io\Exceptions\IoUnavailableException` | The extension for that class is not loaded. |
| `\Tyhp\Io\Exceptions\HttpException` | An HTTP transport failure. |
| `\Tyhp\Io\Exceptions\HttpStatusException` | `ensureSuccess()` saw a non-2xx status. Extends `HttpException`. |
| `\Tyhp\Io\Exceptions\DbException` | A database failure. |
| `\Tyhp\Io\Exceptions\RedisException` | A Redis error reply or connection failure. |
| `\Tyhp\Io\Exceptions\ProcessFailedException` | `mustRunAsync` saw a non-zero exit code. |
| `\Tyhp\Exceptions\TimeoutException` | A timeout from `tyhp/async`. |
| `\Tyhp\Exceptions\OperationCancelledException` | The token was cancelled. |
| `\Tyhp\Exceptions\ParallelException` | `Offload::usesWorkers()` is true and a non-PDO job failed: an unresolved DNS host, an `Offload` job, or a worker-side error that is not reported as `DbException`. |
| `\JsonException`, `\Tyhp\Exceptions\IncompatibleTypeException` | JSON text or a decoded value does not match the struct. |

## Related

- [Packages for PHP](php_packages.md)
- [tyhp/async for PHP](php_package_async.md), [tyhp/parallel for PHP](php_package_parallel.md), [tyhp/core for PHP](php_package_core.md)
- [The tyhp/io Package](package_io.md) — the same package as used from Tyhp
