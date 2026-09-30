---
title: 'FAQ: General'
---

## What is Tyhp?

Tyhp is a typed superset of the PHP language. The compiler type-checks Tyhp source and emits readable PHP. It adds required types, generics, type guards, structs, operator overloads, extension methods, async/await, and similar constructs. The usual comparison is TypeScript’s relationship to JavaScript. Tyhp is not PHP.

## Is Tyhp a new language or a PHP extension?

Tyhp is a language: a typed superset of the PHP language. It is not PHP, not a PHP extension, and not affiliated with the PHP Group. `.php` files in a Tyhp project are passed through unchanged. `<?tyhp` source adds type requirements and extra syntax. The compiler is a standalone tool that reads that source and writes standard PHP. No PHP extensions or runtime modifications are required.

## Does Tyhp work with existing PHP code?

Yes. Tyhp is designed for gradual adoption. You can include `.php` files alongside `.tyhp` files in the same project. PHP files are passed through to the output unchanged. To get type-checking benefits when calling into existing PHP code, you write tyhpdef files that describe the PHP code's types to the compiler.

## What PHP versions does Tyhp support?

Tyhp currently supports targeting PHP 8.0 through 8.5. The target version is set via the `output.phpVersion` option in `tyhp.json`. If that key is omitted, the compiler defaults to `"8.2"` and emits warning **TYHP4306** once per compilation. The compiled output uses only features available in the targeted PHP version. Version-gated declarations (`declare(php=…)` / `#[\Tyhp\Php]`) are filtered to that same target; the `tyhpdef/php` stubs package covers 8.2–8.5.

## Is Tyhp free and open source?

Yes. Tyhp is an open-source project. The compiler, runtime packages, and documentation are all freely available.

## Does Tyhp add runtime overhead?

Most Tyhp features are compile-time only. Types, generics, and type guards are erased from PHP signatures. Source type aliases expand in hints and also emit a `\Tyhp\Type` factory function or static method for PHP interop. Compiled Tyhp libraries stamp `#[\Tyhp\GenericRuntime]` on every emitted generic class, method, and function. Same-compilation Tyhp uses factories/binders when tracked; foreign sites use `\Tyhp\Generic::bind`. Overlay tyhpdefs that omit the stamp keep erase / inline emit. Property hooks on PHP below 8.4, `async`/`await`, structs-as-arrays, remaining `\Tyhp\Type::is`, decimal arithmetic, and `\Tyhp\Type` compile to Tyhp-runtime PHP via `tyhp/core`, `tyhp/decimal`, and `tyhp/async`, which are added as Composer dependencies when needed.

## How does Tyhp compare to PHP static analyzers like PHPStan or Psalm?

PHPStan and Psalm analyze existing PHP code using annotations (PHPDoc comments) to find type errors. Tyhp is a separate language — a superset of PHP — with type syntax in the grammar, not comments. It can also add constructs (generics, structs, operator overloads, async/await) that a PHP analyzer cannot, because those tools cannot change PHP’s syntax. Tyhp’s compile-time checking is mandatory; you cannot ignore type errors the way you can with analyzer baselines.

## Can I use Composer packages with Tyhp?

Yes. Since Tyhp compiles to standard PHP, Composer packages work exactly as they do in PHP. To get type-checking for a Composer package, provide tyhpdef files that describe the package's types. After `composer install`, `tyhp generate_tyhpdef --vendor` (also run from `post-autoload-dump`) prefers published `tyhpdef/*` companions and otherwise writes stubs into `vendor-tyhpdef/`. You can also generate a single package with `--package-path=…`, or write the members you call by hand as overlays. PHP builtins come from the `tyhpdef/php` package.

Tyhp's own runtime packages (`tyhp/core`, `tyhpdef/php`, …) version independently of the compiler. Compiled `tyhp/*` helpers use Packagist MAJOR as the PHP target (`804.x` means PHP 8.4). `tyhpdef/*` packages use the version in that package’s `composer.json`. The compiler itself installs as `composer require --dev tyhp/compiler`. See the Composer Runtime Packages page and [Installing Tyhp](intro_installation.md).

## What editor or IDE support is available?

`tyhp language_server` speaks the Language Server Protocol over stdin/stdout (diagnostics, completion, hover, go-to-definition, find references, rename, and related features). The Tyhp Language extension for VS Code / Cursor and the PhpStorm plugin start it for you. You can also point any LSP client at `tyhp language_server`. See [CLI: Language Server](cli_languageServer.md).

For debugging `.tyhp` sources, set `build.generateSourcemap` to `true`, run `tyhp build`, then `tyhp xdebug_proxy`. See [CLI: Source Map Generation](cli_sourcemapGeneration.md) and [CLI: XDebug Proxy](cli_xdebugProxy.md). You can still use `tyhp lint` and `tyhp build` from the CLI.
