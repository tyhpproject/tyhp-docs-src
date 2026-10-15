---
title: 'Extensions in Tyhpdef'
status:
  tier: 0
  story: '03'
  state: complete
---

Tyhpdef can attach Tyhp extension methods and operator overloads to PHP types you do not own. That lets Tyhp callers write `$money->formatCurrency()` or `$a + $b` while the compiler rewrites those sites to the underlying PHP.

Tyhpdef offers three forms:

1. **Standalone `extension Name { }`** — compile-time `fn` / `operator` mappings that replace call sites with `=>` expressions
2. **Thin mappings** on a tyhpdef class — `extension fn` and `extension operator` with a `=>` expression; fully erased
3. **`use extension`** on a tyhpdef class — attach a standalone extension so callers of **that type** do not need their own import

`use extension` at file level is **opt-in**. Loading a package does **not** auto-activate its standalone `extension { }` blocks unless that tyhpdef contains `global use extension …`. `tyhp/core` does this for `\Tyhp\StringExtensions` and the other scalar catalogs, so those methods are compilation-wide. Class-body `use extension` on a type still auto-activates that type’s attached surface for consumers (minus hidden members).

For the Tyhp-side `extension { }` syntax, `use extension` in `.tyhp` files, generated PHP backer classes, `hide` / `insteadof`, and emit details, see [Extensions](tyhp_2100_extensions.md).

## Standalone `extension Name { }`

A standalone extension in a `.tyhpdef` file is a compile-time mapping from Tyhp method or operator syntax to a PHP expression. Without `#[\Tyhp\GenericRuntime]`, the compiler replaces every call site with the member's `=>` expression. A compiled Tyhp library stamps `GenericRuntime` on emitted generic mappings (`binder` only when the companion exists). Foreign consumer sites use `\Tyhp\Generic::bind` instead of splicing a wrapper that drops the type argument.

When the extension is active and the member has no `#[\Tyhp\GenericRuntime(binder: …)]`, the compiler replaces every call site with the member's `=>` expression and substitutes the receiver and arguments into that expression. For example:

```tyhp
<?tyhpdef

extension StringExtensions extends string {
    fn toUpper(): string => \strtoupper($this);
}
```

With `StringExtensions` in scope, this Tyhp call:

```tyhp
use extension StringExtensions;

string $upper = $name->toUpper();
```

is emitted as:

```php
$upper = (\strtoupper($name));
```

PHP cannot call an erased member — there is no method on a PHP class to invoke. Only Tyhp call sites, after splicing, remain.

Because the declaration has no runtime representation, each member must be a single expression:

- Functions use `fn`, a required return type, and `=> expression;`.
- Operators use `operator`, a required return type, and `=> expression;`.
- Call-site splicing is intrinsic, so `#[\Tyhp\Optimize\Inline]` on an extension member is an error (`TYHP4176`).

The header and nested groups are the same as in Tyhp. A header `extends Type` covers every member. Nested `extends Type { }` / `extends<T> Type { }` groups each name their own target, and the extension then has no header target. Members are short `fn` / `operator` with `=>`. `$this` is the block target and is not a parameter. `&$this` is the by-reference receiver annotation. `self` is that same target, including a scalar (`extends int` is `int`). Type parameters on `extension Name<T>` or `extends<T>` live on that symbol and are in scope for the block; they are not copied onto each method. A method lists only the type parameters written on it.

Writing `extends Type $this` or `operator op<Type>` on a member is `TYHP4361`. `use extension` adaptations still qualify an operator with `operator +<Money>`.

Mappings may delegate to declared PHP methods as well as builtins:

```tyhp
<?tyhpdef

class StringOperators as StringOperators__tyhpExtensionBacker {
    public static function __multiply<T extends string|array>(T $left, int $right): T;
}

extension StringOperators extends string {
    operator * (self $left, int $right): string
        => StringOperators__tyhpExtensionBacker::__multiply($left, $right);
}
```

