---
title: 'Functions in Tyhpdef'
status:
  tier: 0
  story: '02'
  state: complete
---

Tyhpdef allows you to declare function signatures that describe existing PHP functions to the Tyhp type system. Function declarations in tyhpdef are signature-only — they have no function body, just parameter types and a return type followed by a semicolon. Functions can be global or namespaced, and support generic type parameters, constraints, reference parameters, variadic arguments, optional parameters with defaults, async markers, and aliases.

## Basic Function Declarations

A function declaration in tyhpdef consists of the function keyword, the function name, typed parameters in parentheses, a return type, and a terminating semicolon. All parameters must have type annotations and a return type must be specified.

```tyhp
<?tyhpdef

function \strlen(string $string): int;

function \str_contains(string $haystack, string $needle): bool;

function \array_key_exists(int|string $key, array $array): bool;

function \is_numeric(mixed $value): bool;
```

## Optional Parameters and Defaults

Parameters can have default values, making them optional. The default value appears after the equals sign, just like in PHP.

```tyhp
<?tyhpdef

function \substr(string $string, int $offset, ?int $length = null): string;

function \implode(string $separator = "", array<string> $array): string;

function \json_encode(
    mixed $value,
    int $flags = 0,
    int $depth = 512
): string|false;
```

`tyhp generate_tyhpdef` copies a PHP parameter default when it is already a tyhpdef literal. When the default is not tyhpdef-safe (concatenation, nowdoc, const expression, unbalanced quotes), the parameter stays optional: generate writes `= null`, the same dummy used for harvested implicit-nullable PHP (`string $timezone = null`). The declared type is not widened. See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#harvested-types-defaults-and-attributes).

## Reference and Variadic Parameters

Reference parameters use the ampersand prefix, and variadic parameters use the ellipsis syntax. Variadic parameters must be the last parameter.

```tyhp
<?tyhpdef

function \sort(array &$array, int $flags = SORT_REGULAR): true;

function \usort<T>(array<T> &$array, callable(T, T): int $callback): true;

function \array_push<T>(array<T> &$array, T ...$values): int;

function \sprintf(string $format, mixed ...$values): string;
```

## Generic Function Declarations

Functions can declare generic type parameters with optional constraints. The generic parameters are placed in angle brackets after the function name.

```tyhp
<?tyhpdef

function \array_map<T, U>(
    callable(T): U $callback,
    array<T> $array
): array<U>;

function \array_filter<T>(
    array<T> $array,
    ?callable(T): bool $callback = null
): array<T>;

function \array_reduce<T, TCarry>(
    array<T> $array,
    callable(TCarry, T): TCarry $callback,
    TCarry $initial
): TCarry;

function findByType<T extends Entity>(string $type): ?T;
```

## Async Function Declarations

Functions that return a Promise can be declared with the async keyword. When declared as async, the return type represents the resolved value type — the compiler understands that the actual PHP function returns a Promise wrapping that type.

```tyhp
<?tyhpdef

async function fetchUserData(int $userId): UserData;

async function downloadFile(string $url): string;

async function sendNotification(string $to, string $message): void;
```

## Function Aliases

A function can be imported under a different name using the `as` keyword. The original PHP function name comes first, then `as`, then the alias name that Tyhp code will use. This **adds** a Tyhp name; the PHP name remains callable unless you also overlay `omit` or a `partial function` rename (see below).

```tyhp
<?tyhpdef

function \testEmail as test_email(string $emailAddress): bool;

function \array_key_exists as keyExists(
    int|string $key,
    array $array
): bool;
```

