---
title: 'Emitted Docblocks'
---

The compiler writes PHPStan and Psalm docblock tags on the emitted PHP wherever the native declaration drops type information the checker has. A generic, an array shape, a `class-string`, or a callable signature stays visible to those tools and to an IDE that reads the same tags. The tags are on for every build profile (`debug`, `balanced`, and `release`). They do not depend on `output.comments`.

Tyhp does not run PHPStan or Psalm. Run those tools on the emitted PHP the same way you would on any other PHP project. The tags are there so the tools see the types Tyhp already checked.

## Configuration

Both keys live under `emit` in `tyhp.json`. An invalid value is warning **TYHP6003** (`ConfigInvalidValue`), and the key keeps its default.

:::member[emit.docblocks]
Type: `string` (default: `"lossy-only"`).

- `"lossy-only"` writes a tag only when it says more than the native PHP type. A parameter declared `int $x` does not get `@param int $x`. A parameter declared `array<int, User> $ids` is native `array` and gets `@param array<int, \App\User> $ids`.
- `"all"` writes a tag for every signature type, including types PHP already states.
- `"off"` writes no generated docblocks. That includes generated `@template` tags and the `@property` tags written for public property hooks that compile to magic accessors. An author docblock still follows `output.comments`.
:::

:::member[emit.docblockDialect]
Type: `string` (default: `"both"`). `"phpstan"`, `"psalm"`, `"both"`, or `"phpdoc"`. The value is parsed and validated. It does not change the emitted tags. Shared syntax is unprefixed. A `@phpstan-` or `@psalm-` prefix is used only where those dialects diverge, and no tag the compiler writes today needs one.
:::

```json
{
    "emit": {
        "docblocks": "lossy-only",
        "docblockDialect": "both"
    }
}
```

See [Project Options List](project_optionsList.md#emit-options) and [CLI: Build](cli_build.md).

## Tags

The generator writes a tag when the checker has the type:

| Tag | When |
| --- | --- |
| `@param` | A parameter whose docblock type is richer than the native hint. A variadic is `...$name`. |
| `@param-out` | A by-ref parameter, in addition to `@param`. |
| `@return` | A return type the native hint does not already state. |
| `@var` | A property or constant whose native type is lossier than the checked type. |
| `@template` | A type parameter. The tag is `@template-covariant` or `@template-contravariant` when that parameter's variance is covariant or contravariant. A bound is `of Type`. A default is `= Type`. |
| `@extends`, `@implements`, `@use` | A parent, interface, or trait reference. With `"lossy-only"`, the tag is written when that reference has type arguments. |
| `@internal` | A declaration marked `internal`. |
| `@property`, `@property-read`, `@property-write` | A public hooked property that is emitted as a magic accessor (PHP older than 8.4). |

`@throws` is not generated. An author `@throws` is kept, including every repeat.

```tyhp
<?tyhp

class Box<T> {
    public function get(T $value): T {
        return $value;
    }
}
```

The emitted class carries `@template T`. The method's native signature is `mixed`, and the docblock keeps the parameter:

```php
/**
 * @template T
 */
class Box
{
    /**
     * @param T $value
     * @return T
     */
    public function get(mixed $value): mixed
    {
        return $value;
    }
}
```

A generic class still carries `#[\Tyhp\GenericRuntime]` as well. See [Generics](tyhp_0500_generics.md).

## How types are spelled

Symbol names in a generated tag are fully qualified. A `use … as X` alias is expanded to the real name. `self`, `parent`, and `static` stay `self`, `parent`, and `static`.

`class-string` and `class-string<T>` are used for class, interface, and enum name brands (`__ClassName`, and the interface and enum equivalents). A trait name, a used-trait name, or a struct name is `string`. A function-name brand is `callable-string`.

A struct parameter is an array shape. A field is optional (`key?:`) when it has a default or is nullable. A nullable field is `key?: ?type`.

```tyhp
<?tyhp

type Money = struct {
    int $cents;
    string $currency = "USD";
    ?string $note;
};

function price(Money $money): int {
    return $money->cents;
}
```

```php
/**
 * @param array{cents: int, currency?: string, note?: ?string} $money
 */
function price(array $money): int
```

A callable is `callable(int): string`. A return of `string|null` is written `callable(int): ?string`. A union return is parenthesized, `callable(): (int|string)` and `callable(int): (string|int)`, so the `|` stays inside the callable. A callable that is itself nullable is `(callable(int): string)|null`, so the `|null` is not read as the return type.

```tyhp
<?tyhp

function apply(callable(int): string $fn): string {
    return $fn(1);
}

function callbacks(callable(int): string|null $a, callable(int): (string|int) $b): void {}
```

```php
/**
 * @param callable(int): string $fn
 */
function apply(callable $fn): string

/**
 * @param callable(int): ?string $a
 * @param callable(int): (string|int) $b
 */
function callbacks(callable $a, callable $b): void {}
```

## Author docblocks

An author docblock is merged with the generated tags.

- Summary prose stays above the tags.
- `@tyhp` emitter directives and `/@@ … @@/` signed blocks pass through in their original order.
- An author analysis tag wins per key. The generator fills the gaps. The author's wording is copied, including a description and a short name the author wrote.
- Order is prose, then directives, then the generated keys (an author tag that wins occupies that key's place, in signature order), then author tags that have no generated counterpart.

```tyhp
<?tyhp

namespace App\Users;

class User {}

/**
 * Loads users.
 *
 * @throws \RuntimeException when the store is down
 * @throws \LogicException when the ids are invalid
 * @param array<int, User> $ids the ids, never empty
 */
function load(array<int, User> $ids, array<string, User> $byName): void {}
```

```php
/**
 * Loads users.
 *
 * @param array<int, User> $ids the ids, never empty
 * @param array<string, \App\Users\User> $byName
 * @throws \RuntimeException when the store is down
 * @throws \LogicException when the ids are invalid
 */
function load(array $ids, array $byName): void {}
```

The author's `@param $ids` is kept as written. The generator adds `@param` for `$byName`, with the real class name. Both `@throws` tags are kept.

`output.comments: false` drops the summary prose and keeps directives, every author analysis tag (including repeated `@throws`), and the generated tags.

## PHP consumers

A PHP file, or a tool that never sees the `.tyhp` source, can rely on these tags for the types the native declaration lost: generic arguments, array shapes, `class-string`, and callable signatures. The native hints stay the types PHP itself can declare. `"lossy-only"` does not repeat a type the hint already states. `"off"` leaves only whatever the author wrote, subject to `output.comments`.

See [CLI: Interop Contract](cli_interopContract.md#emitted-docblocks).
