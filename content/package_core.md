---
title: 'The tyhp/core Package'
---

`tyhp/core` is the runtime that every compiled Tyhp program loads. It contains three kinds of things:

- **APIs you call from your own code.** The scalar method catalog (`$name->length()`, `$orders->mapped(...)`, `$total->round(2)`), runtime type objects (`\Tyhp\Type`), typed JSON decoding (`\Tyhp\Json`), the generics bridge for hand-written PHP (`\Tyhp\Generic`), contracts such as `\Tyhp\Contracts\IsDisposable`, attributes such as `#[\Tyhp\Php]`, and the exceptions the runtime throws.
- **Plumbing that the compiler's emitted PHP calls.** Property-hook polyfills, per-instance generic bookkeeping, and the traits that host them. You see these names in generated PHP and stack traces, but you do not call them yourself.
- **A Composer plugin.** It keeps your root `require-dev` in sync with the type-definition packages that your dependencies declare in `extra.tyhp.require`.

This page is the API reference for the package. The language features that sit on top of it have their own pages: [Scalar Pseudo-Objects](tyhp_1000_scalarPseudoObjects.md), [Extensions](tyhp_2100_extensions.md), [Generics](tyhp_0500_generics.md), [New and Changed Types](tyhp_0150_newTypes.md), [Type Narrowing and Guards](tyhp_0200_typeNarrowingAndGuards.md), [Compile-Time Constructs](tyhp_2700_compileTimeConstructs.md), [Disposables](tyhp_2300_disposables.md), [Operator Overloads](tyhp_1600_operatorOverloads.md), and [Composer Runtime Packages](project_composerPackages.md). For the other runtime packages, see the [package overview](package_intro.md).

## Installing

`tyhp init` already adds `tyhp/core` to a new project. In an existing project, add it to `require` (not `require-dev`), because the emitted PHP loads it at runtime, and allow its Composer plugin:

```json
{
    "require": {
        "php": ">=8.2",
        "tyhp/core": "@dev"
    },
    "require-dev": {
        "tyhpdef/php": "@dev",
        "tyhp/compiler": "@dev"
    },
    "config": {
        "allow-plugins": {
            "tyhp/core": true
        }
    }
}
```

Published versions follow the `80N.X.Y` scheme, where `80N` is the PHP version that artifact was compiled for (`804` is PHP 8.4) and `X.Y` is the version of `tyhp/core` itself. An application pins the major that matches its `output.phpVersion`; a library ORs the majors it supports. See [Composer Runtime Packages](project_composerPackages.md) for the full version map and pinning rules.

The package requires PHP 8.2 or later and Composer's plugin API 2.3 or later. The `ext-mbstring` extension is optional but recommended: with it, string methods count and slice characters; without it, they fall back to byte-oriented PHP functions (see [Unicode and `ext-mbstring`](#unicode-and-ext-mbstring)).

:::tip
The first `composer require tyhp/core` often does not install the ambient type definitions (`tyhpdef/php` and friends) in that same Composer run. Run `composer update` or `tyhp composer sync` afterwards. See [CLI: Composer](cli_composer.md).
:::

## Package contents at a glance

| Area | Names | Who uses it |
|------|-------|-------------|
| Scalar method catalog | `StringExtensions`, `StringExtensionsVersioned`, `ArrayExtensions`, `ArrayExtensionsVersioned`, `IntExtensions`, `FloatExtensions`, `BoolExtensions`, `ClosureExtensions` | You, as `$value->method()` |
| String helper | `\Tyhp\StringHelper` | Compiled code; also callable from PHP |
| Runtime types | `\Tyhp\Type`, `\Tyhp\NamedType` | You and compiled code (`typeof`, `is`, `default`) |
| Typed JSON | `\Tyhp\Json` | You |
| Generics bridge | `\Tyhp\Generic` | Hand-written PHP and compiled code that calls another library's generics |
| Object `with` helper | `\Tyhp\ObjectHelper` | Compiled `with` expressions; also callable directly |
| Contracts | `\Tyhp\Contracts\IsDisposable`, `Convertible`, `IntConvertible`, `FloatConvertible`, `BoolConvertible`, `StringConvertible`, `ArrayAccessShape<TStruct>` | You implement them |
| Attributes | `#[\Tyhp\Php]`, `#[\Tyhp\PhpType]`, `#[\Tyhp\NativeTypeTest]`, `#[\Tyhp\EraseGeneric]`, `#[\Tyhp\AllowUnset]`, `#[\Tyhp\GenericRuntime]`, `#[\Tyhp\NoEmit]`, `#[\Tyhp\Optimize\Pure]`, `#[\Tyhp\Optimize\Inline]` | You write most of them; the compiler writes `GenericRuntime` |
| Exceptions | `\Tyhp\Exceptions\IncompatibleTypeException`, `InvalidTypeException`, `AggregateException`, `PropertyNotFoundException`, `InvalidParametersForOperatorOverloadException` | Thrown by the runtime and by compiled code |
| Compiled-code plumbing | `PropertyAccessor`, `PropertyAccessorObject`, `PropertyBackingCell`, `GenericObject`, `\Tyhp\Concerns\*` traits | Compiled code only |
| Composer plugin | `Tyhp\Composer\Plugin` | Composer |

## Scalar extension methods

`tyhp/core` attaches methods to `string`, `array`, `int`, `float`, `bool`, and `\Closure`. Its type definition issues `global use extension` for every catalog, so the methods are available in every file of every project that depends on `tyhp/core`. You do not write `use extension` for them. A file-level `use extension \Tyhp\StringExtensions;` with no adaptations is redundant and warns (`TYHP4169`); use a local `use extension` only to hide or rename members in that file. The language rules (how the receiver works, chaining, literals, adaptations) are on [Scalar Pseudo-Objects](tyhp_1000_scalarPseudoObjects.md) and [Extensions](tyhp_2100_extensions.md).

```tyhp
<?tyhp

function slugify(string $title): string {
    string $lower = $title->trim()->toLower();
    ?string $slug = $lower->regexReplace('/[^a-z0-9]+/', '-');
    return $slug === null ? '' : $slug->trim('-');
}

function percent(int $part, int $whole): string {
    float $ratio = (float) $part / (float) $whole * 100.0;
    return $ratio->round(1)->format(1) . '%';
}

// slugify('  Hello, World! 2026 ') === 'hello-world-2026'
// percent(1, 3) === '33.3%'
```

### How to read the signatures

Each entry below shows the receiver as `$s` (string), `$a` (array), `$i` (int), `$f` (float), `$b` (bool), or `$fn` (`\Closure`). The receiver is not a parameter: `$s->contains('x')` passes one argument. Each entry also says what the call **emits**. Most methods are spliced: the call is replaced by the PHP expression shown, so there is no wrapper object and no extra function call. A few methods need a real PHP body; those emit a static call on the catalog class (for example `\Tyhp\ArrayExtensions::sorted($a, $flags)`), and hand-written PHP can call them the same way.

Array methods are generic over the receiver's key and value types. In the array section, `TKey` and `TValue` are the key and value types of the array you call the method on, so `array<string, int>` gives `TKey = string` and `TValue = int`.

### Unicode and `ext-mbstring`

