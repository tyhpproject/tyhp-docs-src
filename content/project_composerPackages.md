---
title: 'Composer Runtime Packages'
status:
  tier: 1
  story: '04'
  state: complete
---

Compiled Tyhp programs depend on small Composer packages (`tyhpdef/php`, `tyhp/core`, and others). Those packages **do not** share the compiler version. You can ship a new `tyhp/core` without bumping the Tyhp compiler.

The **compiler** version `805.1.0-beta.1` only means this toolchain can *emit* PHP up through 8.5 (and still emit 8.2–8.4 when `output.phpVersion` says so).

Each **package** has its own version (in that package’s `composer.json`).

Compiled `tyhp/*` helpers (`core`, `async`, `decimal`, `lambda`, `io`, `parallel`) are versioned as `80N.X.Y` where `80N` is the PHP that artifact is for (`802` = 8.2, `803` = 8.3, `804` = 8.4, `805` = 8.5).

`tyhpdef/*` packages (`tyhpdef/php`, `tyhpdef/php-ext-*`, Composer-lib wrappers) publish that `composer.json` version as the Packagist tag. They do not use `80N.X.Y`.

`tyhp/compiler` is versioned with the compiler itself (`805.1.0-beta.1`), not as `80N.X.Y`. See [The tyhp/compiler Package](package_compiler.md).

The compiled helpers currently ship at source version `0.1`, so the Packagist pins look like `804.0.1` for PHP 8.4 `tyhp/core`. If `tyhp/core` later becomes `1.4`, PHP 8.4 apps require `804.1.4` (or `804.1.*`). `tyhp/lambda` can be `2.0` at the same time. `tyhpdef/php` publishes the `version` in its `composer.json` (currently `0.0.2`); put it in `require-dev` as **`@dev`** rather than pinning that tag.

## Version map (compiled `tyhp/*` helpers)

| `output.phpVersion` | Package MAJOR | Pin when the package is `0.1` | Composer `php` on that artifact |
|---------------------|---------------|-------------------------------|---------------------------------|
| `"8.2"` | `802` | `802.0.1` | `>=8.2` |
| `"8.3"` | `803` | `803.0.1` | `>=8.3` |
| `"8.4"` | `804` | `804.0.1` | `>=8.4` |
| `"8.5"` | `805` | `805.0.1` | `>=8.5` |

`tyhp init` writes **`@dev`** for `tyhp/core` in `require` and for `tyhpdef/php` in `require-dev` (and `--vendor` adds the same constraint for missing runtime `tyhp/*` packages, and `@dev` in `require-dev` for missing `tyhpdef/php`). `tyhpdef/*` packages are compile-time stubs — prefer `require-dev` with `@dev`. Compiled `tyhp/*` helpers belong in `require` because emitted PHP loads them at runtime. `tyhp build` (when not using a compiler-checkout path repository, and when `build.updateComposer` writes pins) uses the pin for **each compiled** `tyhp/*` package from that package’s own `X.Y` plus your `output.phpVersion`. They do not all have to be the same version.

## Applications

An app targets **one** PHP version. Pin compiled `tyhp/*` helpers in `require` at that MAJOR and **that package’s** `X.Y`. Put `tyhpdef/*` in `require-dev` as `@dev`:

```json
{
    "require": {
        "php": "~8.4.0",
        "tyhp/core": "804.0.1"
    },
    "require-dev": {
        "tyhpdef/php": "@dev"
    }
}
```

If `tyhp/decimal` is on `1.2` and you use decimals, require `tyhp/decimal: 804.1.2` (or `804.1.*`). `tyhp build` reports the runtime packages the compiled code needs, and writes them into the generated `composer.json` when [`build.updateComposer`](project_optionsList.md) is `true`.

`804.0.*` is fine for an app if you want patch updates on that package line without changing PHP MAJOR.

