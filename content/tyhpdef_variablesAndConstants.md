---
title: 'Variables and Constants in Tyhpdef'
status:
  tier: 0
  story: '02'
  state: complete
---

Tyhpdef lets you describe existing PHP global variables and constants to the Tyhp compiler. This enables type-safe access to PHP superglobals, user-defined globals, and defined constants from your Tyhp code. You can specify types, alias names with `as`, and mark top-level imports `deprecated` or `obsolete`.

## Declaring Variables

Variable declarations specify a type followed by the variable name. The compiler uses that type when your Tyhp code reads the global. There is **no** runtime existence check or `ErrorException` coercion generated from the tyhpdef.

```tyhp
<?tyhpdef

// Import a global variable with its type
string $globalAppName;

// Import an object variable
\App\Config $appConfig;

// Import a typed array
array<string, mixed> $globalSettings;
```

## `??` expected start values

The grammar accepts `??` after a tyhpdef variable, constant, or class property (`int $maxRetries ?? 3`, `const int FLAG ?? 1`, `public array $items ?? [];`). That clause records the value PHP is **expected** to start with. The live value may differ; tyhpdef does not assign or define it. Handle missing PHP globals at the use site (`isset`, `??` in **code**, or nullable types).

Parameter defaults are unrelated: they still use `function foo(int $x = 1)`.

## Variable Aliasing

Variables can be aliased using `as $newName` so your Tyhp code uses a different name than the PHP global.

```tyhp
<?tyhpdef

// Import $blah1 from PHP as $globalGuest in Tyhp
Guest $blah1 as $globalGuest;
```

## Import by reference

Tyhpdef variable declarations do **not** accept `&`. `int &$sharedCounter` is not a tyhpdef form. Object values are PHP references as usual; scalars are whatever PHP already stored.

## Declaring Constants

Constants are declared using the `const` keyword followed by the type and name. Tyhpdef file-level constants **need** a type because they describe existing PHP constants that may not have an exact value in the tyhpdef. (Tyhp source does not allow a type on file-level `const`; PHP has no typed file-level constants.)

```tyhp
<?tyhpdef

// Simple constant declarations
const string APP_ENV;
const bool DEBUG_MODE;
const int MAX_CONNECTIONS;
const float PI_PRECISE;
const array<string> SUPPORTED_LOCALES;
```

## Fallback constants

`fallback const` describes a PHP constant that is defined only when that name does not already exist (`if (!defined('NAME')) { define('NAME', …); }`). Constant names are case-sensitive. The winner rules match [fallback functions](tyhpdef_functions.md#fallback-functions): one package fills the name, several packages follow `vendor/composer/autoload_files.php` order, `tyhpdef/php` wins over every fallback, and a loaded package that requires `ext-*` wins over a fallback of the same name.

```tyhp
<?tyhpdef

declare(ext="!intl") {
    fallback const int GRAPHEME_EXTR_COUNT ?? 0;
}
```

A later fallback const with a different type or value warns (`TYHP8042`) and is ignored. Two fallback consts and no autoload file list is an error (`TYHP8041`). An ordinary const that Composer loads after a fallback const of the same name is an error (`TYHP8043`). A plain `const` in the same package replaces that package's fallback.

`declare(ext="intl")` keeps the block when a loaded tyhpdef package requires `ext-intl`. `declare(ext="!intl")` keeps it when none do. The directive is alone in that `declare` (`TYHP8039`). The value is the extension name, or `!` plus that name (`TYHP8040`). It composes with `declare(php=…)` by nesting. See [PHP Version Gating](tyhp_0320_phpVersionGating.md#extension-presence).

## Constant Aliasing

Constants can be aliased using the fully-qualified PHP name with <code>as</code> to use a different name in Tyhp.

```tyhp
<?tyhpdef

// Import PHP constant with a shorter alias in Tyhp
const int \MAX_LOOPS_ALLOWED as MAX_LOOPS;
const string \App\Config\DATABASE_URL as DB_URL;
```

## Superglobal Type Declarations

PHP superglobals (`$_GET`, `$_POST`, `$_SERVER`, and similar) are typed by the `tyhpdef/php` package. You do not need to redeclare them unless you want a narrower project-specific type.

## Deprecated and Obsolete

Both **top-level** variables and constants can be marked as `deprecated` or `obsolete`. Member-level markers on class constants are parsed but not enforced in this alpha.

```tyhp
<?tyhpdef

deprecated const string OLD_API_KEY;
deprecated string $legacyConfig;
```

## Runtime Behavior

Tyhpdef imports are **type information**. The compiler does not emit existence checks, coercion, or `ErrorException` for missing globals. If a PHP variable or constant is unset, PHP's usual notices/errors apply at runtime.

## Best Practices

:::tip
DO declare accurate types for the globals you actually read. Handle missing values in Tyhp (`isset`, `??` at the **use** site, or nullable types). Tyhpdef `??` only documents PHP's expected start value.
:::

:::tip
DO use aliases to give cryptic or legacy PHP global names cleaner Tyhp identifiers.
:::

:::danger
DON'T import PHP superglobals ($_GET, $_POST, $_SERVER, etc.) unless you are intentionally narrowing the `tyhpdef/php` stubs. Duplicate declarations can conflict.
:::

:::danger
DON'T declare variables with incorrect types. If a PHP global is a string but you declare it as int, the runtime coercion may throw or silently produce wrong values.
:::

## Extern constants

A name-only `extern const \GMP_ROUND_PLUSINF;` occupies the const name when this package mentions a constant it does not own. Using it from `.tyhp` is `TYHP4307`. See [Extern Types](tyhpdef_extern.md).
