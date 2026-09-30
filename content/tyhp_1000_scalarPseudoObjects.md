---
title: 'Scalar Pseudo-Objects'
status:
  tier: 0
  story: '03'
  state: complete
---

Tyhp lets you call methods on scalar values (`string`, `int`, `float`, `bool`, `array`) and on `\Closure` using object syntax. The compiler rewrites `$value->method($args)` to a PHP expression or a static call. There is zero runtime overhead — no wrapper objects are created.

```status
tier: 2
story: '21'
state: complete
```

The `tyhp/core` package ships a built-in catalog of those methods (`length`, `contains`, `toUpper`, `mapped`, …) and activates them for the whole compilation with `global use extension \Tyhp\StringExtensions` (and the matching `ArrayExtensions`, `IntExtensions`, `FloatExtensions`, `BoolExtensions`, `ClosureExtensions`). You do **not** write `use extension` in each file.

```tyhp
<?tyhp

string $name = "Hello, World!";
int $len = $name->length();
bool $has = $name->contains("World");
string $upper = $name->toUpper();
string $trimmed = "  spaces  "->trim();

array<int, int> $nums = [3, 1, 4];
array<int, int> $evens = $nums->filtered(fn(int $v): bool => $v % 2 === 0);
array<int, string> $labels = $nums->mapped(fn(int $v): string => (string)$v);
int $n = 42->abs();
float $rounded = 3.14159->round(2);
```

`$name->length()` emits `\Tyhp\StringHelper::strlen($name)`. `$name->contains("World")` emits `\str_contains($name, "World")`.

## Unicode by default, `byte` prefix for bytes

String methods that measure or slice characters prefer the multibyte (`\mb_*`) APIs when `ext-mbstring` is loaded: `length()` is `\mb_strlen`, `toUpper()` is `\mb_strtoupper`, `substring()` is `\mb_substr`, and so on. Those calls go through `\Tyhp\StringHelper`, which caches the extension check and falls back to the matching byte API (`\strlen`, `\strtoupper`, `\substr`, …) when mbstring is not installed.

Byte-oriented variants use a `byte` prefix and the corresponding byte API: `byteLength()` is `\strlen`, `byteReverse()` is `\strrev`.

## Local `use` only when adapting

Because `tyhp/core` already issued `global use extension`, a file-level `use extension \Tyhp\StringExtensions;` with no adaptations is redundant and warns (`TYHP4169`). Use a local `use` only to **adapt** the catalog in that file (`hide`, method `as`, `insteadof`):

```tyhp
<?tyhp

use extension \Tyhp\StringExtensions {
    StringExtensions::toLower hide;
};

string $name = 'hello_world';
int $len = $name->length();
```

See [Use Statements](tyhp_0350_useStatements.md#local-use-overlaying-global-use).

## How to Write an Extension

Declare an `extension` with the target on the header (`extends string`) or in a nested `extends` group. `$this` is that target and is not a caller parameter. Same-file extensions are in scope without an import. Extensions from another file or namespace need `use extension` unless a loaded tyhpdef used `global use extension` for that name.

```tyhp
<?tyhp

extension StringHelpers extends string {
    function toCamelCase(): string {
        return $this;
    }

    function trimLower(): string {
        return \strtolower(\trim($this));
    }
}

string $name = 'hello_world';
string $camel = $name->toCamelCase();
```

Compiles to:

```php
<?php
declare(strict_types=1);

$name = 'hello_world';
$camel = \StringHelpers::toCamelCase($name);
```

When the extension lives in another file or namespace, import it with `use extension`:

```tyhp
<?tyhp

use extension App\Extensions\StringHelpers;

string $name = 'hello_world';
string $camel = $name->toCamelCase();
```

See Use Statements for adaptation syntax (`as` / hide) on `use extension`.

## Method Chaining (User Extensions)

If your extensions return the extended type (or another type that also has extensions in scope), you can chain calls. Each call is rewritten independently.

```tyhp
<?tyhp

extension StringHelpers extends string {
    function trimmed(): string {
        return \trim($this);
    }

    function lower(): string {
        return \strtolower($this);
    }

    function dashed(): string {
        return \str_replace(' ', '-', $this);
    }
}

string $input = "  Hello World  ";
$result = $input->trimmed()->lower()->dashed();
```

```php
<?php

$input = "  Hello World  ";
$result = \StringHelpers::dashed(\StringHelpers::lower(\StringHelpers::trimmed($input)));
```

The built-in catalog chains the same way: `"  Hello  "->trim()->toLower()`.

## Calling on Literal Values

Extension methods can be called on literals. Wrap integer and float literals in parentheses.

```tyhp
<?tyhp

$char = (65)->toHex();
$parts = "a,b,c"->split(",");
```

## Best Practices

:::tip
Prefer the `tyhp/core` catalog (`$name->toUpper()`, `$nums->mapped(...)`) when a method exists. Write a small user `extension` when you need a project-specific helper, and import it with `use extension` in each file that needs it.
:::

:::tip
Put the scalar on the extension (`extends string`, `extends array`, …) so call sites read as instance methods while emit stays a static call or a spliced expression.
:::

## Common Mistakes

:::danger
Don't add `use extension \Tyhp\StringExtensions;` with no adaptations. The catalog is already globally imported; that local `use` warns `TYHP4169`.
:::

:::danger
Don't expect actual object instances — these are compile-time rewrites. Calling a method that is not an in-scope extension produces a compile error.
:::

:::danger
Don't import an extension class with a plain `use` and expect methods to attach. Use `use extension` to activate extension methods on the target type (same-file extensions and `tyhp/core` globals are already in scope).
:::

:::danger
Don't try to assign scalar methods to variables — `$fn = $name->trim` is not valid. These are method calls, not callable properties.
:::