Here `StringOperators__tyhpExtensionBacker` is the Tyhp name for the declared PHP backer. The compiler rewrites it to `StringOperators` in emitted PHP while splicing the mapping expression into each operator call site.

Package authors put multi-statement bodies in `tyhp_src/` and describe the emitted PHP class with `class PhpName as Name__tyhpExtensionBacker`. Short `=>` members that map onto builtins need no backer. `tyhp/core` follows this split: its scalar extensions are Tyhp source files in `tyhp_src/` (`StringExtensions.tyhp`, `ArrayExtensions.tyhp`, `IntExtensions.tyhp`, `FloatExtensions.tyhp`, `BoolExtensions.tyhp`, `ClosureExtensions.tyhp`), each declaring `global use extension`, and the generated `package.tyhpdef` publishes the mappings. Brace-body helpers such as `StringExtensions::reverse` stay as static calls into the compiled backer class.

An extension must contain at least one member; an empty block reports `TYHP4172`. Declaring the same extension name more than once in the base and included tyhpdefs is also an error. `deprecated` and `obsolete` are allowed on the extension and its members.

A parameter the mapping writes must be declared `&`, and only those parameters are by reference. See [By-reference parameters](tyhp_2100_extensions.md#by-reference-parameters) on the Tyhp extensions page.

## Thin mappings on a tyhpdef class

Inside a tyhpdef class body you can declare `extension fn` and `extension operator` members. Each is a **thin mapping**: a single `=>` expression that the compiler splices into every Tyhp call site. The compiler treats them as a synthetic extension for that class. These members are **auto-active**: Tyhp code that uses the type does not need a separate `use extension` import.

`extension` replaces a visibility modifier — members are always public. `abstract` and `final` are not allowed. `$this` in an `extension fn` and `self` in an inline `extension operator` resolve to the enclosing tyhpdef class.

A thin mapping is fully erased. The `.tyhpdef` file is never emitted as PHP, and the member does not become a PHP method. PHP cannot call it.

```tyhp
<?tyhpdef

class Money {
    public function plus(Money $other): Money;
    public function isEqualTo(Money $other): bool;
    public function __toString(): string;

    extension fn formatCurrency(string $locale = 'en_US'): string
        => $locale . ' ' . $this->__toString();

    extension fn shortLabel(): string => $this->formatCurrency();

    extension operator +(self $left, self $right): self => $left->plus($right);

    extension operator ==(self $left, self $right): bool => $left->isEqualTo($right);
}
```

Tyhp callers then write:

```tyhp
<?tyhp

Money $total = $a + $b;
string $label = $total->formatCurrency();
```

The compiler splices the mapping expressions into those sites. For example `$a + $b` becomes `($a->plus($b))`, and `$name->toUpper()` with `extension fn toUpper(): string => \strtoupper($this);` becomes `(\strtoupper($name))`.

`$this` in an `extension fn` and `self` in an `extension operator` are the enclosing tyhpdef class. The member lists the parameters callers pass.

The same by-reference rules as Tyhp `extension { }` apply: a parameter the expression writes must be declared `&`, and only those parameters are by reference. See [By-reference parameters](tyhp_2100_extensions.md#by-reference-parameters).

## Native vs Mapped Operators

Tyhpdef has two operator members. Mixing them up is a common source of `TYHP8013`.

| Form | Meaning | Emitter |
|------|---------|---------|
| `operator +(…): T;` (no `extension`) | Native PHP operator — the type already supports it | **No rewrite** — leave `$a + $b` |
| `extension operator +(…): T => …;` | Thin mapping onto an expression | Splice the `=>` expression |
| `extension operator +(…): T;` (bodyless) | **Illegal** | Diagnostic `TYHP8013` |

Bare `operator` is documented in [Classes in Tyhpdef](tyhpdef_classes.md#operators). The rest of this section is the mapped form.

`DateTimeInterface` comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`, `<=>`) are native. `DateTime` and `DateTimeImmutable` `+` / `-` map onto `add` / `sub` / `diff`.

```tyhp
<?tyhpdef

class Money {
    public function plus(Money $other): Money;

    extension operator +(self $left, self $right): self => $left->plus($right);
}
```

Unary and conversion overloads use the same mapped form. A single-parameter `extension operator` is unary; `extension operator convert` maps conversions:

```tyhp
<?tyhpdef

namespace Tyhp;

final class Decimal {
    extension operator +(self $value): float => \Tyhp\Decimal::__asNumeric($value);

    extension operator convert(int $value): self => \Tyhp\Decimal::__from($value);

    extension operator convert(self $value): string => $value->__toString();
}
```

## use extension in Tyhpdef Class Bodies

`use extension` on a tyhpdef class is the extension analogue of `use SomeTrait;` in a Tyhp or PHP class: it attaches an existing standalone `extension { }` to this type. Matching methods become part of the type's surface. Callers that use the type do **not** need their own `use extension`.

The import supports the same adaptation syntax as traits, plus postfix `hide` and operator `insteadof`. `as` on operators is an error (`TYHP4170`). See [Operator overloads](tyhp_1600_operatorOverloads.md#hiding-and-preferring-extension-operators).

```tyhp
<?tyhpdef

class Money {
    public function plus(Money $other): Money;
    public function format(): string;

    use extension MoneyFormatting {
        MoneyFormatting::format as formatExtended;
        operator + hide;
    };
}
```

Only methods whose first parameter `extends` this class are attached. A method in the same extension that `extends` a different type is skipped for this class — it is not an error. If nothing in the extension targets the enclosing class, the `use` adds no methods (a no-op for this type, unless the name itself is missing).

The referenced extension must resolve to a real `extension Name { … }` (Tyhp source or tyhpdef). If the name does not resolve to an extension, the compiler reports `TYHP8011`.

File-level `use extension` is also valid in tyhpdef (same syntax as Tyhp) when the tyhpdef file needs the extension name in scope. That form is opt-in unless the file (or another loaded tyhpdef) uses `global use extension`.

## PHP version gating

`#[\Tyhp\Php]` is **illegal** on a standalone tyhpdef `extension { }` (**TYHP4304**), the same as on Tyhp `extension { }`. Wrap the extension in `declare(php=…)` instead — file-level `declare(php="…");` and brace `declare(php="…") { … }` both parse in `.tyhpdef`. See [PHP Version Gating](tyhp_0320_phpVersionGating.md#structs-and-extensions).

`extension fn` / `extension operator` members inside a tyhpdef **class** body are not affected by this restriction — `#[\Tyhp\Php]` on the enclosing class or on ordinary methods works normally; the restriction is on the `extension { }` declaration itself.

## Access and Conflicts

Thin mapping members can only use the **public** API of the enclosing type. They cannot access private or protected members — extensions are external to the class.

An inline extension member must not collide with a member already declared on the same class (`TYHP8010`).

A user type whose Tyhp name ends with `__tyhpExtensionBacker` collides with the reserved backer suffix (`TYHP4171`).

## Best Practices

:::tip
DO use standalone tyhpdef `extension Name { }` with short `=>` mappings when describing a compiled Tyhp extension (or a hand mapping onto builtins). Keep `$this` / `self` as the target type.
:::

:::tip
DO use a class-body `extension operator … => …;` when a PHP type has methods such as `plus()` / `isEqualTo()` and you want Tyhp to accept `$a + $b`. Keep the expression a thin mapping onto those methods.
:::

:::tip
DO use bodyless `operator …;` (no `extension`) when the PHP type already implements the operator natively (engine magic, PECL, `DateTime` comparison).
:::

:::tip
DO use `use extension` on a tyhpdef class to auto-activate a shared extension for every consumer of that type.
:::

:::tip
DO keep mapping expressions small. They exist so the consumer compiler can splice call sites; they are not a place to reimplement the PHP library.
:::

## Common Mistakes

:::danger
DON'T write a bodyless `extension operator +(…): T;`. That is `TYHP8013`. Use bodyless `operator` for native ops, or give `extension operator` a thin `=>` expression.
:::

:::danger
DON'T put the target on a class-body `extension fn` or `extension operator`. Those members use the enclosing class. A standalone `extension Name { }` puts the target on the header or in a nested `extends` group.
:::

:::danger
DON'T mix a header `extends` with nested `extends` groups (`TYHP4362`), and don't leave a member outside a group when the extension uses groups (`TYHP4363`). Writing `extends Type $this` or `operator op<Type>` on a member is `TYHP4361`.
:::

:::danger
DON'T omit return types on tyhpdef `extension` members. Short `fn` / `operator` + `=>` only. Empty `{}` is `TYHP4172`.
:::

:::danger
DON'T use `abstract` or `final` on `extension fn` or `extension operator`.
:::

:::danger
DON'T write `function name(...): T => expr;` for a short body. Standalone extension members and class-body thin mappings use `fn` (or `extension fn`); tyhpdef class, enum, and trait methods that declare PHP signatures use `function name(...): T;`.
:::

:::danger
DON'T put `#[\Tyhp\Optimize\Inline]` on a tyhpdef extension member. Splicing is decided by the member's form (`TYHP4176`).
:::

```tyhp
<?tyhpdef

class Money {
    public function plus(Money $other): Money;

    // ERROR TYHP8013: mapped overload missing a => expression
    // extension operator +(self $left, self $right): self;

    // OK: native passthrough
    // operator +(self $left, self $right): self;

    // OK: thin mapping
    extension operator +(self $left, self $right): self => $left->plus($right);
}
```

## Compiler Errors

- `TYHP4170` — `as` on an operator in a `use extension` adaptation; use `hide` or `insteadof`
- `TYHP4171` — type name collides with the reserved `__tyhpExtensionBacker` suffix
- `TYHP4172` — empty `extension Name {}`
- `TYHP4173` — `hide` of a member that extension does not declare
- `TYHP4174` — a spliced member writes a parameter not declared `&`, declares `&` on a parameter it does not write, or mutates `$this` without `&`
- `TYHP4175` — a spliced member reduces to itself, directly or through other spliced members
- `TYHP4176` — `#[\Tyhp\Optimize\Inline]` on an extension member
- `TYHP4177` — a variable name collides with the generated inline temporary prefix
- `TYHP4180` — argument for a `&` parameter is not something PHP can reference
- `TYHP4181` — an erased member's call site cannot be spliced faithfully (no PHP method to fall back to)
- `TYHP8010` — an inline extension member conflicts with a declared member on the same class
- `TYHP8011` — a `use extension` reference in tyhpdef does not resolve to an extension declaration
- `TYHP8012` — a member marked `extension` is not a valid extension member (`fn` / `operator` only)
- `TYHP8013` — `extension operator` is missing a thin `=>` expression; use bodyless `operator` for native PHP operators

## Summary

- Tyhpdef **can** declare standalone `extension Name extends Type { }` or nested `extends Type { }` groups. Members are short `fn` / `operator` + `=>`; `$this` is the block target; return types required; empty `{}` is an error
- Class-body members are **thin mappings** (`extension fn` / `extension operator` + `=>`). They erase completely; PHP cannot call them. `$name->toUpper()` with `=> \strtoupper($this)` emits `(\strtoupper($name))`
- `$this` / `self` in standalone members refer to the **target**; in class-body mappings they refer to the enclosing tyhpdef class
- Bodyless `operator …;` means native PHP passthrough; `extension operator` always needs a `=>` expression
- File-level `use extension` is opt-in unless `global use extension`; class-body `use extension` auto-activates that type’s attached surface (minus `hide`)
- `tyhp/core` declares its scalar extensions in `tyhp_src/<ScalarType>Extensions.tyhp` with `global use extension`, and its generated `package.tyhpdef` maps them to backer classes (`class PhpName as Name__tyhpExtensionBacker`) for multi-statement bodies
