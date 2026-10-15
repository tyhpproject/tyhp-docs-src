---
title: 'PHP Version Gating'
status:
  tier: 2
  story: '20.5'
  state: complete
---

Tyhp can keep or drop declarations according to PHP version. Two gates exist: `declare(php="…")` and `#[\Tyhp\Php("…")]`. Both use Composer version-constraint strings. `output.phpVersion` is the **oldest PHP the build runs on**: the compiler binds and checks against it, and it writes a `\PHP_VERSION_ID` check into the PHP for a gate that holds on only some versions at or above it. See [What is emitted](#what-is-emitted).

This is not an existence check such as `if (!\function_exists(…))`. Those declaration gates are covered on [Declaration Gating](tyhp_0310_declarationGating.md). Extension presence uses `declare(ext="name")` and `declare(ext="!name")`, evaluated from loaded tyhpdef packages that `require` `ext-name`. It is also not the managed PHP runtime that `tyhp generate_tyhpdef` can download for reflection — that tool's `--php` / `--php-targets` path is separate from `output.phpVersion`. `#[\Tyhp\PhpType]` is a different attribute: it replaces an emitted PHP type hint. See [New and Changed Types](tyhp_0150_newTypes.md#the-tyhpphptype-attribute).

Version gates are how one `tyhpdef/php` (and one `tyhpdef/php-ext-*` per optional extension) stubs package can describe APIs that differ across PHP 8.2–8.5. In `.tyhpdef`, the compiler keeps only the declarations that match `output.phpVersion`.

## 8.2–8.5 matrix in `tyhpdef/php`

The same `tyhpdef/php` tree is used for every supported minor. Change `output.phpVersion` and lint/build — you do not install four PHP runtimes to type-check the stubs.

| Target | Always-present surface | Examples that appear at this minor |
|--------|------------------------|------------------------------------|
| `"8.2"` | Core, date, filter, hash, json, libxml, pcre, random, Reflection, SPL, standard | Baseline only |
| `"8.3"` | same | `json_validate()` (`declare(php=">=8.3")`) |
| `"8.4"` | same | `array_find()` / `array_find_key()` / `array_any()` / `array_all()` (`declare(php=">=8.4")`) |
| `"8.5"` | same | `array_first()` / `array_last()` (`declare(php=">=8.5")`); `#[\Tyhp\Php(">=8.5")]` on selected Core members |

Scalar extension methods that differ by minor (for example `pad` / `ucFirst` on strings) use the same `declare(php=…)` blocks in the Tyhp source of `tyhp/core` (`StringExtensionsVersioned` and `ArrayExtensionsVersioned` in `tyhp_src/`). Each published `tyhp/core` artifact contains the `package.tyhpdef` for one PHP minor, with the variants that apply to that minor already selected.

PHP Core attribute **classes** are gated the same way (`\Override` at 8.3, `\Deprecated` at 8.4, `\NoDiscard` and `\DelayedTargetValidation` at 8.5). Some **checks** still run below those minors — see [Engine attributes and `output.phpVersion`](#engine-attributes-and-outputphpversion).

## The minimum PHP version

Set it in `tyhp.json`:

```json
{
    "output": {
        "phpVersion": "8.4"
    }
}
```

Supported values are `"8.0"` through `"8.5"`. A value such as `"8.2"` is compared as PHP `8.2.0`. The whole emitted file uses syntax that parses on that version — a `declare(php=">=8.5")` block in an `"8.2"` project still gets the 8.2 spelling of `|>`, `(void)`, and `clone with`. Gate constraints accept any PHP version string; the `tyhpdef/php` stubs package specifically covers 8.2–8.5, so `output.phpVersion` values of `"8.0"` or `"8.1"` see none of that package's version-gated declarations.

If `output.phpVersion` is omitted (and the legacy top-level `phpVersion` key is omitted too), the compiler uses **`8.2`** and emits warning **TYHP4306** once per compilation — not once per file:

> `output.phpVersion` is unset; defaulting to `8.2`

An explicit but unsupported value is a different path: the compiler warns **TYHP6006** and falls back to `8.4`.

## `declare(php="…")`

The declare key is `php`. The value is a string. That directive must appear **alone** in that `declare` statement (**TYHP4301** if you mix it with `strict_types`, `output_file`, or anything else). Consecutive declares are fine:

```tyhp
<?tyhp

declare(strict_types=1);
declare(php=">=8.4");
```

```tyhp
<?tyhp

// ERROR TYHP4301 — php is not alone
// declare(php=">=8.4", strict_types=1);
```

### File-level (semicolon form)

A non-block `declare(php="…");` gates the **entire file**. If the constraint does not match `output.phpVersion`, the compiler skips the file's declarations silently — no TYHP4302, and those symbols are simply absent.

```tyhp
<?tyhp

declare(php=">=8.5");

function only_on_php85(): void {}
```

Use this form when you want a whole `.tyhp` file (including a top-level `extension` or `struct`) to exist only for some PHP minors. See [Structs and extensions](#structs-and-extensions).

### Block-level

A `declare(php="…") { … }` block gates only its body. Sibling code outside the block is unchanged. Inactive bodies contribute no symbols.

```tyhp
<?tyhp

function always_present(): void {}

declare(php=">=8.4") {
    function isValidJson(string $json, int $depth = 512, int $flags = 0): bool {
        return \json_validate($json, $depth, $flags);
    }
}
```

The colon / `enddeclare` form is the same kind of block for Tyhp statements.

## `#[\Tyhp\Php]`

`\Tyhp\Php` lives in `tyhp/core`. The constructor takes a string `$version`. Positional and named arguments are equivalent:

```tyhp
<?tyhp

#[\Tyhp\Php(">=8.4")]
function findFirst(array $array, callable $callback): mixed {
    return null;
}

#[\Tyhp\Php(version: ">=8.2 <8.4")]
function example(string $v): mixed {
    return $v;
}

#[\Tyhp\Php(version: ">=8.4")]
function example(string $v, bool $strict = false): string {
    return $v;
}
```

The attribute is legal on functions, classes, interfaces, traits, enums, and methods of classes, traits, and enums. It is **illegal** on `struct` and on Tyhp **and** tyhpdef `extension` declarations (**TYHP4304**). Wrap those with `declare(php=…)` instead — see [Structs and extensions](#structs-and-extensions).

In `.tyhp` source it is also illegal on a property, a class constant, an enum case, and an interface method (**TYHP4371**), because PHP cannot declare those conditionally. When one of them differs between PHP versions, declare the whole class, interface, or enum once per version inside `declare(php=…)` blocks. `.tyhpdef` members may still carry the attribute.

Missing or non-string `version` is **TYHP4305**. On a tyhpdef hooked property, put `#[\Tyhp\Php]` on the property, not on `get` or `set` (**TYHP8016**).

If the constraint does not match the target, the compiler omits the symbol (as if it were not declared).

## Constraint syntax

Gates use full Composer version-constraint syntax. Examples:

| Constraint | Matches |
|------------|---------|
| `">=8.4"` | 8.4 and later |
| `"<8.4"` | before 8.4 |
| `">=8.2 <8.4"` | 8.2 and 8.3 (space or comma means AND) |
| `"^8.2"` | `>=8.2.0 <9.0.0` |
| `"~8.2.3"` | `>=8.2.3 <8.3.0` |
| `"8.2.*"` | the 8.2 minor |
| `"8.2"` | same as `8.2.*` (bare minor = whole minor) |

`||` (or a single `|`) is OR; AND binds tighter. Tyhp treats a **bare** (or `=`) partial version as the **whole minor**. So `"8.2"` and `"=8.2"` in a gate mean `8.2.*` (`>=8.2.0 <8.3.0`), not “exactly 8.2.0”. Comparison operators still pad missing components with zeros the way Composer does: `">=8.2"` means `>=8.2.0`.

Invalid constraint strings are **TYHP4300**.

## Nesting is AND

A declaration must satisfy **every** active constraint around it. A `#[\Tyhp\Php(">=8.4")]` member inside `declare(php=">=8.3") { … }` is kept only when the target matches both.

If the outer gate is inactive, the whole inner region is inactive with it.

## Unreachable vs alternate variants

**TYHP4302** is only for a **nested** constraint that cannot overlap its enclosing constraint — the inner gate can never be true given the outer one. Example (outer `>=8.4` with inner `<8.3`):

```tyhp
<?tyhp

declare(php=">=8.4") {
    function outer(): void {}

    // ERROR TYHP4302 — unsatisfiable given the outer constraint
    declare(php="<8.3") {
        function never(): void {}
    }
}
```

Sibling blocks that cover different PHP versions are **alternate variants**, not unreachable code. They do not report TYHP4302:

```tyhp
<?tyhp

declare(php=">=8.4") {
    function example(): string {
        return '8.4+';
    }
}

declare(php="<8.4") {
    function example(): string {
        return 'pre-8.4';
    }
}
```

An inactive **file-level** `declare(php="…");` is also not TYHP4302 — the file is skipped silently.

## Same name, different versions

Two declarations of the same symbol are allowed when their **effective** constraints are pairwise **disjoint**. The compiler keeps the variant that matches `output.phpVersion` and emits it without a version check.

If the constraints **overlap** (both could match some PHP version, including the current target) **and** the declarations would also collide as ordinary overloads (same parameter-list shape), that is **TYHP4303**:

> Duplicate declaration of `{0}` with overlapping PHP version constraints

`#[\Tyhp\Php(">=8.3")] function foo()` together with `#[\Tyhp\Php(">=8.4")] function foo()` overlaps on 8.4+ and is an error. `">=8.4"` together with `"<8.4"` does not overlap. Distinct parameter lists under the same gate are overloads, not TYHP4303 — for example a no-argument `get_defined_functions()` beside a deprecated `get_defined_functions(bool $exclude_disabled)` in `declare(php=">=8.5")`. A static method and an instance method still cannot share a name, even with different parameter lists: that pairing is TYHP4303 under overlapping gates.

## What is emitted

`declare(php=…)` and `#[\Tyhp\Php]` are Tyhp-only, in the same family as `declare(output_file=…)`: the emitter never writes `declare(php=…)` (file or block), `#[\Tyhp\Php(…)]` (`\Tyhp\Php` is tagged `#[\Tyhp\NoEmit]`), or the `\Tyhp\Php` class itself. What replaces them depends on how the constraint relates to `output.phpVersion`, which is the oldest version the code runs on and has no upper limit:

| The constraint is true for… | Emitted |
|-----------------------------|---------|
| no version at or above `output.phpVersion` | nothing — the body is dropped |
| every version at or above `output.phpVersion` | the body, with no check |
| only some of those versions | the body inside an `if` over `\PHP_VERSION_ID` |

With `output.phpVersion` set to `"8.2"`:

```tyhp
<?tyhp

namespace App;

declare(php="<8.6") {
    function legacy(): string { return 'legacy'; }
}
```

```php
namespace App;

if (\PHP_VERSION_ID < 80600) {
    function legacy(): string
    {
        return 'legacy';
    }
}
```

The check applies to functions, classes, interfaces, traits, enums, and file-level `const`. A class lands in its own file with its own copy of the check, and functions land in the namespace's `_functions.php` after the ungated declarations. A `const` behind a check is written as `\define()` inside it, because PHP has no conditional `const`. Nested gates produce nested `if` blocks, outermost first.

A `declare(php=…)` or `declare(ext=…)` block inside a function body behaves the same way: its statements go inside an `if` when the gate needs a runtime check, and are emitted as plain statements when it does not.

```tyhp
function hasMbString(): bool {
    bool $found = false;
    declare(ext="mbstring") {
        $found = true;
    }
    return $found;
}
```

```php
function hasMbString(): bool
{
    $found = false;
    if (\extension_loaded('mbstring')) {
        $found = true;
    }
    return $found;
}
```

When the same function or type name is also declared under another version gate that `output.phpVersion` does not satisfy, only the declaration that matches `output.phpVersion` is compiled, and it is emitted without a check.

`.tyhpdef` gates are never written into PHP. They select which signatures the checker sees.

## Structs and extensions

Do not put `#[\Tyhp\Php]` on a `struct` or on a Tyhp or tyhpdef `extension { }` (**TYHP4304**). Gate those declarations with `declare(php=…)` instead.

```tyhp
<?tyhp
declare(php=">=8.4") {
    extension GatedStringOps extends string {
        function gated_tag(): string {
            return \strtoupper($this);
        }
    }
}
```

File-level `declare(php=">=8.4");` is also valid: it gates the rest of that file.

### Tyhpdef

`.tyhpdef` accepts the same file-level `;` and brace `{ }` declare forms. Use `#[\Tyhp\Php]` on classes, functions, and other legal attribute targets; wrap `struct` / `extension { }` in `declare(php=…)`.

```tyhp
<?tyhpdef

#[\Tyhp\Php(">=8.2 <8.4")]
function example(string $v): mixed;

#[\Tyhp\Php(">=8.4")]
function example(string $v, bool $strict = false): string;

declare(php=">=8.3") {
    function json_validate(string $json, int $depth = 512, int $flags = 0): bool;
}

declare(php=">=8.4") {
    extension GatedStringOps extends string {
        fn gated_tag(): string => \strtoupper($this);
    }
}
```

## Engine attributes and `output.phpVersion`

`#[\Tyhp\Php]` on a Core attribute class hides that class when the target is too low. Tyhp still recognizes several engine attributes **by name** and runs their checks:

| Attribute | Class visible | Checker |
|-----------|---------------|---------|
| `#[\Deprecated]` | 8.4+ | Use-site **TYHP4500** at every `output.phpVersion`. Literal `$message` is included in the warning. |
| `#[\Override]` | 8.3+ | Methods: **TYHP4129** when not overriding. Properties: legal at **8.5+**; below 8.5, **TYHP4127**. `__construct`: **TYHP4339** at every target. |
| `#[\NoDiscard]` | 8.5+ | Unused-return **TYHP4165** at every `output.phpVersion`. `(void)` suppresses. |
| `#[\DelayedTargetValidation]` | 8.5+ | At **8.5+**, skip **TYHP4127** for Core attributes on that declaration. Below 8.5 the skip is ignored. Functional checks (4129, 4165, 4339, 4500) still run. |

See [PHP Engine Attributes](tyhp_0330_phpEngineAttributes.md).

## Extension presence

`declare(ext="…")` keeps or drops a block according to whether an extension's tyhpdef package is loaded. The key must be alone in that `declare` (`TYHP8039`).

A loaded tyhpdef package provides extension `intl` when its `require` or `require-dev` contains `ext-intl`. `declare(ext="intl")` type-checks the block when some loaded package provides it. `declare(ext="!intl")` type-checks the block when none do, except inside a function body (see [Choosing an implementation at runtime](#choosing-an-implementation-at-runtime)). The value is the extension name, or `!` plus that name (`TYHP8040`). An `ext-intl` requirement on the application `composer.json` does not count unless that tyhpdef package is part of the compilation.

In `.tyhpdef` the gate only selects signatures. In `.tyhp` the matching block is also emitted inside a runtime check, because the PHP that runs the code may or may not have the extension:

```tyhp
<?tyhp

namespace App;

declare(php="<8.6") {
    declare(ext="!intl") {
        fallback function graphemeStrrev(string $string): string {
            return \implode('', \array_reverse(\str_split($string)));
        }
    }
}
```

```php
namespace App;

if (\PHP_VERSION_ID < 80600) {
    if (!\extension_loaded('intl')) {
        if (!\function_exists(__NAMESPACE__ . '\graphemeStrrev')) {
            function graphemeStrrev(string $string): string
            {
                return \implode('', \array_reverse(\str_split($string)));
            }
        }
    }
}
```

### Choosing an implementation at runtime

Inside a function body, `declare(ext="…")` is a runtime branch, so a chain of blocks can pick the best implementation the running PHP has. Here the negative gate `!name` always compiles, because a loaded tyhpdef package says nothing about the PHP that will run the code. A positive gate `name` still needs a loaded tyhpdef package for the extension, so its block can be type-checked.

`declare(ext="x") { … }` directly followed by `declare(ext="!x") { … }` is checked as `if … else …`: a variable that both blocks assign is definitely assigned afterwards.

```tyhp
private static function resolveBackend(): DecimalBackend {
    ?DecimalBackend $backend = null;
    declare(ext="decimal") {
        $backend = new PhpDecimalBackend();
    }
    declare(ext="!decimal") {
        declare(ext="bcmath") {
            $backend = new BcMathBackend();
        }
        declare(ext="!bcmath") {
            $backend = new IntegerScaledBackend();
        }
    }
    return $backend;
}
```

```php
private static function resolveBackend(): DecimalBackend
{
    $backend = null;
    if (\extension_loaded('decimal')) {
        $backend = new PhpDecimalBackend();
    } else {
        if (\extension_loaded('bcmath')) {
            $backend = new BcMathBackend();
        } else {
            $backend = new IntegerScaledBackend();
        }
    }
    return $backend;
}
```

Two adjacent blocks for opposite gates (`ext="x"` and `ext="!x"`, in either order) share one `if … else`. The blocks must be next to each other, and both must compile.

If a positive gate's tyhpdef package is not loaded, that block is dropped and the checker reports a possibly unassigned variable, because no code handles that extension.

Around declarations (functions, classes, constants) a `!name` gate follows the loaded packages instead: it is dropped when a loaded package provides the extension, so a fallback does not redeclare what the package already declares.

`fallback` in `.tyhp` marks a `function`, `class`, `interface`, `trait`, `enum`, or `const` declaration that is only declared when nothing has declared that name already. See [Declaration Gating](tyhp_0310_declarationGating.md#fallback-declarations).

```tyhp
<?tyhpdef

declare(ext="intl") {
    function grapheme_strlen(string $string): int|false|null;
}

declare(php="<8.6") {
    declare(ext="!intl") {
        fallback function grapheme_strrev(string $string): string|false;
        fallback const int GRAPHEME_EXTR_COUNT ?? 0;
    }
}
```

`fallback function` and `fallback const` still apply inside the block: they fill the name only when nothing else has declared it. See [Fallback functions](tyhpdef_functions.md#fallback-functions) and [Fallback constants](tyhpdef_variablesAndConstants.md#fallback-constants).

File-level `declare(ext="!intl");` gates the rest of that file the same way a file-level `declare(php=…);` does. A block that does not match is skipped. Nesting with `declare(php=…)` keeps a declaration only when both gates match.

## Diagnostics

| Code | Severity | When |
|------|----------|------|
| TYHP4300 | Error | Invalid Composer constraint string |
| TYHP4301 | Error | `php` mixed with other directives in the same `declare` |
| TYHP4302 | Error | Nested constraint unsatisfiable given the outer constraint |
| TYHP4303 | Error | Same name with overlapping version constraints, unless they are distinct same-staticness overloads |
| TYHP4304 | Error | `#[\Tyhp\Php]` on `struct` or `extension` (Tyhp or tyhpdef) |
| TYHP4305 | Error | Missing or non-string `version` argument |
| TYHP4306 | Warning | `output.phpVersion` unset; defaulted to `8.2` (once per compilation) |
| TYHP4371 | Error | `#[\Tyhp\Php]` on a property, class constant, enum case, or interface method in `.tyhp` source |
| TYHP8016 | Error | `#[\Tyhp\Php]` on a tyhpdef property hook (`get`/`set`); place it on the property or `declare(php=…)` |

See the [Diagnostic Code Reference](diagnostics_reference.md) for the compiler's short messages.

## Common mistakes

:::danger
Don't mix `php` with other declare directives in one statement. Use a separate `declare(php="…")`.
:::

:::danger
Don't put `#[\Tyhp\Php]` on `struct` or `extension`. That is TYHP4304; wrap those declarations in `declare(php=…) { }` instead.
:::

:::danger
Don't treat sibling version variants as unreachable. TYHP4302 is only for nested constraints that can never overlap the outer gate.
:::

:::danger
Don't expect `declare(php=…)` or `#[\Tyhp\Php]` to appear in the compiled PHP. They are replaced by a `\PHP_VERSION_ID` check, or by nothing, as described in [What is emitted](#what-is-emitted).
:::
