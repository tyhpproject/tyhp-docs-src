---
title: 'The internal Visibility Modifier'
status:
  tier: 2
  state: complete
---

`internal` is a Tyhp visibility keyword. Mark implementation details that belong in this project but must not appear in the published `package.tyhpdef`. Consumers of the compiled library type-check against that file, so they never see those symbols.

`internal` has no PHP equivalent. The compiler strips it on emit: class members become `public`; top-level classes, functions, and constants are unprefixed (PHP’s default). Same-project `.tyhp` can still use the symbols.

## Syntax

Apply `internal` to a top-level class, interface, trait, enum, function, constant, type alias, or extension, and to members (methods, properties, constants, enum cases).

```tyhp
<?tyhp

internal class GmpBackend {
    public function add(string $a, string $b): string {
        return \gmp_strval(\gmp_add($a, $b));
    }
}

internal function formatScale(int $scale): string {
    return (string)$scale;
}

internal const BACKEND_ID = 1;

public class Decimal {
    public function add(Decimal $other): Decimal {
        return $this->addWith(new GmpBackend(), $other);
    }

    internal function addWith(GmpBackend $backend, Decimal $other): Decimal {
        // ...
    }
}
```

Do not combine `internal` with `public`, `protected`, or `private` on the same declaration (`TYHP4002`). `internal static`, `internal readonly`, `internal abstract`, and `internal final` are allowed.

## Published tyhpdef

`tyhp build` for a library always writes `package.tyhpdef`. Symbols marked `internal` are omitted, the same way `private` members are omitted. A public type’s internal members are left out of that file.

```tyhp
<?tyhpdef
class Decimal {
    public function add(Decimal $other): Decimal;
}
```

`GmpBackend`, `formatScale`, `BACKEND_ID`, and `Decimal::addWith` do not appear. Consumers cannot name them through the published tyhpdef.

Use `internal` for backends, helpers, and other author-only code that must compile in this package but must not become part of the consumer API. Put author-only **tyhpdef packages** in `require-dev` and leave them out of `extra.tyhp.require` — see [Composer Runtime Packages](project_composerPackages.md#ambient-tyhpdefs-extratyhprequire).

## Compiled PHP

```php
<?php

class GmpBackend {
    public function add(string $a, string $b): string {
        return \gmp_strval(\gmp_add($a, $b));
    }
}

function formatScale(int $scale): string {
    return (string)$scale;
}

const BACKEND_ID = 1;

class Decimal {
    public function add(Decimal $other): Decimal {
        return $this->addWith(new GmpBackend(), $other);
    }

    public function addWith(GmpBackend $backend, Decimal $other): Decimal {
        // ...
    }
}
```

PHP does not enforce the project boundary. The published tyhpdef is what hides the names from Tyhp consumers.

## Best Practices

:::tip
DO mark helper classes, optional-extension backends, and shared constants `internal` when they exist only so this package can compile. They stay in the emitted PHP and stay usable inside the same `tyhp.json`.
:::

:::danger
DON'T combine `internal` with `public`, `protected`, or `private`. That is `TYHP4002`. Write `internal function helper(): void` (project-scoped) or `private function helper(): void` (class-scoped), not both.
:::

## Related

- [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#auto-generation-during-build) — `package.tyhpdef` omit
- [Composer Runtime Packages](project_composerPackages.md) — ambient vs author-only tyhpdefs
- [Diagnostic Code Reference](diagnostics_reference.md) — `TYHP4002`