Ambient tyhpdefs for the require tree (`extra.tyhp.require`) land on root `require-dev`. Allow `tyhp/core` under `config.allow-plugins`. The first `composer require tyhp/core` often misses that transaction — run `composer update` or `tyhp composer sync`. See [Ambient tyhpdefs](#ambient-tyhpdefs-extratyhprequire) and [CLI: Composer](cli_composer.md).

## Libraries

A library that supports several PHP versions should OR together the PHP majors it supports and keep **that package’s** X (not the compiler MINOR, and not some other package’s X):

```json
{
    "require": {
        "php": ">=8.3",
        "tyhp/core": "803.0.* || 804.0.* || 805.0.*"
    },
    "require-dev": {
        "tyhpdef/php": "@dev"
    }
}
```

If `tyhp/core` is on `1.y` and `tyhp/lambda` is on `2.y`:

```json
"tyhp/core": "803.1.* || 804.1.* || 805.1.*",
"tyhp/lambda": "803.2.* || 804.2.* || 805.2.*"
```

Composer then installs the newest artifact the *consumer's* PHP allows: on PHP 8.4 that is `804.*`, because `805.*` requires `>=8.5`.

Do **not** mix X values for the **same** package (`803.0.* || 804.1.*` for core). `803.1` and `804.1` are the same core line on different PHP; `804.0` is an older core line.

Published Tyhp libraries also declare ambient tyhpdefs in `extra.tyhp.require` (see below). Do not put author-only tyhpdefs there.

## Packages

| Package | Role |
|---------|------|
| `tyhpdef/php` | Always-present PHP 8.2+ builtins (Core, date, filter, hash, json, libxml, pcre, random, Reflection, SPL, standard) |
| `tyhpdef/php-ext-*` | Optional / disableable / PECL extensions (see below) |
| [`tyhp/core`](package_core.md) | Generics, typed variables, property accessors, scalar extension methods |
| [`tyhp/async`](package_async.md) | Promise, event loop, cancellation |
| [`tyhp/decimal`](package_decimal.md) | Arbitrary-precision decimal (`\Tyhp\Decimal`) |
| [`tyhp/lambda`](package_lambda.md) | Expression-tree / PropertyPath runtime |
| [`tyhp/io`](package_io.md) | Non-blocking HTTP, processes, files, sockets, Redis, and databases |
| [`tyhp/parallel`](package_parallel.md) | Process pool for CPU-heavy or blocking work |
| [`tyhp/compiler`](package_compiler.md) | `vendor/bin/tyhp`, the shim that installs and runs the native compiler (`require-dev`) |

Compiled `tyhp/*` packages (`tyhp/core`, `tyhp/decimal`, `tyhp/async`, `tyhp/lambda`, `tyhp/io`, `tyhp/parallel`) are versioned with four PHP-target prefixes (`802.`…`805.` plus that package’s `X.Y`). [Runtime Packages Overview](package_intro.md) describes what each one is for.

Only `tyhp/core` stands alone. Each of the others requires `tyhp/core` on the same `X` line, written as `802.X.* || 803.X.* || 804.X.* || 805.X.*` so Composer picks the artifact for the consumer’s PHP. `tyhp/io` and `tyhp/parallel` also require `tyhp/async`. `tyhp/parallel` additionally requires `ext-pcntl` and `ext-posix`. `tyhp/core` does not require `tyhp/io` or `tyhp/parallel`, and `tyhp/io` works without `tyhp/parallel` (it only suggests it). Install `tyhp/io` and `tyhp/parallel` yourself when you want them; `tyhp build` does not add them.

`tyhpdef/php` and `tyhpdef/php-ext-*` are **one Composer package each** for PHP 8.2–8.5. Their `composer.json` requires `"php": ">=8.2"`, and Packagist uses that file’s `version` as the tag. There are no `tyhpdef/php-8.2` / `tyhpdef/php-8.x-ext-*` forks. APIs that exist only on some minors are marked with `declare(php=…)` or `#[\Tyhp\Php]`; the compiler keeps only the declarations that match your `output.phpVersion`. See [PHP Version Gating](tyhp_0320_phpVersionGating.md).

## `tyhpdef/php` (always present)

Install `tyhpdef/php` in `require-dev` as `@dev` so `\strlen`, `DateTime`, SPL, json, hash, and libxml type-check. json, hash, and libxml stay in this package — there is no `tyhpdef/php-ext-json`, `tyhpdef/php-ext-hash`, or `tyhpdef/php-ext-libxml`.

## `tyhp/core` (runtime helpers + scalar methods)

`tyhp/core` ships the scalar method catalog (`$s->length()`, `$arr->mapped(...)`). The catalog is Tyhp source in the package (`StringExtensions`, `ArrayExtensions`, `IntExtensions`, `FloatExtensions`, `BoolExtensions`, and `ClosureExtensions` in `tyhp_src/`), and each file declares `global use extension` for its own extension. The package’s `package.tyhpdef` publishes those declarations, and its `composer.json` lists that file under `extra.tyhp.package.include`. Any project that loads `tyhp/core` therefore sees every catalog without a `use extension` in each file.

Each PHP-target artifact carries its own `package.tyhpdef`. Members that differ by PHP minor (`pad` / `ucFirst` on strings, `first` / `find` on arrays) sit in `declare(php=…)` blocks in the package source, and the generated file keeps only the variant for that artifact’s PHP. See [Scalar Pseudo-Objects](tyhp_1000_scalarPseudoObjects.md) and [PHP Version Gating](tyhp_0320_phpVersionGating.md).

## `tyhpdef/php-ext-*` (optional extensions)

Add a `tyhpdef/php-ext-*` package in `require-dev` (also `@dev`) when your project uses that PHP extension. Each package’s `composer.json` requires `ext-<name>` in `require`, and lists `tyhpdef/php` in both `require-dev` and `extra.tyhp.require`. Driver packages list parent wrappers the same way — for example `tyhpdef/php-ext-pdo_mysql` lists `tyhpdef/php-ext-pdo` and `tyhpdef/php-ext-mysqlnd`.

`tyhpdef/php-ext-decimal` is the **PECL Decimal** extension (php-decimal / mpdecimal). `tyhp/decimal` (`\Tyhp\Decimal`) can use it as one of its arithmetic backends, but does not require it; see [The tyhp/decimal Package](package_decimal.md).

Shipped packages (Composer name `tyhpdef/php-ext-<id>`):

apcu, bcmath, bz2, calendar, csv, ctype, curl, dba, decimal, dom, exif, ffi, fileinfo, ftp, gd, gettext, gmp, iconv, imagick, intl, ldap, lexbor, mbstring, memcached, mongodb, mysqli, mysqlnd, odbc, opcache, openssl, pcntl, pdo, pdo_dblib, pdo_mysql, pdo_odbc, pdo_pgsql, pdo_sqlite, pgsql, phar, posix, readline, redis, session, shmop, simplexml, snmp, soap, sockets, sodium, sqlite3, sysvmsg, sysvsem, sysvshm, tidy, tokenizer, uri, xml, xmlreader, xmlwriter, xsl, zip, zlib.

You do not install a PHP version matrix to type-check these packages. Set `output.phpVersion` to `"8.2"`, `"8.3"`, `"8.4"`, or `"8.5"` and lint/build; gated symbols appear or disappear for that target.

## Ambient tyhpdefs (`extra.tyhp.require`)

A Tyhp library can type-check against tyhpdef packages that its **consumers must not install**. List everything this package needs to compile in `require-dev`. Copy the subset that consumers need into `extra.tyhp.require`. Duplicate those ambient pins in `require-dev` so authors lock and install them.

Any Composer package name is allowed — not only `tyhpdef/*`. Values are ordinary Composer constraints (including `@dev` for path repositories).

```json
{
    "require": {
        "php": ">=8.2",
        "tyhp/core": "@dev"
    },
    "require-dev": {
        "tyhpdef/php": "@dev",
        "tyhpdef/php-ext-bcmath": "@dev",
        "tyhpdef/php-ext-gmp": "@dev",
        "tyhpdef/php-ext-decimal": "@dev"
    },
    "extra": {
        "tyhp": {
            "interopContractVersion": 1,
            "require": {
                "tyhpdef/php": "@dev"
            }
        }
    }
}
```

That shape is `tyhp/decimal`: authors compile optional backends against the bcmath / gmp / php-decimal wrappers, but apps that only call `\Tyhp\Decimal` install `tyhpdef/php`. They do **not** pick up those three wrappers. `tyhp/core` keeps `tyhpdef/php-ext-mbstring` in `require-dev` only so it can compile `\Tyhp\StringHelper`; consumers do not need that package to type-check `$s->length()`.

| Bucket | Where | Published `package.tyhpdef` |
|--------|--------|------------------------------|
| Runtime PHP | `require` | Spell the FQN. Do not copy. Do not emit `extern`. |
| Ambient for consumers | `extra.tyhp.require` (also list in `require-dev`) | Spell the FQN. Consumers install that tyhpdef. |
| Author-only | `require-dev` only | Name-only `extern` plus `// @provided-by: <owning package>`. |
| Omitted / `{}` extras | — | No ambient tyhpdefs from this package. |

Never put author-only tyhpdefs in extras. A public type must not `extends` / `implements` an author-only name (`TYHP3026` / `TYHP3027`) — keep those owners ambient (decimal lists `tyhpdef/php` so `\JsonSerializable` stays a real type). Mark author-only classes `internal` so they drop out of the public tyhpdef; see [The internal Visibility Modifier](tyhp_3100_internalModifier.md).

`tyhp/compiler` is not listed in extras on `tyhp/*` packages. Application roots still pin it on `require-dev` (`tyhp init` does; `tyhp composer sync` adds it when `tyhp/core` is in the graph). The `tyhp/compiler` package itself does not require itself.

### Plugin on `tyhp/core`

`tyhp/core` is a Composer plugin (`type: composer-plugin`) that walks `extra.tyhp.require` and runtime `require` edges, merges constraints onto the **root** `require-dev`, and adds `tyhp/compiler` unless the root package is already `tyhp/compiler`. Allow it:

```json
"config": {
    "allow-plugins": {
        "tyhp/core": true
    }
}
```

`tyhp init` writes that key. `tyhp composer`, `tyhp composer sync`, and `tyhp build --fix` also write it when missing and do not overwrite an explicit `false`. A raw `composer` command still needs the key already on disk. A `--no-dev` install does not rewrite `composer.json`.

The first `composer require tyhp/core` often misses ambient tyhpdefs in that same transaction. Run `composer update` or `tyhp composer sync`. If extras are missing, `tyhp build` explains (`TYHP7701`) and `tyhp composer sync` / `tyhp build --fix` recovers. Ordinary `tyhp build` never auto-updates Composer. Details: [CLI: Composer](cli_composer.md).

## Path repositories (compiler checkout)

If `tyhp build` can see a `tyhp-runtime-src` checkout, it pins each package’s **source** version (for example `0.1` or `0.0.2`) and adds Composer path repositories for the packages in it. It finds the checkout through the `TYHP_RUNTIME_SRC` environment variable (the checkout or its `packages` directory), otherwise a sibling `tyhp-runtime-src/packages` directory found by walking up from the compiler’s directory or the current directory. That is only for developing against the runtime packages themselves. Packagist consumers of compiled `tyhp/*` helpers use the `80N.X.Y` form. Packagist consumers of `tyhpdef/*` typically use `@dev` in `require-dev`; the published tag is the source version (currently `0.0.2` for `tyhpdef/php`).

:::tip
`output.phpVersion` in `tyhp.json` chooses the emitted PHP **and** the `80N` prefix on compiled `tyhp/*` helpers. Each `tyhp/*` package’s `X.Y` is independent. `tyhpdef/*` packages are not prefixed.
:::
