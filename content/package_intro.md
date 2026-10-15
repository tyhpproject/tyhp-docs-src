---
title: 'Runtime Packages Overview'
---

Tyhp compiles to plain PHP. Some language features need a small amount of runtime code to work in that PHP: generics, `async`/`await`, decimals, and parsable lambdas. That code ships as Composer packages under the `tyhp/` vendor name. Other `tyhp/*` packages are ordinary libraries written in Tyhp, for example non-blocking I/O and a process pool. You install those when you want them.

Each package has its own page with a full API reference, explanations, and worked examples.

## The packages

| Package | Namespace | What it gives you | How it gets into `composer.json` |
|---------|-----------|-------------------|--------------------------|
| [`tyhp/core`](package_core.md) | `Tyhp\` | Runtime types, contracts, attributes, and the scalar extension methods (`$s->length()`, `$items->mapped(...)`). Compiled code loads it when it uses those features, and the other `tyhp/*` packages depend on it. | By `tyhp init`; also reported by `tyhp build` when compiled code needs it |
| [`tyhp/async`](package_async.md) | `Tyhp\` | `Promise<T>`, the event loop, cancellation, and async iteration. It is the runtime behind `async` and `await`. | Reported by `tyhp build` when compiled code uses async features |
| [`tyhp/decimal`](package_decimal.md) | `Tyhp\` | The arbitrary-precision `\Tyhp\Decimal` number. | Reported by `tyhp build` when compiled code uses decimals |
| [`tyhp/lambda`](package_lambda.md) | `Tyhp\` | Expression trees and `PropertyPath` for parsable lambdas. | Reported by `tyhp build` when compiled code uses parsable lambdas |
| [`tyhp/io`](package_io.md) | `Tyhp\Io\` | Non-blocking HTTP, processes, files, sockets, Redis, PostgreSQL, MySQL, and PDO on the `tyhp/async` event loop. | By you |
| [`tyhp/parallel`](package_parallel.md) | `Tyhp\` | A process pool that runs CPU-heavy or blocking tasks in worker processes, from the CLI or from php-fpm. | By you |
| [`tyhp/compiler`](package_compiler.md) | — | `vendor/bin/tyhp`, which installs and runs the native Tyhp compiler for your project. | In `require-dev`: by `tyhp init` and `tyhp composer sync` (an exact version) and by the `tyhp/core` Composer plugin (`@dev`) |

The `tyhpdef/*` packages (`tyhpdef/php`, `tyhpdef/php-ext-*`, and the wrappers for popular Composer libraries) are a different kind of package: compile-time type definitions with no runtime code. They are covered in [Composer Runtime Packages](project_composerPackages.md).

## How the packages depend on each other

```text
tyhp/core
├── tyhp/async
│   ├── tyhp/io        (optionally uses tyhp/parallel)
│   └── tyhp/parallel
├── tyhp/decimal
├── tyhp/lambda
└── tyhp/compiler      (require-dev)
```

Requiring a package pulls in the packages above it. For example, `composer require tyhp/io` also installs `tyhp/async` and `tyhp/core`. `tyhp/io` works without `tyhp/parallel`. When `tyhp/parallel` is installed and a pool is available, io moves its blocking work into worker processes: PDO queries, DNS lookups, and `Offload` jobs. See [Offloading blocking work](package_io.md#offloading-blocking-work-tyhpio).

## PHP extensions

| Package | Requires | Optional |
|---------|----------|----------|
| `tyhp/core` | — | `ext-mbstring` for Unicode-aware string methods. Without it, the string methods work on bytes. |
| `tyhp/async` | — | — |
| `tyhp/decimal` | — | `ext-decimal` (preferred), `ext-bcmath`, or `ext-gmp` as the arithmetic backend |
| `tyhp/lambda` | — | — |
| `tyhp/io` | — | `ext-curl` for `HttpClient`, `ext-pgsql` for `PostgresConnection`, `ext-mysqli` for `MySqlConnection`, `ext-pdo` for `PdoConnection` |
| `tyhp/parallel` | `ext-pcntl`, `ext-posix` | — |
| `tyhp/compiler` | `ext-curl` | — |

`tyhp/io` checks for an extension only when you use the class that needs it. A missing extension throws `\Tyhp\Io\Exceptions\IoUnavailableException` with the extension's name.

## Installing

Compiled `tyhp/*` packages are versioned once per PHP target. The version starts with `80N`, the PHP version the artifact was built for (`802` for PHP 8.2 through `805` for PHP 8.5), followed by the package's own version. Pick the prefix that matches `output.phpVersion` in your `tyhp.json`:

```bash
composer require tyhp/io:804.0.*
composer require tyhp/parallel:804.0.*
```

`tyhp init` adds `tyhp/core` and `tyhp/compiler`, plus `tyhpdef/php` in `require-dev`. After each build, `tyhp build` prints the runtime packages your compiled code needs (`tyhp/core`, `tyhp/async`, `tyhp/decimal`, `tyhp/lambda`, and `tyhpdef/php`). When [`build.updateComposer`](project_optionsList.md) is `true`, it also writes them into the `composer.json` in `output.publishPath` and runs `composer install` there; otherwise require them yourself. `tyhp/io` and `tyhp/parallel` are never added for you. Libraries that support several PHP versions OR the prefixes together. [Composer Runtime Packages](project_composerPackages.md) explains the version scheme in full.

## Async method names

In `tyhp/io` and `tyhp/parallel`, every public method that returns a `Promise` (or is declared `async`) has a name ending in `Async`: `HttpClient::getAsync()`, `File::readAsync()`, `DbConnection::queryAsync()`, `Parallel::runAsync()`. If the name ends in `Async`, `await` the result. Methods that implement an interface keep the interface's name, for example `OffloadJob::run()` and `ParallelTask::run()`.

```tyhp
<?tyhp

use Tyhp\Io\File\File;
use Tyhp\Io\Http\HttpClient;
use Tyhp\Io\Http\HttpResponse;

async function backup(string $url, string $path): void {
    HttpResponse $response = await HttpClient::shared()->getAsync($url);
    await File::writeAsync($path, $response->ensureSuccess()->body);
}
```

## Choosing between async, io, and parallel

- **Waiting on I/O** (HTTP calls, database queries, sockets, child processes): use [`tyhp/io`](package_io.md). It runs many operations at once in one process, using `async`/`await` from [`tyhp/async`](package_async.md).
- **CPU-heavy work, or a blocking library with no async API**: use [`tyhp/parallel`](package_parallel.md). Each task runs in its own worker process, so it doesn't stall the event loop or the request.
- **Your own async building blocks** (timers, combinators, cancellation, custom stream watchers): use [`tyhp/async`](package_async.md) directly.

## Related pages

- [Async and Await](tyhp_2600_asyncAndAwait.md) — the language feature that `tyhp/async` implements.
- [Scalar Pseudo-Objects](tyhp_1000_scalarPseudoObjects.md) — the method syntax on scalars and arrays that `tyhp/core` provides.
- [Parsable Lambdas](tyhp_3000_parsableLambdas.md) — the language feature that `tyhp/lambda` implements.
- [Composer Runtime Packages](project_composerPackages.md) — versioning, ambient tyhpdefs, and the `tyhp/core` Composer plugin.
- [CLI: Composer](cli_composer.md) — `tyhp composer` and `tyhp composer sync`.