Methods that count, slice, search, or change the case of characters go through [`\Tyhp\StringHelper`](#string-helper-tyhpstringhelper). When `ext-mbstring` is loaded, those calls use the `\mb_*` functions and work in characters; otherwise they use the byte functions (`\strlen`, `\substr`, `\strtoupper`, …). Offsets returned by `indexOf()` and friends are therefore character offsets with mbstring and byte offsets without it. Methods with a `byte` prefix (`byteLength()`, `byteReverse()`) always work in bytes.

`trim()`, `trimLeft()`, and `trimRight()` use PHP's byte-based `\trim` family in both cases.

### PHP-version-dependent methods

A few members differ by `output.phpVersion`. The signature and the result are the same on every target; only the implementation changes:

| Method | PHP 8.2 | PHP 8.3 | PHP 8.4 | PHP 8.5 |
|--------|---------|---------|---------|---------|
| `$s->pad()`, `padLeft()`, `padRight()` | `\str_pad` (bytes) | `\mb_str_pad` when mbstring is loaded | same as 8.3 | same as 8.3 |
| `$s->ucFirst()`, `lcFirst()` | first character via `StringHelper` | same as 8.2 | `\mb_ucfirst` / `\mb_lcfirst` when mbstring is loaded | same as 8.4 |
| `$a->find()`, `findKey()`, `any()`, `all()` | polyfill loop | polyfill loop | `\array_find` / `\array_find_key` / `\array_any` / `\array_all` | same as 8.4 |
| `$a->first()`, `last()` | polyfill via `\array_key_first` / `\array_key_last` | same as 8.2 | same as 8.2 | `\array_first` / `\array_last` |

The polyfilled array methods emit a static call on `\Tyhp\ArrayExtensionsVersioned`; the native ones splice the PHP function. On PHP 8.2 the `pad` family pads by bytes, so multibyte padding strings can produce a different visible width than on 8.3+.

### Chaining and receivers

Calls chain: `$title->trim()->toLower()`. Integer and float literals need parentheses: `(255)->toHex()`.

A few string methods splice the receiver into a later argument position of the PHP function: `split()` (`\explode($delimiter, $s)`), `replace()`, `replaceIgnoreCase()`, `regexReplace()`, `regexSplit()`, `matches()`, and `hash()`. A call can be the receiver of one of those (`$s->toLower()->split(' ')`) as long as the other arguments are literals, constants, or variables. When the receiver and an earlier argument are both calls (`$s->trim()->split(sep())`), the compiler cannot keep PHP's evaluation order and reports `TYHP4181`. Assign one of the values to a variable first, as `slugify()` does above.

Methods that modify the array in place (`sort()`, `push()`, `pop()`, …) take the receiver by reference, so the receiver must be a variable, property, or array element, not a call result.

### String methods

#### Length and emptiness

:::member[$s->length(): int]
Number of characters (with mbstring) or bytes (without). Emits `\Tyhp\StringHelper::strlen($s)`.
:::

:::member[$s->byteLength(): int]
Number of bytes, regardless of mbstring. Emits `\strlen($s)`.
:::

:::member[$s->isEmpty(): bool]
`true` when the string is exactly `''`. `'0'` and `' '` are not empty. Emits `$s === ''`.
:::

:::member[$s->isNotEmpty(): bool]
`true` when the string is not `''`. Emits `$s !== ''`.
:::

#### Searching

:::member[$s->contains(string $needle): bool]
Case-sensitive substring test. An empty needle always matches. Emits `\str_contains($s, $needle)`.
:::

:::member[$s->containsIgnoreCase(string $needle): bool]
Case-insensitive substring test, Unicode-aware with mbstring. Emits `\Tyhp\StringHelper::stripos($s, $needle) !== false`.
:::

:::member[$s->startsWith(string $prefix): bool]
Emits `\str_starts_with($s, $prefix)`.
:::

:::member[$s->endsWith(string $suffix): bool]
Emits `\str_ends_with($s, $suffix)`.
:::

:::member[$s->indexOf(string $needle, int $offset = 0): int|false]
Position of the first occurrence at or after `$offset`, or `false` when not found. Compare the result with `=== false`; `0` is a valid position. Emits `\Tyhp\StringHelper::strpos($s, $needle, $offset)`.
:::

:::member[$s->lastIndexOf(string $needle, int $offset = 0): int|false]
Position of the last occurrence, or `false`. A negative `$offset` limits the search as in `\strrpos`. Emits `\Tyhp\StringHelper::strrpos($s, $needle, $offset)`.
:::

:::member[$s->indexOfIgnoreCase(string $needle, int $offset = 0): int|false]
Case-insensitive `indexOf()`. Emits `\Tyhp\StringHelper::stripos($s, $needle, $offset)`.
:::

#### Extracting

:::member[$s->substring(int $start, ?int $length = null): string]
Characters from `$start` (negative counts from the end) for `$length` characters, or to the end when `$length` is `null`. Emits `\Tyhp\StringHelper::substr($s, $start, $length)`.
:::

:::member[$s->charAt(int $index): string]
The single character at `$index`, or `''` when out of range. Emits `\Tyhp\StringHelper::substr($s, $index, 1)`.
:::

:::member[$s->first(int $length = 1): string]
The first `$length` characters. Emits `\Tyhp\StringHelper::substr($s, 0, $length)`.
:::

:::member[$s->last(int $length = 1): string]
The last `$length` characters. Emits `\Tyhp\StringHelper::substr($s, -$length)`. Because `-0` is `0`, `last(0)` returns the whole string, not `''`.
:::

:::member[$s->chunk(int $length = 1): array<int, string>]
Splits the string into pieces of `$length` characters (the last piece may be shorter). Emits `\Tyhp\StringHelper::strSplit($s, $length)`.
:::

#### Case

:::member[$s->toLower(): string]
Emits `\Tyhp\StringHelper::strtolower($s)`.
:::

:::member[$s->toUpper(): string]
Emits `\Tyhp\StringHelper::strtoupper($s)`.
:::

:::member[$s->ucWords(): string]
Capitalizes each word. With mbstring this is `\mb_convert_case($s, MB_CASE_TITLE)`, which also lowercases the rest of each word (`'hELLO wORLD'` becomes `'Hello World'`); without mbstring it is `\ucwords`, which leaves the rest unchanged. Emits `\Tyhp\StringHelper::ucWords($s)`.
:::

:::member[$s->ucFirst(): string]
Uppercases the first character (`'élan'` becomes `'Élan'` with mbstring). Implementation depends on the PHP target; see [PHP-version-dependent methods](#php-version-dependent-methods).
:::

:::member[$s->lcFirst(): string]
Lowercases the first character. Implementation depends on the PHP target.
:::

#### Trimming and padding

:::member[$s->trim(string $characters = " \t\n\r\0\x0B"): string]
Removes the listed bytes from both ends. Pass a character list (ranges like `'a..z'` work as in PHP) to trim something else, for example `$slug->trim('-')`. Emits `\trim($s, $characters)`.
:::

:::member[$s->trimLeft(string $characters = " \t\n\r\0\x0B"): string]
Emits `\ltrim($s, $characters)`.
:::

:::member[$s->trimRight(string $characters = " \t\n\r\0\x0B"): string]
Emits `\rtrim($s, $characters)`.
:::

:::member[$s->pad(int $length, string $padString = ' ', int $padType = \STR_PAD_RIGHT): string]
Pads to `$length` with `$padString`. `$padType` is `\STR_PAD_RIGHT`, `\STR_PAD_LEFT`, or `\STR_PAD_BOTH`. A string already at least `$length` long is returned unchanged.
:::

:::member[$s->padLeft(int $length, string $padString = ' '): string]
Pads on the left. `'42'->padLeft(8, '0')` is `'00000042'`.
:::

:::member[$s->padRight(int $length, string $padString = ' '): string]
Pads on the right.
:::

#### Replacing, splitting, and joining

:::member[$s->replace(string|array<int|string, string> $search, string|array<int|string, string> $replace): string]
Case-sensitive replacement of every occurrence. Arrays replace pairwise, as in `\str_replace`. Emits `\str_replace($search, $replace, $s)`.
:::

:::member[$s->replaceIgnoreCase(string|array<int|string, string> $search, string|array<int|string, string> $replace): string]
Emits `\str_ireplace($search, $replace, $s)`.
:::

:::member[$s->split(string $delimiter, int $limit = \PHP_INT_MAX): array<int, string>]
Splits on `$delimiter`. A positive `$limit` caps the number of pieces (the last piece holds the rest); a negative one drops that many pieces from the end. An empty delimiter throws `\ValueError`. Emits `\explode($delimiter, $s, $limit)`.
:::

:::member[$s->repeat(int $times): string]
Emits `\str_repeat($s, $times)`.
:::

:::member[$s->reverse(): string]
Reverses the characters (multibyte-safe with mbstring: `'añb'` becomes `'bña'`). Emits `\implode('', \array_reverse(\Tyhp\StringHelper::strSplit($s)))`.
:::

:::member[$s->byteReverse(): string]
Reverses the bytes. This corrupts multibyte characters; use `reverse()` for text. Emits `\strrev($s)`.
:::

:::member[$s->wordWrap(int $width = 75, string $break = "\n", bool $cutLongWords = false): string]
Emits `\wordwrap($s, $width, $break, $cutLongWords)`.
:::

:::member[$s->wordCount(int $format = 0, ?string $characters = null): array<int, string>|int]
With `$format` `0`, the number of words (`int`). With `1`, a list of the words; with `2`, the words keyed by their byte offset (both `array<int, string>`). A literal `$format` selects the matching return type; with a non-literal `$format` the result is the union, so narrow it (`\is_int($count)`) before use. Emits `\str_word_count($s, $format, $characters)`.
:::

:::member[$s->format(mixed ...$args): string]
Uses the string as a `\sprintf` format: `'%d items'->format($count)`. Emits `\sprintf($s, ...$args)`.
:::

#### Regular expressions

All patterns are PCRE patterns with delimiters, exactly as for PHP's `preg_*` functions.

:::member[$s->matches(string $pattern): bool]
`true` when the pattern matches somewhere in the string. Emits `\preg_match($pattern, $s) === 1`.
:::

:::member[$s->match(string $pattern, int $flags = 0, int $offset = 0): \PregMatchSetNullable|\PregMatchSetOffset|\PregMatchSetOffsetNullable|null]
The first match as `\preg_match` fills it (index `0` is the whole match, then the groups), or `null` when there is no match. `$flags` takes `\PREG_OFFSET_CAPTURE` and `\PREG_UNMATCHED_AS_NULL`. When `$flags` is a literal or constant, the result type follows it:

- `0` (the default): `\PregMatchSet`, an array of strings.
- `\PREG_OFFSET_CAPTURE`: `\PregMatchSetOffset`, whose entries are `[string, offset]` pairs.
- `\PREG_UNMATCHED_AS_NULL`: `\PregMatchSetNullable`, where unmatched groups are `null`.
- Both flags: `\PregMatchSetOffsetNullable`.

Any other `$flags` expression gives the union of those types. Emits `\Tyhp\StringExtensions::match($s, $pattern, $flags, $offset)`.
:::

:::member[$s->matchAll(string $pattern, int $flags = 0, int $offset = 0): array<int|string, mixed>|false]
Every match as `\preg_match_all` fills it (default ordering `\PREG_PATTERN_ORDER`), or `false` on a PCRE error. Returns an empty-group structure, not `false`, when nothing matches. When `$flags` is a literal or constant, the result type follows it: pattern order (`0`, `\PREG_PATTERN_ORDER`) gives `\PregMatchAllSet`, `\PREG_SET_ORDER` gives `\PregMatchAllList`, and `\PREG_OFFSET_CAPTURE` and `\PREG_UNMATCHED_AS_NULL` select the offset-capture and nullable variants. Any other `$flags` expression gives `array<int|string, mixed>|false`. Emits `\Tyhp\StringExtensions::matchAll($s, $pattern, $flags, $offset)`.
:::

:::member[$s->regexReplace(string $pattern, string $replacement): string|null]
Replaces every match; `$replacement` may use `$1` back-references. Returns `null` on a PCRE error. Emits `\preg_replace($pattern, $replacement, $s)`.
:::

:::member[$s->regexSplit(string $pattern, int $limit = -1, int $flags = 0): array<int, string>|array<int, \PregOffsetCapture>|false]
Splits on the pattern. With `\PREG_SPLIT_OFFSET_CAPTURE` in `$flags`, each piece is a `[string, offset]` pair. Returns `false` on a PCRE error. When `$flags` is a literal or constant, the result is `array<int, string>|false` without `\PREG_SPLIT_OFFSET_CAPTURE` and `array<int, \PregOffsetCapture>|false` with it; any other `$flags` expression gives the union. Emits `\preg_split($pattern, $s, $limit, $flags)`.
:::

:::member[$s->regexQuote(string $delimiter = '/'): string]
Escapes regex metacharacters (and `$delimiter`) so the string can be embedded in a pattern. Emits `\preg_quote($s, $delimiter)`.
:::

```tyhp
<?tyhp

function parseVersion(string $tag): ?string {
    $m = $tag->match('/^v(\d+)\.(\d+)\.(\d+)$/');
    if ($m === null) {
        return null;
    }
    mixed $major = $m[1];
    mixed $minor = $m[2];
    if (!\is_string($major) || !\is_string($minor)) {
        return null;
    }
    return $major . '.' . $minor;
}

// parseVersion('v8.4.12') === '8.4'
```

#### Encoding and escaping

:::member[$s->htmlEncode(int $flags = \ENT_QUOTES | \ENT_SUBSTITUTE | \ENT_HTML401, bool $doubleEncode = true): string]
Escapes `&`, `<`, `>`, `"`, and `'` for HTML output. Use it for every untrusted value you place in HTML. Emits `\htmlspecialchars($s, $flags, null, $doubleEncode)`.
:::

:::member[$s->htmlDecode(int $flags = \ENT_QUOTES | \ENT_SUBSTITUTE | \ENT_HTML401): string]
Reverses `htmlEncode()`. Emits `\htmlspecialchars_decode($s, $flags)`.
:::

:::member[$s->htmlEntities(int $flags = \ENT_QUOTES | \ENT_SUBSTITUTE | \ENT_HTML401, bool $doubleEncode = true): string]
Converts every character that has a named HTML entity. Emits `\htmlentities($s, $flags, null, $doubleEncode)`.
:::

:::member[$s->nl2Br(bool $useXhtml = true): string]
Inserts `<br />` (or `<br>` when `$useXhtml` is `false`) before each newline. It does not escape HTML; call `htmlEncode()` first. Emits `\nl2br($s, $useXhtml)`.
:::

:::member[$s->stripTags(array<int|string, string>|string|null $allowedTags = null): string]
Removes HTML and PHP tags. This is not an HTML sanitizer; use `htmlEncode()` to make text safe. Emits `\strip_tags($s, $allowedTags)`.
:::

:::member[$s->urlEncode(): string]
Form encoding (spaces become `+`). Emits `\urlencode($s)`.
:::

:::member[$s->urlDecode(): string]
Emits `\urldecode($s)`.
:::

:::member[$s->rawUrlEncode(): string]
RFC 3986 encoding (spaces become `%20`); use it for path segments. Emits `\rawurlencode($s)`.
:::

:::member[$s->rawUrlDecode(): string]
Emits `\rawurldecode($s)`.
:::

:::member[$s->base64Encode(): string]
Emits `\base64_encode($s)`.
:::

:::member[$s->base64Decode(bool $strict = false): string|false]
Returns `false` when `$strict` is `true` and the input contains characters outside the Base64 alphabet. Emits `\base64_decode($s, $strict)`.
:::

:::member[$s->convertEncoding(string $toEncoding, array|string|null $fromEncoding = null): string|false]
Converts between character encodings. Returns `false` when mbstring is not loaded. Emits `\Tyhp\StringHelper::convertEncoding($s, $toEncoding, $fromEncoding)`.
:::

:::member[$s->detectEncoding(): string|false]
Detects the encoding with `\mb_detect_encoding`. Returns `false` when it cannot decide or when mbstring is not loaded. Emits `\Tyhp\StringHelper::detectEncoding($s)`.
:::

:::member[$s->ord(): int|false]
Code point of the first character (with mbstring) or value of the first byte (without). Emits `\Tyhp\StringHelper::ord($s)`.
:::

#### Hashing

:::member[$s->md5(bool $binary = false): string]
Emits `\md5($s, $binary)`. Do not use it for passwords.
:::

:::member[$s->sha1(bool $binary = false): string]
Emits `\sha1($s, $binary)`. Do not use it for passwords.
:::

:::member[$s->hash(string $algorithm, bool $binary = false): string]
Any algorithm from `\hash_algos()`, for example `'sha256'`. An unknown algorithm throws `\ValueError`. Emits `\hash($algorithm, $s, $binary)`.
:::

:::member[$s->crc32(): int]
Emits `\crc32($s)`.
:::

#### JSON

:::member[$s->jsonDecode(bool $associative = true, int $depth = 512, int $flags = 0): \JsonAssoc|\JsonObject|null]
Untyped decode. Unlike `\json_decode`, objects become associative arrays by default. Returns `null` for invalid JSON unless `\JSON_THROW_ON_ERROR` is in `$flags`. Prefer `jsonDecodeAs<T>()` when you know the shape. Emits `\json_decode($s, $associative, $depth, $flags)`.
:::

:::member[$s->jsonDecodeAs<T extends struct>(int $depth = 512, int $flags = 0): T]
Typed decode; the same as [`\Tyhp\Json::decode<T>($s)`](#typed-json-tyhpjson). Throws `\JsonException` for invalid JSON and `IncompatibleTypeException` when the value does not match `T`.
:::

:::member[$s->jsonTryDecodeAs<T extends struct>(T &$out, int $depth = 512, int $flags = 0): bool]
Typed decode that does not throw; the same as `\Tyhp\Json::tryDecode<T>($s, $out)`.
:::

#### Conversion

:::member[$s->isNumeric(): bool]
Emits `\is_numeric($s)`.
:::

:::member[$s->__toInt(): int]
Emits `\intval($s)`. Non-numeric strings give `0`.
:::

:::member[$s->__toFloat(): float]
Emits `\floatval($s)`.
:::

:::member[$s->__toBool(): bool]
Emits `(bool) $s`. `''` and `'0'` are `false`.
:::

### Array methods

Methods ending in `-ed` (`sorted`, `filtered`, `mapped`, `reversed`, …) return a new array and leave the receiver alone. The bare verbs (`sort`, `push`, `shift`, …) modify the receiver in place and return what the PHP function returns.

```tyhp
<?tyhp

type Order = struct {
    int $id = 0;
    string $customer = '';
    float $total = 0.0;
    string $status = 'open';
};

function topCustomers(array<int, Order> $orders): array<int, string> {
    array<int, Order> $open = $orders->filtered(fn(Order $o): bool => $o->status === 'open');
    array<int, Order> $byTotal = $open->sortedBy(fn(Order $a, Order $b): int => $b->total <=> $a->total);
    array<int, string> $names = $byTotal->mapped(fn(Order $o): string => $o->customer);
    return $names->unique()->values()->sliced(0, 3);
}

function revenue(array<int, Order> $orders): float {
    return $orders->reduce(fn(float $sum, Order $o): float => $sum + $o->total, 0.0);
}

function firstLarge(array<int, Order> $orders): ?Order {
    return $orders->find(fn(Order $o, int $i): bool => $o->total > 1000.0);
}
```

#### Size and membership

:::member[$a->count(): int]
Emits `\count($a)`.
:::

:::member[$a->isEmpty(): bool]
Emits `\count($a) === 0`.
:::

:::member[$a->isNotEmpty(): bool]
Emits `\count($a) > 0`.
:::

:::member[$a->keyExists(TKey $key): bool]
`true` when the key is present, even if its value is `null`. Emits `\array_key_exists($key, $a)`.
:::

:::member[$a->contains(TValue $value, bool $strict = false): bool]
Searches the values. The comparison is loose (`==`) unless `$strict` is `true`; pass `true` for strings that might look numeric and for mixed types. Emits `\in_array($value, $a, $strict)`.
:::

:::member[$a->search(TValue $value, bool $strict = false): TKey|false]
Key of the first matching value, or `false`. Loose by default, like `contains()`. Compare with `=== false`, since `0` is a valid key. Emits `\array_search($value, $a, $strict)`.
:::

#### Keys and values

:::member[$a->keys(): array<int, TKey>]
Emits `\array_keys($a)`.
:::

:::member[$a->values(): array<int, TValue>]
The values re-indexed from `0`. Use it after `filtered()` or `unique()` when you need a list. Emits `\array_values($a)`.
:::

:::member[$a->first(): ?TValue]
The first value in iteration order, or `null` for an empty array. A stored `null` is indistinguishable from "empty"; check `isEmpty()` when that matters. Implementation depends on the PHP target.
:::

:::member[$a->last(): ?TValue]
The last value, or `null` for an empty array. Implementation depends on the PHP target.
:::

:::member[$a->flipped(): array<TValue, TKey>]
Swaps keys and values. Available when `TValue` is `int` or `string`. Later duplicates win. Emits `\array_flip($a)`.
:::

:::member[$a->countValues(): array<TValue, int>]
How many times each value occurs. Available when both `TKey` and `TValue` are `int` or `string`. Emits `\array_count_values($a)`.
:::

#### Searching with a predicate

These take a callback that receives the value and then the key.

:::member[$a->find(callable(TValue, TKey): bool $callback): ?TValue]
The first value for which the callback returns `true`, or `null`.
:::

:::member[$a->findKey(callable(TValue, TKey): bool $callback): ?TKey]
The key of the first value for which the callback returns `true`, or `null`.
:::

:::member[$a->any(callable(TValue, TKey): bool $callback): bool]
`true` as soon as one element satisfies the callback; `false` for an empty array.
:::

:::member[$a->all(callable(TValue, TKey): bool $callback): bool]
`true` when every element satisfies the callback; `true` for an empty array.
:::

#### Transforming

:::member[$a->filtered(?callable $callback = null, int $mode = 0): array<TKey, TValue>]
Keeps the elements for which the callback returns `true`. Keys are preserved, so a filtered list can have gaps; call `values()` to re-index. Without a callback, removes every falsy element. `$mode` is `\ARRAY_FILTER_USE_KEY` or `\ARRAY_FILTER_USE_BOTH`. Emits `\array_filter($a, $callback, $mode)`.
:::

:::member[$a->mapped<TResult>(callable(TValue): TResult $callback): array<TKey, TResult>]
Applies the callback to every value and keeps the keys. `TResult` is inferred from the callback's return type. Emits `\array_map($callback, $a)`.
:::

:::member[$a->reduce<TResult>(callable(TResult, TValue): TResult $callback, TResult $initial): TResult]
Folds the values into one result, starting from `$initial`. Emits `\array_reduce($a, $callback, $initial)`.
:::

:::member[$a->walk(callable(TValue, TKey): void $callback): bool]
Calls the callback for every element with the value and the key, and returns `true`. Emits `\array_walk($a, $callback)`.
:::

:::member[$a->unique(int $flags = \SORT_STRING): array<TKey, TValue>]
Removes duplicate values, keeping the first key of each. Values are compared as strings by default. Emits `\array_unique($a, $flags)`.
:::

:::member[$a->reversed(bool $preserveKeys = false): array<TKey, TValue>]
Reverses the order. Integer keys are renumbered unless `$preserveKeys` is `true`; string keys are always kept. Emits `\array_reverse($a, $preserveKeys)`.
:::

:::member[$a->flatten(): array]
Collects every leaf value of a nested array into one list, depth-first. Keys are discarded. The result is an untyped `array`, so annotate the variable you assign it to. Calls `\Tyhp\ArrayExtensions::flatten($a)`.
:::

:::member[$a->join(string $separator = ''): string]
Joins the values into a string. Emits `\implode($separator, $a)`.
:::

#### Slicing and combining

:::member[$a->sliced(int $offset, ?int $length = null, bool $preserveKeys = false): array<TKey, TValue>]
A portion of the array, by position. Integer keys are renumbered unless `$preserveKeys` is `true`. Emits `\array_slice($a, $offset, $length, $preserveKeys)`.
:::

:::member[$a->chunked(int $length, bool $preserveKeys = false): array<int, array<TKey, TValue>>]
Splits into arrays of `$length` elements (the last may be shorter). Emits `\array_chunk($a, $length, $preserveKeys)`.
:::

:::member[$a->padded(int $length, TValue $value): array<TKey, TValue>]
Pads to `$length` elements with `$value` (a negative `$length` pads at the front). Emits `\array_pad($a, $length, $value)`.
:::

:::member[$a->merged(array<TKey, TValue> ...$arrays): array<TKey, TValue>]
Appends the other arrays. String keys from later arrays overwrite earlier ones; integer keys are renumbered. Emits `\array_merge($a, ...$arrays)`.
:::

:::member[$a->diffed(array<TKey, TValue> ...$arrays): array<TKey, TValue>]
Values of the receiver that appear in none of the other arrays (compared as strings). Emits `\array_diff($a, ...$arrays)`.
:::

:::member[$a->diffedByKey(array<TKey, TValue> ...$arrays): array<TKey, TValue>]
Elements whose keys appear in none of the other arrays. Emits `\array_diff_key($a, ...$arrays)`.
:::

:::member[$a->intersected(array<TKey, TValue> ...$arrays): array<TKey, TValue>]
Values of the receiver that appear in every other array. Emits `\array_intersect($a, ...$arrays)`.
:::

:::member[$a->intersectedByKey(array<TKey, TValue> ...$arrays): array<TKey, TValue>]
Elements whose keys appear in every other array. Emits `\array_intersect_key($a, ...$arrays)`.
:::

#### Sorting into a new array

:::member[$a->sorted(int $flags = \SORT_REGULAR): array<int, TValue>]
The values in ascending order, as a new list (keys are discarded). Calls `\Tyhp\ArrayExtensions::sorted($a, $flags)`.
:::

:::member[$a->reverseSorted(int $flags = \SORT_REGULAR): array<int, TValue>]
The values in descending order, as a new list. Calls `\Tyhp\ArrayExtensions::reverseSorted($a, $flags)`.
:::

:::member[$a->sortedBy(callable(TValue, TValue): int $callback): array<int, TValue>]
The values ordered by a comparison callback that returns a negative number, zero, or a positive number (the `<=>` operator is the usual body). Keys are discarded. Calls `\Tyhp\ArrayExtensions::sortedBy($a, $callback)`.
:::

:::member[$a->sortedByKey(int $flags = \SORT_REGULAR): array<TKey, TValue>]
A copy ordered by key, ascending, with keys kept. Calls `\Tyhp\ArrayExtensions::sortedByKey($a, $flags)`.
:::

:::member[$a->reverseSortedByKey(int $flags = \SORT_REGULAR): array<TKey, TValue>]
A copy ordered by key, descending, with keys kept. Calls `\Tyhp\ArrayExtensions::reverseSortedByKey($a, $flags)`.
:::

:::member[$a->sortedByKeyWith(callable(TKey, TKey): int $callback): array<TKey, TValue>]
A copy ordered by a key comparison callback, with keys kept. Calls `\Tyhp\ArrayExtensions::sortedByKeyWith($a, $callback)`.
:::

#### Modifying in place

These require a variable (or property, or element) as the receiver.

:::member[$a->sort(int $flags = \SORT_REGULAR): bool]
Sorts the values ascending and re-indexes. Emits `\sort($a, $flags)`.
:::

:::member[$a->reverseSort(int $flags = \SORT_REGULAR): bool]
Emits `\rsort($a, $flags)`.
:::

:::member[$a->sortBy(callable(TValue, TValue): int $callback): bool]
Sorts with a comparison callback and re-indexes. Emits `\usort($a, $callback)`.
:::

:::member[$a->sortByKey(int $flags = \SORT_REGULAR): bool]
Emits `\ksort($a, $flags)`.
:::

:::member[$a->reverseSortByKey(int $flags = \SORT_REGULAR): bool]
Emits `\krsort($a, $flags)`.
:::

:::member[$a->sortByKeyWith(callable(TKey, TKey): int $callback): bool]
Emits `\uksort($a, $callback)`.
:::

:::member[$a->shuffle(): bool]
Randomizes the order and re-indexes. Not cryptographically secure. Emits `\shuffle($a)`.
:::

:::member[$a->push(TValue ...$values): int]
Appends values; returns the new element count. Emits `\array_push($a, ...$values)`.
:::

:::member[$a->pop(): ?TValue]
Removes and returns the last value, or `null` when the array is empty. Emits `\array_pop($a)`.
:::

:::member[$a->shift(): ?TValue]
Removes and returns the first value, or `null`; integer keys are renumbered. Emits `\array_shift($a)`.
:::

:::member[$a->unshift(TValue ...$values): int]
Prepends values; returns the new element count. Emits `\array_unshift($a, ...$values)`.
:::

:::member[$a->splice(int $offset, ?int $length = null, array $replacement = []): array<TKey, TValue>]
Removes `$length` elements starting at `$offset` (to the end when `null`), inserts `$replacement` in their place, and returns the removed elements. Emits `\array_splice($a, $offset, $length, $replacement)`.
:::

```tyhp
<?tyhp

function queue(): array<int, string> {
    array<int, string> $jobs = ['email', 'resize'];
    int $n = $jobs->push('cleanup', 'report');   // 4
    ?string $next = $jobs->shift();              // 'email'
    $jobs->sort();                               // ['cleanup', 'report', 'resize']
    return $n > 0 && $next !== null ? $jobs : [];
}
```

#### Numeric arrays

Available when the value type is `int` or `float`.

:::member[$a->sum(): int|float]
Emits `\array_sum($a)`. `0` for an empty array.
:::

:::member[$a->product(): int|float]
Emits `\array_product($a)`. `1` for an empty array.
:::

#### Untyped helpers

These are declared on plain `array` because their result shape depends on the arguments. Annotate the variable you assign the result to.

:::member[$a->column(string|int|null $columnKey, string|int|null $indexKey = null): array]
One field from each row of a list of rows (arrays or objects), optionally keyed by another field. A `null` `$columnKey` returns whole rows. Emits `\array_column($a, $columnKey, $indexKey)`.
:::

:::member[$a->combined(array $values): array]
Uses the receiver's values as keys for `$values`. Both arrays must have the same number of elements, or PHP throws `\ValueError`. Emits `\array_combine($a, $values)`.
:::

:::member[$a->zipped(array ...$arrays): array]
Pairs up elements by position: when `$ids` is `[1, 2]`, `$ids->zipped(['a', 'b'])` is `[[1, 'a'], [2, 'b']]`. Shorter arrays are padded with `null`. Emits `\array_map(null, $a, ...$arrays)`.
:::

:::member[$a->toJson(int $flags = 0, int $depth = 512): string|false]
Encodes the array as JSON; returns `false` on failure unless `\JSON_THROW_ON_ERROR` is set. Emits `\json_encode($a, $flags, $depth)`.
:::

### Int methods

:::member[$i->abs(): int]
Emits `\abs($i)`.
:::

:::member[$i->clamp(int $min, int $max): int]
Limits the value to the range `$min`…`$max`. When `$min` is greater than `$max`, the result is `$min`. Emits `\max($min, \min($max, $i))`.
:::

:::member[$i->between(int $min, int $max): bool]
Inclusive range test. Emits `($i >= $min) && ($i <= $max)`. Pass variables or literals as `$min` and `$max`; a call as either bound is **TYHP4181**. Assign it to a variable first.
:::

:::member[$i->isEven(): bool]
Emits `($i % 2) === 0`.
:::

:::member[$i->isOdd(): bool]
Emits `($i % 2) !== 0`.
:::

:::member[$i->isPositive(): bool]
Strictly greater than zero. Emits `$i > 0`.
:::

:::member[$i->isNegative(): bool]
Emits `$i < 0`.
:::

:::member[$i->isZero(): bool]
Emits `$i === 0`.
:::

:::member[$i->sign(): int]
`-1`, `0`, or `1`. Emits `$i <=> 0`.
:::

:::member[$i->max(int $value, int ...$values): int]
The largest of the receiver and the arguments. At least one argument is required. Emits `\max($i, $value, ...$values)`.
:::

:::member[$i->min(int $value, int ...$values): int]
The smallest of the receiver and the arguments. At least one argument is required. Emits `\min($i, $value, ...$values)`.
:::

:::member[$i->pow(int $exponent): int|float]
`$i ** $exponent`. The result is a `float` for a negative exponent or when the result overflows `int`.
:::

:::member[$i->toBase(int $base): string]
The value written in base 2–36. Emits `\base_convert((string) $i, 10, $base)`. `\base_convert` drops the minus sign with a deprecation notice, so `(-10)->toBase(2)` is `'1010'`; convert `abs()` and add the sign yourself for negative values.
:::

:::member[$i->toHex(): string]
Lowercase hexadecimal. Negative values give the two's-complement form. Emits `\dechex($i)`.
:::

:::member[$i->toOctal(): string]
Emits `\decoct($i)`.
:::

:::member[$i->toBinary(): string]
Emits `\decbin($i)`.
:::

:::member[$i->format(int $decimals = 0, string $decimalSeparator = '.', string $thousandsSeparator = ','): string]
Groups thousands: `(1234567)->format()` is `'1,234,567'`. Emits `\number_format($i, $decimals, $decimalSeparator, $thousandsSeparator)`.
:::

:::member[$i->__toString(): string]
Emits `(string) $i`.
:::

:::member[$i->__toFloat(): float]
Emits `(float) $i`.
:::

:::member[$i->__toBool(): bool]
`false` only for `0`. Emits `(bool) $i`.
:::

### Float methods

:::member[$f->abs(): float]
Emits `\abs($f)`.
:::

:::member[$f->ceil(): int]
Rounds up and returns an `int`. Emits `(int) \ceil($f)`. Values outside the `int` range (and `NAN` / `INF`) do not convert meaningfully; check `isFinite()` first when the input is untrusted.
:::

:::member[$f->floor(): int]
Rounds down and returns an `int`. Emits `(int) \floor($f)`. The same range caveat as `ceil()` applies.
:::

:::member[$f->round(int $precision = 0, int $mode = \PHP_ROUND_HALF_UP): float]
Rounds to `$precision` decimal places and stays a `float`. Emits `\round($f, $precision, $mode)`.
:::

:::member[$f->clamp(float $min, float $max): float]
Emits `\max($min, \min($max, $f))`.
:::

:::member[$f->between(float $min, float $max): bool]
Inclusive range test.
:::

:::member[$f->isNan(): bool]
Emits `\is_nan($f)`.
:::

:::member[$f->isInfinite(): bool]
Emits `\is_infinite($f)`.
:::

:::member[$f->isFinite(): bool]
Emits `\is_finite($f)`.
:::

:::member[$f->isPositive(): bool]
Emits `$f > 0.0`.
:::

:::member[$f->isNegative(): bool]
Emits `$f < 0.0`.
:::

:::member[$f->isZero(): bool]
Emits `$f == 0.0`, so `-0.0` also counts as zero.
:::

:::member[$f->sign(): int]
`-1`, `0`, or `1`. Emits `$f <=> 0.0`.
:::

:::member[$f->max(float $value, float ...$values): float]
The largest of the receiver and the arguments. At least one argument is required. Emits `\max($f, $value, ...$values)`.
:::

:::member[$f->min(float $value, float ...$values): float]
Emits `\min($f, $value, ...$values)`.
:::

:::member[$f->pow(float $exponent): float]
Emits `$f ** $exponent`.
:::

:::member[$f->sqrt(): float]
`NAN` for negative values. Emits `\sqrt($f)`.
:::

:::member[$f->log(float $base = \M_E): float]
Natural logarithm by default. Emits `\log($f, $base)`.
:::

:::member[$f->sin(): float]
Argument in radians. Emits `\sin($f)`.
:::

:::member[$f->cos(): float]
Emits `\cos($f)`.
:::

:::member[$f->tan(): float]
Emits `\tan($f)`.
:::

:::member[$f->fmod(float $divisor): float]
Floating-point remainder, with the sign of the receiver. Emits `\fmod($f, $divisor)`.
:::

:::member[$f->format(int $decimals = 0, string $decimalSeparator = '.', string $thousandsSeparator = ','): string]
`(1234.5)->format(2, ',', '.')` is `'1.234,50'`. Emits `\number_format($f, $decimals, $decimalSeparator, $thousandsSeparator)`.
:::

:::member[$f->__toString(): string]
Emits `(string) $f`.
:::

:::member[$f->__toInt(): int]
Truncates toward zero. Emits `(int) $f`.
:::

:::member[$f->__toBool(): bool]
Emits `(bool) $f`.
:::

### Bool methods

:::member[$b->__toString(): string]
`'true'` or `'false'`. This differs from a PHP cast: `(string) $b` stays a PHP cast and gives `'1'` or `''`. Emits `$b ? 'true' : 'false'`.
:::

:::member[$b->__toInt(): int]
`1` or `0`. Emits `(int) $b`.
:::

:::member[$b->not(): bool]
Emits `!$b`.
:::

:::member[$b->and(bool $other): bool]
Emits `$b && $other`, so `$other` is not evaluated when `$b` is `false`. Pass a variable or a literal as `$other`; an expression such as a comparison or a call is **TYHP4181**, because splicing it would make its evaluation conditional. Assign it to a variable first, or use `&&` directly. The receiver can be a literal: `true->not()`, `false->or($flag)`.
:::

:::member[$b->or(bool $other): bool]
Emits `$b || $other`, so `$other` is not evaluated when `$b` is `true`. The same argument rule as `and()` applies.
:::

### Closure methods

These work on any `\Closure`, including first-class callables such as `slowSquare(...)`. They call static methods on `\Tyhp\ClosureExtensions`.

:::member[$fn->then<TNextReturn>(\Closure<callable(__CallableReturnType<TThisCallable>): TNextReturn> $next): \Closure<callable(__CallableParametersRest<TThisCallable> ...): TNextReturn>]
Left-to-right composition: the result calls `$fn` with its arguments, then passes the return value to `$next`. `$trim->then($len)` trims and then measures.
:::

:::member[$fn->compose(\Closure<TNextCallable> $next): \Closure<callable(__CallableParametersRest<TNextCallable> ...): TThisReturn>]
Right-to-left composition: the result calls `$next` first, then `$fn` on its result. `$label->compose($len)` measures and then labels. Available when `$fn` takes the return type of `$next`.
:::

:::member[$fn->memoize(): \Closure<TThisCallable>]
Returns a closure with the same signature that caches results by its arguments. The cache key is `\serialize($args)`, so arguments must be serializable (closures and many resources are not), and the cache lives as long as the returned closure. Only use it for pure functions.
:::

:::member[$fn->partial(mixed ...$partialArgs): \Closure]
Fixes the leading arguments and returns a closure that takes the rest. The result is an untyped `\Closure` returning `mixed`.
:::

```tyhp
<?tyhp

function pipeline(): string {
    \Closure<callable(string): string> $trim = fn(string $s): string => \trim($s);
    \Closure<callable(string): int> $len = fn(string $s): int => \strlen($s);

    $trimThenLen = $trim->then($len);
    int $n = $trimThenLen('  hello  ');            // 5

    \Closure<callable(int): string> $label = fn(int $n): string => "len={$n}";
    $labelOfLen = $label->compose($len);
    return $labelOfLen('abc') . ' / ' . (string) $n;  // 'len=3 / 5'
}

function slowSquare(int $n): int {
    return $n * $n;
}

function cached(): int {
    \Closure<callable(int): int> $square = slowSquare(...);
    $fast = $square->memoize();
    return $fast(12) + $fast(12);                   // second call is served from the cache
}
```

## Runtime types: `\Tyhp\Type`

A `\Tyhp\Type` is a runtime description of a Tyhp type. The compiler creates them for you: `typeof(T)` produces one, `$x is ?User` and other non-native guards compile to `\Tyhp\Type::is($x, …)`, `default(T)` compiles to `->defaultValue()` once `T` is known, and tracked generic classes carry the types they were constructed with. You use the class directly when you validate untrusted data, write generic infrastructure, or pass type arguments from hand-written PHP to [`\Tyhp\Generic::bind`](#generics-bridge-tyhpgeneric). See [Compile-Time Constructs](tyhp_2700_compileTimeConstructs.md) for `typeof` and `default`.

`Type` implements `\Stringable`. Its constructor is protected; create instances with the static factories below. Scalar factories and `fromClassName()` return a shared instance per name, so `Type::int() === Type::int()`.

```tyhp
<?tyhp

use Tyhp\Type;
use Tyhp\NamedType;

function classify(mixed $value): string {
    Type $idList = Type::generic('array', new NamedType('TKey', Type::int()), new NamedType('TValue', Type::int()));
    Type $maybeName = Type::nullable(Type::string());

    if (Type::is($value, $idList)) {
        return 'ids';
    }
    if (Type::is($value, $maybeName)) {
        return 'name';
    }
    Type::check($value, Type::union(Type::int(), Type::string()));  // throws for anything else
    return (string) Type::of($value);
}

// classify([1, 2]) === 'ids'
// classify(3.5) throws IncompatibleTypeException: "Incompatible type: expected int|string, got float."
```

### Scalar and pseudo-type factories

:::member[public static function string(): self]
`string`.
:::

:::member[public static function int(): self]
`int`.
:::

:::member[public static function float(): self]
`float`. `Type::is()` accepts `int` values for `float`, matching PHP's int-to-float widening.
:::

:::member[public static function bool(): self]
`bool`.
:::

:::member[public static function null(): self]
`null`. This type is nullable and matches only `null`.
:::

:::member[public static function void(): self]
`void`. At runtime only `null` matches it, because `null` is what `default(void)` produces.
:::

:::member[public static function mixed(): self]
`mixed`. Matches every value.
:::

:::member[public static function never(): self]
`never`. Matches no value.
:::

:::member[public static function array(): self]
Any array.
:::

:::member[public static function object(): self]
Any object.
:::

:::member[public static function callable(): self]
Anything `\is_callable()` accepts.
:::

:::member[public static function iterable(): self]
Arrays and `\Traversable` objects.
:::

:::member[public static function resource(): self]
Open or closed resources.
:::

### Composite factories

:::member[public static function union(self ...$types): self]
A union. Nested unions are flattened and repeated members (the same instance) are dropped. Throws `\Tyhp\Exceptions\InvalidTypeException` when fewer than two distinct members remain, so `Type::union(Type::int(), Type::int())` is an error; use the single type instead.
:::

:::member[public static function intersection(self ...$types): self]
An intersection, flattened and de-duplicated like `union()`. Throws `InvalidTypeException` with fewer than two distinct members.
:::

:::member[public static function nullable(self $type): self]
The nullable form of `$type`. Returns `$type` itself when it is already nullable, `null`, or `mixed`.
:::

:::member[public static function generic(string $className, \Tyhp\NamedType ...$params): self]
A generic application such as `Box<int>` or `array<string, int>`. Pass one `NamedType` per type parameter in declaration order. For `'array'` and `'iterable'`, one parameter is the value type and two are key then value; `is()` then checks every element. For a class, `is()` checks the instance and, when the object tracks its own type arguments, that they are compatible.
:::

:::member[public static function struct(string $name, array<int|string, self> $fields, array<int, int|string> $requiredKeys = []): self]
A struct shape: an associative array with typed fields. `$fields` maps each key to its field type; every key in `$requiredKeys` must be present on a value. Fields that are present must match their type; missing optional fields and extra keys are ignored. `$name` is used for display only.
:::

:::member[public static function objectShape(string $name, array<int, string> $methods = [], array<int, string> $properties = []): self]
An object shape: any object that has every listed public method and public property. Only existence is checked, not signatures or property types. Do not list `__construct`. `$name` is used for display only.
:::

:::member[public static function callableShape(string $name): self]
A callable shape. Matches any value `\is_callable()` accepts; the signature is not compared. Pass the alias name, or `'callable'` for an inline shape.
:::

:::member[public static function fromClassName(string $className): self]
A class, interface, enum, or trait type. Matching uses `\is_a` on loaded names and never autoloads `$className`, so an object cannot match an interface that has not been loaded yet.
:::

:::member[public static function fromReflectionType(\ReflectionType $type, ?string $relativeClassName = null): self]
Converts a PHP reflection type. `true` and `false` become `bool`; `static` resolves to `$relativeClassName` (or `object` when it is `null`). When reflection reports `self` or `parent` unresolved, `self` resolves like `static` and `parent` to the parent class of `$relativeClassName`. A nullable reflection type becomes a nullable `Type`.
:::

:::member[public static function fromCallableReturn(callable $callable): ?self]
The declared return type of a closure, function name, `'Class::method'` string, `[$objectOrClass, 'method']` array, or invokable object. Returns `null` when the callable has no declared return type or cannot be reflected.
:::

:::member[public static function of(mixed $value): self]
The runtime type of a value: a scalar type, `array`, `resource`, or the object's class. An object that tracks its generic arguments reports its full generic type. Arrays always report plain `array`; structs and element types are not inferred.
:::

### Checking values

:::member[public static function is(mixed $value, self $type): bool]
`true` when `$value` matches `$type`. This is what compiled `is` guards call for unions, nullables, structs, shapes, generic parameters, and other types without a native PHP check. Array generics are checked element by element, so the cost grows with the size of the array.
:::

:::member[public static function isType<TTarget>(mixed $value): $value is TTarget]
A type guard: `Type::isType<int>($v)` narrows `$v` to `int` in Tyhp. From PHP, bind the type argument with `\Tyhp\Generic::bind(\Tyhp\Type::isType(...), \Tyhp\Type::int())($v)`.
:::

:::member[public static function check(mixed $value, self $type): void]
Throws `\Tyhp\Exceptions\IncompatibleTypeException` when `is()` is `false`. The exception reports `$type` as expected and `Type::of($value)` as actual.
:::

:::member[public static function compatible(self $broad, self $narrow): bool]
`true` when every value of `$narrow` is also a value of `$broad`: `mixed` accepts everything, `never` fits everywhere, a nullable type does not fit a non-nullable one, a union fits when each member fits, and a class fits its parents and interfaces. Generic applications are compared argument by argument. Struct and shape types are compatible only with the same kind and name.
:::

### Instance methods

:::member[public function defaultValue(): mixed]
The zero value for the type, which is what `default(T)` produces: `''`, `0`, `0.0`, `false`, `[]` for `array` and `iterable`, `[]` for structs, and `null` for nullable types, objects, `void`, `never`, `mixed`, `resource`, unions, and intersections.
:::

:::member[public function asNullable(): self]
Same as `Type::nullable($this)`.
:::

:::member[public function asNonNullable(): self]
A non-nullable copy, or `$this` when it is already non-nullable.
:::

:::member[public function asReadOnly(): self]
A copy flagged read-only (used for read-only type arguments). The flag does not affect `is()` or `compatible()`.
:::

:::member[public function genericParameter(string $name): ?\Tyhp\NamedType]
The type argument bound to the parameter called `$name` on a `generic()` type, or `null`.
:::

:::member[public function getKind(): string]
The descriptor kind: `'scalar'` (for all scalar and pseudo types), `'class'`, `'union'`, `'intersection'`, `'generic'`, `'struct'`, `'objectShape'`, `'callableShape'`, or `'named'` for a `NamedType`.
:::

:::member[public function getName(): ?string]
The scalar name, class name (`'array'` for an `array` generic), struct or shape name, or the parameter name for a `NamedType`; `null` for unions and intersections.
:::

:::member[public function isNullable(): bool]
`true` for `null` and for types made nullable with `nullable()`. A union that merely contains `Type::null()` reports `false`, although `is(null, …)` still matches it.
:::

:::member[public function isReadOnly(): bool]
`true` after `asReadOnly()`.
:::

:::member[public function __toString(): string]
Tyhp spelling: `'?string'`, `'int|string|null'`, `'Box<int>'`, `'struct App\User'`, `'object HasName'`, `'callable callable'`.
:::

### `\Tyhp\NamedType`

`final class NamedType extends \Tyhp\Type` pairs a generic parameter name with the type bound to it. It is the argument type of `Type::generic()`. Matching and display delegate to the underlying type, and its nullability follows the underlying type.

:::member[public function __construct(string $parameterName, \Tyhp\Type $underlyingType, bool $readOnly = false)]
Binds `$underlyingType` to the parameter `$parameterName` (for example `'T'` or `'TValue'`).
:::

:::member[public function getParameterName(): string]
The parameter name.
:::

:::member[public function getUnderlyingType(): \Tyhp\Type]
The bound type.
:::

:::member[public function asReadOnly(): self]
A read-only copy with the same name and underlying type.
:::

:::member[public function __toString(): string]
The underlying type's string form; the parameter name is not included.
:::

## Typed JSON: `\Tyhp\Json`

`\Tyhp\Json` decodes JSON straight into a Tyhp struct and verifies the shape, the way `JsonSerializer.Deserialize<T>` does in C#. JSON objects always decode to associative arrays, which is how structs are represented in PHP. The string methods `jsonDecodeAs<T>()` and `jsonTryDecodeAs<T>()` are shorthands for these two methods. `\json_decode` itself stays an ordinary PHP builtin; see [New Functions](tyhp_0151_newFunctions.md).

:::member[public static function decode<T extends struct>(string $json, int $depth = 512, int $flags = 0): T]
Decodes `$json` and checks the result against `T` with `Type::is()`. `\JSON_THROW_ON_ERROR` is always added to `$flags`. Throws `\JsonException` for invalid JSON (including exceeding `$depth`) and `\Tyhp\Exceptions\IncompatibleTypeException` when the decoded value does not match `T`: it is not an object, a field has the wrong type, or a required field (one that is neither nullable nor defaulted) is missing. Absent fields are not filled in from the struct's defaults; the decoded array contains only what the JSON contained.
:::

:::member[public static function tryDecode<T extends struct>(string $json, T &$out, int $depth = 512, int $flags = 0): bool]
Like `decode()`, but returns `false` instead of throwing for invalid JSON or a shape mismatch, and leaves `$out` unchanged in that case. On success, writes the value to `$out` and returns `true`.
:::

```tyhp
<?tyhp

namespace App;

use Tyhp\Json;
use Tyhp\Exceptions\IncompatibleTypeException;

type User = struct {
    int $id;
    string $name;
    ?string $email;
};

function loadUser(string $json): User {
    try {
        return Json::decode<User>($json);
    } catch (\JsonException $e) {
        throw new \RuntimeException('Malformed user JSON: ' . $e->getMessage(), 0, $e);
    } catch (IncompatibleTypeException $e) {
        throw new \RuntimeException('Unexpected user shape: ' . $e->getMessage(), 0, $e);
    }
}

function tryUser(string $json): ?User {
    User $user = new User() with [id => 0, name => ''];
    if (!Json::tryDecode<User>($json, $user)) {
        return null;
    }
    return $user;
}

// loadUser('{"id": 7, "name": "Ada"}') returns ['id' => 7, 'name' => 'Ada']
// loadUser('{"id": 7, "name": "Ada", "email": null}') returns ['id' => 7, 'name' => 'Ada', 'email' => null]
// loadUser('{"id": "7", "name": "Ada"}') throws RuntimeException:
//     "Unexpected user shape: Incompatible type: expected struct App\User, got array."
// loadUser('{"name": "Ada"}') throws the same exception: `id` is required.
// loadUser('{"id": 7') throws RuntimeException: "Malformed user JSON: Syntax error"
// tryUser('{"id": "x"}') returns null
```

A struct field is required when it is neither nullable nor given a default, so `email` may be absent or `null` while `id` and `name` must be present. Keys the struct does not declare are kept in the decoded array.

From hand-written PHP, bind `T` with [`\Tyhp\Generic::bind`](#generics-bridge-tyhpgeneric), passing a `Type::struct()` descriptor whose third argument lists the required keys:

```php
<?php

declare(strict_types=1);

use Tyhp\Generic;
use Tyhp\Json;
use Tyhp\Type;

$userType = Type::struct('App\\User', [
    'id' => Type::int(),
    'name' => Type::string(),
    'email' => Type::nullable(Type::string()),
], ['id', 'name']);

$decodeUser = Generic::bind(Json::decode(...), $userType);

try {
    $user = $decodeUser('{"id": 7, "name": "Ada"}');
} catch (\Throwable $e) {
    \error_log('Could not decode user: ' . $e->getMessage());
}
```

## Generics bridge: `\Tyhp\Generic`

Tyhp generics are erased from PHP signatures. When a generic class or callable needs its type arguments at runtime, the compiler emits a factory or binder and stamps the declaration with [`#[\Tyhp\GenericRuntime]`](#tyhpgenericruntime). Inside one compilation, Tyhp calls those helpers directly. `\Tyhp\Generic::bind` is the stable entry point for everyone else: hand-written PHP, and Tyhp code that uses a generic from another compiled library (the compiler emits `bind` for those call sites). See [Generics](tyhp_0500_generics.md#compiled-php-output).

`final class Generic` cannot be constructed directly.

:::member[public static function bind(mixed $target, ?\Tyhp\Type ...$typeArguments): mixed]
Binds type arguments to a generic class or callable. Pass one `Type` per type parameter of the target, in declaration order. A `null` (or an omitted trailing argument) leaves that parameter unbound, and it resolves the way a missing type argument does in Tyhp: the declared default, else the constraint, else `mixed`.

When `$target` is a class name, `bind` returns a `Generic` binder; nothing is constructed until you call `new(...)` or invoke the binder. When `$target` is a callable, `bind` returns a `\Closure` that takes the target's value arguments. For a static method or function, pass a first-class callable (`\Vendor\Util::first(...)`) or a `'Class::method'` / function-name string; for an instance method, pass `$object->method(...)` so the receiver is known. By-reference parameters are preserved.

Throws `\Tyhp\Exceptions\InvalidTypeException` when the target is not a compiled Tyhp generic (no `GenericRuntime` stamp), was compiled with a binding layout this runtime does not support, or is an instance method bound without a receiver. Throws `\ReflectionException` when a class name cannot be loaded, and `\InvalidArgumentException` when `$target` is an anonymous closure (other than one made by `wrapCallable`) or neither a class name nor a resolvable callable.
:::

:::member[public static function wrapCallable(\Closure $target, \Closure $factory): \Closure]
Wraps the first-class callable of a generic function or method so that it keeps its type-binding identity. The compiler emits it for a generic function whose first-class callable needs implicit `operator convert` conversions. `$target` is the native first-class callable. `$factory` is `fn(\Closure $target): \Closure` and returns the closure that converts the arguments and then calls `$target`. The result behaves as `$factory($target)`; `Generic::bind` on it binds `$target` and applies `$factory` to the bound closure, so the conversions survive the binding.

Throws `\InvalidArgumentException` when `$factory` does not return a `\Closure`.
:::

:::member[public function new(mixed ...$constructorArguments): object]
Runs the class's constructor with the bound type arguments and returns the instance. Named arguments are forwarded to the constructor by name. Each binder constructs exactly one object: a second `new()` or invocation on the same binder throws `\LogicException` ("Generic instance of 'Vendor\Box' has already been constructed."). Call `bind()` again for another instance. Prefer `new()` over invoking the binder when you want IDEs and static analyzers to infer the instance type.
:::

:::member[public function __invoke(mixed ...$constructorArguments): object]
Same as `new()`.
:::

```php
<?php

declare(strict_types=1);

use Tyhp\Generic;
use Tyhp\Type;

// A generic class from a compiled Tyhp library: class Box<T> { public function __construct(T $value) {} }
$intBox = Generic::bind(\Vendor\Box::class, Type::int())->new(42);

// A generic method: public function identity<T>(T $value): T
$identity = Generic::bind($helper->identity(...), Type::string());
$value = $identity('hello');
```

## Object `with` helper: `\Tyhp\ObjectHelper`

A `with` expression used as a value compiles to `\Tyhp\ObjectHelper::with(...)` for `new Widget() with [color => 'blue']` on a class without readonly overrides (on every PHP version), and for `clone $cfg with [...]` when the target is PHP 8.2–8.4. On PHP 8.5, `clone $cfg with [...]` uses PHP's native `clone($cfg, [...])`. See [The with Keyword](tyhp_2200_withKeyword.md#compiled-php-output).

:::member[public static function with<TProperties extends struct, T extends object&TProperties>(T $object, TProperties $properties): T]
Assigns each entry of `$properties` to the property of the same name on `$object` and returns the same instance; it does not clone. Throws `\Tyhp\Exceptions\PropertyNotFoundException` when a key is not a property of the object. Readonly properties cannot be assigned this way.
:::

## String helper: `\Tyhp\StringHelper`

`final class StringHelper` holds the multibyte-or-byte switch behind the string methods. Each method uses the `\mb_*` function when `ext-mbstring` is loaded and the byte function otherwise. Compiled code calls it; you can call it from PHP for the same behaviour.

:::member[public static function hasMbStringExt(): bool]
`true` when `ext-mbstring` is loaded. The answer is cached for the request.
:::

:::member[public static function strlen(string $string): int]
`\mb_strlen` or `\strlen`.
:::

:::member[public static function substr(string $string, int $start, ?int $length = null): string]
`\mb_substr` or `\substr`.
:::

:::member[public static function strpos(string $haystack, string $needle, int $offset = 0): int|false]
`\mb_strpos` or `\strpos`.
:::

:::member[public static function strrpos(string $haystack, string $needle, int $offset = 0): int|false]
`\mb_strrpos` or `\strrpos`.
:::

:::member[public static function stripos(string $haystack, string $needle, int $offset = 0): int|false]
`\mb_stripos` or `\stripos`.
:::

:::member[public static function strtolower(string $string): string]
`\mb_strtolower` or `\strtolower`.
:::

:::member[public static function strtoupper(string $string): string]
`\mb_strtoupper` or `\strtoupper`.
:::

:::member[public static function strSplit(string $string, int $length = 1): array<int, string>]
`\mb_str_split` or `\str_split`.
:::

:::member[public static function ord(string $string): int|false]
`\mb_ord` or `\ord`.
:::

:::member[public static function ucWords(string $string): string]
`\mb_convert_case($string, \MB_CASE_TITLE)` or `\ucwords`.
:::

:::member[public static function convertEncoding(string $string, string $toEncoding, array|string|null $fromEncoding = null): string|false]
`\mb_convert_encoding`, or `false` without mbstring.
:::

:::member[public static function detectEncoding(string $string): string|false]
`\mb_detect_encoding`, or `false` without mbstring.
:::

:::member[public static function strPad(string $string, int $length, string $padString = ' ', int $padType = \STR_PAD_RIGHT): string]
`\mb_str_pad` or `\str_pad`. Exists only when `output.phpVersion` is 8.3 or later.
:::

:::member[public static function ucFirst(string $string): string]
`\mb_ucfirst` or `\ucfirst`. Exists only when `output.phpVersion` is 8.4 or later.
:::

:::member[public static function lcFirst(string $string): string]
`\mb_lcfirst` or `\lcfirst`. Exists only when `output.phpVersion` is 8.4 or later.
:::

## Contracts

### `\Tyhp\Contracts\IsDisposable`

```tyhp
<?tyhp

interface IsDisposable {
    public function dispose(): void;
}
```

Implement it on classes that own something that must be released: file handles, locks, connections, temporary files. `using (...)` blocks and `:=` declarations call `dispose()` for you; see [Disposables](tyhp_2300_disposables.md). Make `dispose()` safe to call more than once. The asynchronous counterpart, `AsyncIsDisposable`, and the `DisposableScope` that `:=` uses live in `tyhp/async`; see [the tyhp/async package](package_async.md).

```tyhp
<?tyhp

use Tyhp\Contracts\IsDisposable;

final class TempFile implements IsDisposable {
    private bool $closed = false;

    public function __construct(public readonly string $path) {}

    public function dispose(): void {
        if ($this->closed) {
            return;
        }
        $this->closed = true;
        if (\is_file($this->path)) {
            \unlink($this->path);
        }
    }
}

function writeReport(): int {
    TempFile $tmp = new TempFile(\sys_get_temp_dir() . '/report.csv');
    try {
        int|false $written = \file_put_contents($tmp->path, "a,b\n");
        return $written === false ? 0 : $written;
    } finally {
        $tmp->dispose();
    }
}
```

### Conversion contracts

| Interface | Declares | Extends |
|-----------|----------|---------|
| `\Tyhp\Contracts\Convertible` | nothing (marker) | — |
| `\Tyhp\Contracts\IntConvertible` | `public function __toInt(): int;` | `Convertible` |
| `\Tyhp\Contracts\FloatConvertible` | `public function __toFloat(): float;` | `Convertible` |
| `\Tyhp\Contracts\BoolConvertible` | `public function __toBool(): bool;` | `Convertible` |
| `\Tyhp\Contracts\StringConvertible` | `__toString()` via `\Stringable` | `\Stringable`, `Convertible` |

These interfaces mark a class that converts itself to a scalar. When a class declares a convert-to operator (`operator convert(self $value): int`), the compiler emits the matching `__toInt()` method, adds the matching interface for you, and rewrites explicit casts, arguments, and return values to the call (`(int) $celsius`, `takesInt($celsius)`, and `return $celsius;` from an `int` function all become `$celsius->__toInt()`). See [Operator Overloads](tyhp_1600_operatorOverloads.md#conversion-operators). If you implement an interface by hand instead, you get the method and the type, but only `operator convert` triggers the rewrites: `(int) $value` stays an ordinary PHP cast, so call the method explicitly. Use `Convertible` as a parameter type when any conversion is acceptable.

### `\Tyhp\Contracts\ArrayAccessShape<TStruct extends struct>`

Per-key array access over a struct schema: `$config['host']` has the `host` field's type and `$config['port']` the `port` field's type. It extends `\ArrayAccess<__IndexKeys<TStruct>, __IndexValueTypes<TStruct>>`.

```tyhp
<?tyhp

interface ArrayAccessShape<TStruct extends struct> extends \ArrayAccess<__IndexKeys<TStruct>, __IndexValueTypes<TStruct>> {
    public function offsetExists(#[\Tyhp\PhpType('mixed')] __IndexKeys<TStruct> $offset): bool;

    #[\Tyhp\PhpType('mixed')]
    public function offsetGet<TKey extends __IndexKeys<TStruct>>(#[\Tyhp\PhpType('mixed')] TKey $offset): __IndexValueType<TStruct, TKey>;

    public function offsetSet<TKey extends __IndexKeys<TStruct>>(#[\Tyhp\PhpType('mixed')] TKey $offset, #[\Tyhp\PhpType('mixed')] __IndexValueType<TStruct, TKey> $value): void;

    public function offsetUnset(#[\Tyhp\PhpType('mixed')] __IndexKeys<TStruct> $offset): void;
}
```

The `#[\Tyhp\PhpType('mixed')]` attributes keep the emitted PHP signatures compatible with `\ArrayAccess`; implementors inherit them. Call sites must index with a key literal. The rules for implementing `offsetGet` and `offsetSet` (per-key coverage, `TYHP4331`–`TYHP4333`) are on [New and Changed Types](tyhp_0150_newTypes.md#the-tyhpcontractsarrayaccessshapetstruct-type).

## Attributes

### `#[\Tyhp\Php]`

:::member[#[\Tyhp\Php(string $version)]]
Keeps the declaration only when `output.phpVersion` satisfies the Composer constraint `$version` (`">=8.4"`, `">=8.2 <8.4"`). `#[\Tyhp\Php(">=8.4")]` and `#[\Tyhp\Php(version: ">=8.4")]` are equivalent. It is valid on any declaration except `struct` and `extension`; wrap those in `declare(php="…") { }`. The attribute is compile-time only and is removed from emitted PHP. See [PHP Version Gating](tyhp_0320_phpVersionGating.md#tyhpphp).
:::

```tyhp
<?tyhp

#[\Tyhp\Php(">=8.4")]
function onlyOn84(): string {
    return 'new';
}
```

### `#[\Tyhp\PhpType]`

:::member[#[\Tyhp\PhpType(string $type)]]
Replaces the emitted PHP type of the parameter, return type, property, or typed constant it is on, without changing the Tyhp type the checker sees. `$type` is a PHP type spelling such as `'mixed'` or `'string|int'`. Implementing an interface or abstract member inherits the attribute. Compile-time only. Not valid on classes. See [New and Changed Types](tyhp_0150_newTypes.md#the-tyhpphptype-attribute).
:::

### `#[\Tyhp\NativeTypeTest]`

:::member[#[\Tyhp\NativeTypeTest]]
Marks a free function or concrete static method whose return is a type guard (`function isUuid(mixed $value): $value is Uuid`) as the native check for that type. `$x is Uuid` then compiles to a call of that function instead of `\Tyhp\Type::is`. The guard type must be a single type, extra parameters need defaults, and two markers for the same type conflict (`TYHP4340`–`TYHP4344`). `tyhpdef/php` marks `is_string`, `is_int`, and the other built-in checks this way. Compile-time only. See [Type Narrowing and Guards](tyhp_0200_typeNarrowingAndGuards.md).
:::

### `#[\Tyhp\EraseGeneric]`

:::member[#[\Tyhp\EraseGeneric]]
Opts a generic-typed property, promoted constructor parameter, or every generic-typed property of a class out of runtime property type checks. A class with generic-typed properties is otherwise tracked at runtime so writes are checked against the bound type argument. Uses of `typeof(T)`, `default(T)`, `is T`, `new T()`, or forwarded type arguments still force tracking. Not inherited. Not valid on methods or functions (`TYHP4345`). Compile-time only. See [Generics](tyhp_0500_generics.md).
:::

### `#[\Tyhp\AllowUnset]`

:::member[#[\Tyhp\AllowUnset]]
Allows `unset($this->prop)` on a typed property or promoted constructor parameter. Without it, unsetting a typed property is an error (`TYHP4158`), because PHP returns the property to the uninitialized state. With it, the checker treats the property as possibly uninitialized when an instance method starts, so guard reads with `isset()` or `??` (`TYHP4157` otherwise). When "no value" and `null` mean the same thing, declare `?T $prop = null` instead. This attribute is kept in the emitted PHP.
:::

```tyhp
<?tyhp

final class Profile {
    #[\Tyhp\AllowUnset]
    public string $cachedName;

    public function __construct(string $name) {
        $this->cachedName = $name;
    }

    public function forget(): void {
        unset($this->cachedName);
    }
}
```

### `#[\Tyhp\GenericRuntime]`

:::member[#[\Tyhp\GenericRuntime(bool $erased = false, ?string $binder = null, ?string $factory = null, ?string $aliasFactory = null, array<int> $layouts = [1], ?string $compiler = null)]]
The compiler stamps this attribute on every generic class, method, and function it emits; you do not write it (an authored one is overwritten, `TYHP4346`). It is kept in the emitted PHP so `\Tyhp\Generic::bind` can find the declaration's factory or binder at runtime. Its readonly public properties describe the declaration: `erased` (no runtime helpers were emitted), `binder` (generic method or function helper), `factory` (generic class helper), `aliasFactory` (the `\Tyhp\Type` factory of a type alias), `layouts` (supported binding layouts; this runtime supports `1`), and `compiler` (the compiler version, for diagnostics only).
:::

### `#[\Tyhp\NoEmit]`

:::member[#[\Tyhp\NoEmit]]
Marks an attribute class as compile-time only: the class and every use of it are left out of the emitted PHP. `Php`, `PhpType`, `NativeTypeTest`, `EraseGeneric`, `Optimize\Pure`, and `Optimize\Inline` carry it. Valid on classes.
:::

### `#[\Tyhp\Optimize\Pure]` and `#[\Tyhp\Optimize\Inline]`

:::member[#[\Tyhp\Optimize\Pure]]
Documents that a function or method has no side effects and depends only on its arguments. The scalar catalog marks its side-effect-free members this way. Compile-time only: it does not change checking or the emitted PHP, and the attribute is removed from the output.
:::

:::member[#[\Tyhp\Optimize\Inline]]
Applies the call-site splice safety rules to a function or method. Calls to it stay ordinary PHP calls; the checker validates that its single-`return` body could be spliced safely: a parameter the body writes must be declared `&` (`TYHP4174`), and members that call each other in a cycle are rejected (`TYHP4175`). It is an error on extension members (`TYHP4176`), where the member's form (short `fn` or full body) already decides whether a call is spliced. Compile-time only; the attribute is removed from emitted PHP.
:::

## Exceptions

All exception classes are `final` and live in `\Tyhp\Exceptions`.

### `IncompatibleTypeException`

`final class IncompatibleTypeException extends \RuntimeException`. Thrown when a value does not match a required type at runtime: `Type::check()`, `Json::decode()`, generic property writes in tracked classes, and other runtime checks the compiler emits. The message reads `Incompatible type for $name: expected X, got Y.` (the `for $name` part only when a name is known).

:::member[public function __construct(\Tyhp\Type $expected, \Tyhp\Type $actual, ?string $variableOrParameterName = null, ?\Throwable $previous = null)]
Builds the message from the two types and the optional name.
:::

:::member[public function getExpectedType(): \Tyhp\Type]
The type that was required.
:::

:::member[public function getActualType(): \Tyhp\Type]
The type of the value that was found, usually `Type::of($value)`.
:::

:::member[public function getVariableOrParameterName(): ?string]
The variable, parameter, or property name without `$`, when known.
:::

### `InvalidTypeException`

`final class InvalidTypeException extends \LogicException`. Signals a programming error in how types are used: a union or intersection with fewer than two distinct members, or a `\Tyhp\Generic::bind` call on something that is not a compiled Tyhp generic. It has no members beyond `\LogicException`.

### `AggregateException`

`final class AggregateException extends \RuntimeException`. Carries several exceptions at once. A `using` block throws it when more than one resource fails to dispose; see [Disposables](tyhp_2300_disposables.md). Other runtime packages throw it from combinators that collect failures.

:::member[public function __construct(array<\Throwable> $innerExceptions, string $message = 'One or more errors occurred', ?\Throwable $previous = null)]
Throws `\InvalidArgumentException` when an element of `$innerExceptions` is not a `\Throwable`.
:::

:::member[public function getInnerExceptions(): array<\Throwable>]
The collected exceptions, in the order given.
:::

```tyhp
<?tyhp

use Tyhp\Contracts\IsDisposable;
use Tyhp\Exceptions\AggregateException;

function closeAll(array<int, IsDisposable> $resources): void {
    array<int, \Throwable> $errors = [];
    foreach ($resources as $r) {
        try {
            $r->dispose();
        } catch (\Throwable $e) {
            $errors[] = $e;
        }
    }
    if ($errors !== []) {
        throw new AggregateException($errors, 'Some resources failed to close');
    }
}
```

### `PropertyNotFoundException`

`final class PropertyNotFoundException extends \RuntimeException`. Thrown by `ObjectHelper::with()` (and therefore by compiled `with` expressions) when a key does not name a property of the object. Message: `Property 'name' does not exist on class 'Class'.`

:::member[public function __construct(string $propertyName, string $className, ?\Throwable $previous = null)]
Builds the message.
:::

:::member[public function getPropertyName(): string]
The missing property name.
:::

:::member[public function getClassName(): string]
The object's class.
:::

### `InvalidParametersForOperatorOverloadException`

`final class InvalidParametersForOperatorOverloadException extends \RuntimeException`. Thrown by a compiled operator-overload method when the runtime operand types match none of the declared forms, for example when a value reaches the operator through `mixed`. Message: `Invalid parameters for operator overload Class::method() — received: int, string.` See [Operator Overloads](tyhp_1600_operatorOverloads.md).

:::member[public function __construct(string $className, string $methodName, mixed ...$operands)]
Records the class, the generated operator method name, and the operands' types.
:::

:::member[public function getClassName(): string]
The class that declares the operator.
:::

:::member[public function getMethodName(): string]
The generated operator method name.
:::

## Compiled-code plumbing

The following public types exist so that emitted PHP can implement Tyhp features on every supported PHP version. They are used by compiled code; you don't call them directly, and their members can change with the compiler. You will see them in generated PHP, `var_dump` output, and stack traces.

| Name | Purpose |
|------|---------|
| `\Tyhp\PropertyAccessor<TValue>`, `\Tyhp\PropertyAccessorObject`, `\Tyhp\PropertyBackingCell` | Polyfill for PHP 8.4 property hooks (`get` / `set`, asymmetric visibility, `final` hooks, `parent::$prop::get()`) when `output.phpVersion` is below 8.4. |
| `\Tyhp\GenericObject` | Per-instance record of the type arguments a tracked generic object was constructed with; backs `typeof(T)`, `default(T)`, and generic property checks inside the class. |
| `\Tyhp\Concerns\HasGenerics` | Adds the `$__tyhpGeneric` property that holds a `GenericObject`. |
| `\Tyhp\Concerns\HasPropertyAccessors`, `UsesPropertyAccessors` | Add the `$__tyhpPropertyHook` property that holds a `PropertyAccessorObject`. |
| `\Tyhp\Concerns\HandlesGet`, `HandlesSet`, `HandlesIsset`, `HandlesUnset` | Dispatch `__get`, `__set`, `__isset`, and `__unset` to registered handlers. |
| `\Tyhp\Concerns\BootsTraits` | Runs each trait's `__bootTrait_*` initializer once per instance. |
| `\Tyhp\StringExtensions` and the other catalog classes | Static methods for catalog members that need a PHP body (see [How to read the signatures](#how-to-read-the-signatures)). |

When a class uses property hooks on a PHP target below 8.4, the `Handles*` traits supply `final` `__get`, `__set`, `__isset`, and `__unset` methods, so subclasses cannot override them. If the class defines one of those magic methods itself, its own method is kept and the compiler inserts the hook dispatch at the top of it.

## The Composer plugin

`tyhp/core` is a Composer plugin (`"type": "composer-plugin"`, class `Tyhp\Composer\Plugin`). Its job is to make the type definitions your dependencies need for type-checking land in your project automatically. A Tyhp library lists those packages in `extra.tyhp.require` of its `composer.json`; the plugin collects them across your whole dependency tree and writes them to your root `require-dev`. The rules for what belongs in `extra.tyhp.require` are on [Composer Runtime Packages](project_composerPackages.md#ambient-tyhpdefs-extratyhprequire).

Composer only runs plugins that you allow:

```json
"config": {
    "allow-plugins": {
        "tyhp/core": true
    }
}
```

`tyhp init`, `tyhp composer` (including `tyhp composer sync`), and `tyhp build --fix` add that key when it is missing and never overwrite an explicit `false`.

### What it does on each Composer run

The plugin runs once per Composer command, before Composer resolves dependencies (`pre-pool-create`):

1. **Skips dev-less installs.** Nothing happens when the run excludes dev dependencies: `--no-dev`, `COMPOSER_NO_DEV` set to a true value, `COMPOSER_DEV_MODE=0`, or a lock file installed without dev packages.
2. **Walks the dependency tree.** It starts from your root `require`, `require-dev`, and `extra.tyhp.require`, looks each package up in your configured repositories (the highest version that matches the constraint), and follows that package's `require` and `extra.tyhp.require`. A dependency's own `require-dev` is never followed. Platform packages (`php`, `ext-*`, `lib-*`, `composer-plugin-api`, …) are skipped.
3. **Merges the collected pins onto your root `require-dev`.** Packages already in your root `require` are left alone, and your own package name is never added. When the same package is pinned twice and the constraints overlap, the existing pin is kept. When they cannot both be satisfied, the Composer command fails with `TYHP7700`.
4. **Adds the compiler.** When `tyhp/core` is in the graph and `tyhp/compiler` is not already pinned, it adds `"tyhp/compiler": "@dev"`, unless your root package is `tyhp/compiler`.
5. **Writes `composer.json`.** When the merged `require-dev` differs from yours, it rewrites the root `composer.json`: existing entries keep their order, new entries are appended in alphabetical order, other keys are preserved, and `config.allow-plugins.tyhp/core` is added if missing. The new requirements are also fed into the running Composer command. If the file cannot be read or written, the command fails with `TYHP7703`.

For example, if your application requires a library whose `composer.json` contains:

```json
{
    "name": "acme/invoices",
    "require": {
        "php": ">=8.2",
        "tyhp/core": "804.0.*"
    },
    "extra": {
        "tyhp": {
            "require": {
                "tyhpdef/php": "@dev",
                "tyhpdef/php-ext-intl": "@dev"
            }
        }
    }
}
```

then after `composer update` your root `require-dev` contains `tyhpdef/php`, `tyhpdef/php-ext-intl`, and `tyhp/compiler`, and the type checker sees the `intl` definitions that `acme/invoices` exposes in its public API.

:::note
A package's `extra.tyhp.require` is only known once Composer can see that package in a repository. The very first `composer require` of a Tyhp library therefore often installs the library without its extras. Run `composer update` or `tyhp composer sync` once more. `tyhp build` and `tyhp lint` report missing extras (`TYHP7701`) but never change `composer.json` themselves; see [CLI: Composer](cli_composer.md).
:::

## Common mistakes

:::danger
Don't add `use extension \Tyhp\StringExtensions;` (or any other catalog) to a file just to "enable" scalar methods. They are already global; the import only warns (`TYHP4169`). Use a local `use extension` only to hide or rename members.
:::

:::danger
Don't compare `indexOf()`, `lastIndexOf()`, `search()`, or `strpos`-style results with `!= false` or treat them as booleans. Position `0` and key `0` are valid results; compare with `=== false`.
:::

:::warning
`contains()` and `search()` on arrays compare loosely by default, like `\in_array`. Pass `true` as the second argument when values can be numeric strings or of mixed types.
:::

:::warning
`filtered()` and `unique()` keep the original keys. A filtered list such as `[0 => 'a', 2 => 'c']` encodes as a JSON object, not an array. Call `->values()` when you need a list.
:::

:::warning
`$flag->__toString()` gives `'true'` / `'false'`, but `(string) $flag` is still PHP's cast and gives `'1'` / `''`. Choose deliberately when building output.
:::

:::warning
`Type::union()` and `Type::intersection()` throw `InvalidTypeException` when fewer than two distinct members remain. When you build unions from data, handle the single-type case yourself.
:::

:::warning
A `\Tyhp\Generic` binder constructs one object. Calling `new()` (or invoking the binder) a second time throws `\LogicException`; call `bind()` again for each instance.
:::

:::tip
Prefer `Json::decode<T>()` or `$json->jsonDecodeAs<T>()` over `$json->jsonDecode()` whenever the shape is known. You get a typed value and a precise error instead of `mixed`.
:::

## Related

- [Scalar Pseudo-Objects](tyhp_1000_scalarPseudoObjects.md) — how scalar method calls work in the language
- [Extensions](tyhp_2100_extensions.md) — writing your own extension methods; `use extension` adaptations
- [Generics](tyhp_0500_generics.md) — runtime tracking, `#[\Tyhp\EraseGeneric]`, `\Tyhp\Generic::bind`
- [New and Changed Types](tyhp_0150_newTypes.md) — `ArrayAccessShape`, `#[\Tyhp\PhpType]`, `\Closure<…>`
- [Compile-Time Constructs](tyhp_2700_compileTimeConstructs.md) — `typeof`, `default`, `nameof`
- [Type Narrowing and Guards](tyhp_0200_typeNarrowingAndGuards.md) — `is`, `instanceof`, `#[\Tyhp\NativeTypeTest]`
- [PHP Version Gating](tyhp_0320_phpVersionGating.md) — `#[\Tyhp\Php]` and `declare(php=…)`
- [Disposables](tyhp_2300_disposables.md) — `IsDisposable`, `using`, `:=`
- [Operator Overloads](tyhp_1600_operatorOverloads.md) — `convert` and the `*Convertible` contracts
- [The with Keyword](tyhp_2200_withKeyword.md) — `\Tyhp\ObjectHelper::with`
- [Composer Runtime Packages](project_composerPackages.md) and [CLI: Composer](cli_composer.md) — versions, `extra.tyhp.require`, the plugin
- [Runtime packages overview](package_intro.md), [tyhp/async](package_async.md), [tyhp/decimal](package_decimal.md), [tyhp/lambda](package_lambda.md)