To **rename** without restating the signature, use overlay `partial function X as Y` — see [Tyhpdef Overlays](tyhpdef_overlays.md#overlay-partial-function).

:::tip
DO: Always specify full type annotations on every parameter and the return type. Tyhpdef functions with incomplete types will cause the compiler to treat missing types as mixed, reducing type safety.
:::

:::tip
DO: Use generic type parameters when a function's return type depends on its input types. This lets the compiler track types through function calls precisely.
:::

:::danger
DON'T: Include a function body in a tyhpdef declaration. Tyhpdef is declaration-only — every function signature must end with a semicolon, not a curly-brace block.
:::

:::danger
DON'T: Declare a variadic parameter anywhere other than the last position. The compiler will reject signatures where variadic parameters precede regular ones.
:::

## Callable Parameter Types

When a function accepts a callable parameter, write a callable shape: `callable(…): R`. Parameter names are optional. `=` marks a parameter as optional. `\Closure` is a class: write `\Closure<callable(int $i): string>`, not `\Closure<int, string>`. See [New and Changed Types](tyhp_0150_newTypes.md#the-closuretcallableshape-tthis-tscope-type).

```tyhp
<?tyhpdef

// callable(): ReturnType -- zero params, returns ReturnType
function \registerShutdown(callable(): void $callback): void;

// callable(ParamType): ReturnType -- one param, returns ReturnType
function \array_walk<T>(
    array<T> &$array,
    callable(T): void $callback
): true;

// callable(Param1, Param2): ReturnType -- two params
function \usort<T>(
    array<T> &$array,
    callable(T, T): int $callback
): true;
```

## Extension Function Declarations

Functions can be declared as extension functions using the extends keyword on the first parameter. Extension functions are called with instance method syntax on the extended type.

```tyhp
<?tyhpdef

function toCamelCase(extends string $str): string;

function toSnakeCase(extends string $str): string;

function toSlug(extends string $str, string $separator = "-"): string;
```

To map operators and methods onto an existing PHP class (inline `extension fn` / `extension operator`, or `use extension` on the type), see [Extensions in Tyhpdef](tyhpdef_extensions.md). Standalone tyhpdef `extension Name { }` uses short `fn` / `operator` + `=>` members, not these file-level `extends` forms.

## PHP version gating

Version-specific PHP functions use `#[\Tyhp\Php("…")]` or `#[\Tyhp\Php(version: "…")]` on the signature. Disjoint constraints may declare the same name with different parameter lists. Overlapping constraints on the **same** parameter list are **TYHP4303**; distinct parameter lists under the same gate are overloads.

```tyhp
<?tyhpdef

#[\Tyhp\Php(">=8.2 <8.4")]
function example(string $v): mixed;

#[\Tyhp\Php(">=8.4")]
function example(string $v, bool $strict = false): string;
```

`declare(php="…") { function …; }` also parses in `.tyhpdef`. See [PHP Version Gating](tyhp_0320_phpVersionGating.md).

## Native type tests (`#[\Tyhp\NativeTypeTest]`)

A free function or concrete static method with a type-guard return can be marked as the native lowering for `$x is T` / `$x instanceof T`. `T` is the guard type, not an attribute argument:

```tyhp
<?tyhpdef

#[\Tyhp\NativeTypeTest]
function is_string(mixed $value): $value is string;

class Tests {
    #[\Tyhp\NativeTypeTest]
    public static function isPositiveInt(mixed $value): $value is int;
}
```

The same attribute is legal on Tyhp source. Usages and the `NativeTypeTest` class itself are compile-only (`#[\Tyhp\NoEmit]`). Extra parameters are allowed only when they have defaults so emit stays `fqn($x)` or `\Class::method($x)`. Unions, nullables, duplicate `T`, and overlapping guarded types are errors. Instance, abstract, and interface methods cannot be marked. Unmarked guards still narrow when called; they do not change `$x is T` emit.

`tyhpdef/php` marks `is_string`, `is_int`, `is_float`, `is_bool`, `is_array`, `is_object`, `is_null`, `is_resource`, and the defaulted `is_callable` overload. It does not mark `is_integer` / `is_long` / `is_numeric` / `is_scalar`.

## Overlay `partial function`

Overlay files may write name-only `partial function` to merge attributes onto an existing callable, or to rename it, without restating the signature:

```tyhp
<?tyhpdef

#[\Tyhp\Optimize\Pure]
partial function \str_contains;

partial function \strtolower as str2LC;
partial function \strtoupper;
partial function \strtoupper as str2UC;
```

`partial function X as Y;` replaces Tyhp name `X` with `Y` (same PHP emit name) unless the same overlay file also has `partial function X;`. Match is the **current Tyhp name**. Overlay-only (`TYHP8032`); missing target warns (`TYHP8031`). Methods belong inside an overlay `partial` type (`TYHP8033`). Confirm live names with `tyhp symbol_tree --filter=<name>` ([CLI: Symbol Tree](cli_symbolTree.md)).

Include / baseline `partial` still applies only to **types** (`class` / `enum` / `interface` / `trait`): additive members, duplicate members error (`TYHP8002`), missing target error (`TYHP8014`). Overlay `omit` may hide a whole function (`omit function \array_map();`) or a member inside overlay `partial`.

See [Classes in Tyhpdef](tyhpdef_classes.md#partial-types-base--include) and [Tyhpdef Overlays](tyhpdef_overlays.md). Overlay type headers (`partial class Foo<T>;`) are documented there as well.

## Fallback functions

`fallback function` describes a PHP function that is declared only when that name does not already exist:

```php
if (!function_exists('collect')) {
    function collect($value = null) { /* ... */ }
}
```

```tyhp
<?tyhpdef

fallback function collect<TKey extends int|string = int|string, TValue = mixed>(
    \Illuminate\Contracts\Support\Arrayable<TKey, TValue>|iterable<TKey, TValue>|null $value = []
): \Illuminate\Support\Collection<TKey, TValue>;

deprecated fallback function trigger_deprecation(
    string $package,
    string $version,
    string $message,
    mixed ...$args
): void;
```

One package declaring the name makes the function available. When several packages declare it, the package whose file appears first in `vendor/composer/autoload_files.php` supplies the signature. `tyhpdef/php` wins over every fallback. A loaded tyhpdef package that `require`s or `require-dev`s `ext-intl` (or any `ext-*`) also wins over a fallback of the same name. Installing that package is what makes the extension present for type-checking. An `ext-intl` line on the application `composer.json`, without the tyhpdef package loaded, does not.

A later fallback with a different signature warns (`TYHP8037`) and is ignored. Two fallbacks and no Composer autoload file list to order them is an error (`TYHP8036`). An ordinary function that Composer loads after a fallback of the same name is an error (`TYHP8038`). A function in Tyhp source next to a package fallback of the same name is a duplicate declaration. A plain `function` in the same package replaces that package's fallback.

`fallback` combines with `deprecated` or `obsolete`, and with `async` (`fallback async function …`). It does not combine with `partial`, `omit`, or `extern`.

Wrap a fallback in `declare(ext="!intl")` when the function exists only if that extension's tyhpdef package is not loaded, and in `declare(php="…")` when it is also version-specific. See [PHP Version Gating](tyhp_0320_phpVersionGating.md) and [Fallback constants](tyhpdef_variablesAndConstants.md#fallback-constants).

```tyhp
<?tyhpdef

declare(php="<8.6") {
    declare(ext="!intl") {
        fallback function grapheme_strrev(string $string): string|false;
    }
}
```

## Summary

- All parameters must be fully typed — no untyped parameters are allowed
- Return types must always be specified
- Function declarations end with a semicolon (no function body)
- Reference parameters use `&` just like in PHP
- Variadic parameters use `...` and must be the last parameter
- Generic type parameters with constraints are supported via angle bracket syntax
- Async functions use the `async` keyword and represent the resolved return type
- Functions can be aliased using `as` to expose them under a different name in Tyhp. Overlay `partial function X as Y` renames without restating the signature.
- An imported function can be marked as `deprecated` or `obsolete`
- `fallback function` is a signature PHP defines only when the name is still empty. Composer `autoload.files` order picks the winning package. `declare(ext="!name")` hides it when that extension's tyhpdef package is loaded.
- `#[\Tyhp\Php]` gates a function to a PHP version constraint; `declare(php=…)` also parses in `.tyhpdef`
- Callable parameters use callable shapes: `callable(Params …): ReturnType`. `\Closure` takes that shape as `TCallableShape`.
- Top-level functions can use `extends` on the first parameter to import PHP functions as extension methods; standalone tyhpdef `extension Name { }` and class-body `extension fn` / `extension operator` are covered in [Extensions in Tyhpdef](tyhpdef_extensions.md)
- Overlay `partial function` merges attributes or renames a live callable — see [Tyhpdef Overlays](tyhpdef_overlays.md#overlay-partial-function). Overlay `omit` can hide a function.
- `#[\Tyhp\NativeTypeTest]` on a free function or concrete static method with a type-guard return (`$param is T` on the first parameter) makes `$x is T` emit a call to that callable (`\is_string($x)` or `\Foo::isString($x)`). `T` must be a single type. Extra parameters need defaults. Duplicate or overlapping `T` is an error. Canonical PHP tests (`is_int`, not `is_integer`) are marked this way in `tyhpdef/php`.
- `extern function \bcadd;` is a name-only placeholder when this package mentions a function it does not own. See [Extern Types](tyhpdef_extern.md).
