---
title: Extensions
status:
  tier: 0
  story: '03'
  state: complete
---

Extensions in Tyhp allow you to add new methods and operator overloads to existing types without modifying their source code. This is useful for adding functionality to classes you don't own, imported PHP types, or even scalar types like string, int, and array. The compiler always rewrites Tyhp call sites. A member's form decides whether PHP also keeps a method on the extension class.

## Declaring an Extension

The target is written once on the extension. `$this` inside each member is that target. Callers do not pass `$this`; call sites look like instance methods (`$text->toCamelCase()`). Member names follow PHP method naming, so names such as `match`, `and`, and `or` are allowed.

A header target applies to every member:

```tyhp
<?tyhp

extension StringExtensions extends string {
    function toCamelCase(): string {
        $parts = \explode('_', $this);
        return \lcfirst(\implode('', \array_map('\ucfirst', $parts)));
    }

    function toSnakeCase(): string {
        return \strtolower(\preg_replace('/[A-Z]/', '_$0', $this));
    }

    function truncate(int $maxLength, string $suffix = '...'): string {
        if (\strlen($this) <= $maxLength) {
            return $this;
        }
        return \substr($this, 0, $maxLength - \strlen($suffix)) . $suffix;
    }
}

// Using extension methods — called as if they were instance methods
string $text = 'hello_world';
echo $text->toCamelCase();   // outputs: helloWorld
echo $text->toSnakeCase();   // outputs: hello_world
```

A mixed extension omits the header target. Each nested group names its own type. Groups are one level: a group contains members, not further groups. A header `extends` together with a nested group is `TYHP4362`. A member beside those groups, outside any group, is `TYHP4363`. Members with no target at all are `TYHP4147`. An empty extension is `TYHP4172`.

```tyhp
<?tyhp

extension NumericHelpers {
    extends int {
        fn abs(): int => \abs($this);
    }

    extends float {
        fn abs(): float => \abs($this);
    }

    extends<T> \App\MyClass<T> {
        function id(): T { return $this->id; }
    }

    extends<TRight> \App\Pair<string, TRight> {
        function right(): TRight { return $this->right; }
    }
}
```

Generics on the extension name are the same kind of binder as `extends<T>` on a group:

```tyhp
<?tyhp

extension MyClassOps<T> extends \App\MyClass<T> {
    function id(): T { return $this->id; }
}

extension Ops<T extends int|string> extends \App\MyClass<T> {
    function id(): T { return $this->id; }
}
```

The `extends` inside `<T extends int|string>` is the type-parameter constraint. The `extends` after the name, or the `extends` that opens a group, is the target.

Those type parameters live on the extension symbol, or on the group for `extends<T>`. They are in scope for the target and for the members in that block. A call binds them only when the receiver matches the whole target, so `Pair<string, int>->right()` is `int` and `Pair<int, int>->right()` stays `TRight`. They are not copied onto each method. A method's type parameters are only the ones written on that method (`function mapTo<R>(callable(T): R $fn): array<R>`). Reusing an in-scope name on the method is `TYHP4366`. A type parameter that is never referenced is `TYHP4365`.

Writing the target on the member (`extends Type $this`, or `<Type>` after the operator token) is `TYHP4361`. Adaptation clauses in `use extension` still qualify an operator by target: `E::operator +<Money> hide`.

## The target

A target is one class, interface, enum, type alias, builtin, or generic application, including `object`, `callable`, and `struct`. `?T` applies to a receiver of type `T` and of type `?T`. Inside the member, `$this` is `?T`; a use as `T` needs a null check (`!== null` narrows it).

A union is a legal target when every member of the union is itself a legal target. The member applies when every type the receiver might be is a member of that union. `$this` in the member is the whole union. `extends string|int` applies to `string`, to `int`, and to `string|int`. It does not apply to `string|int|bool` or to `?string`. A union that includes `null` applies to every non-empty combination of its members (so `extends null|string` applies to `string` and to `?string`) and does not apply to a receiver that is only `null`.

`TYHP4364` reports an intersection, `void`, `never`, `mixed`, a type parameter, an `object { … }` shape, `_`, or a union that contains one of those. An alias is read through to its body: an alias of a legal union is a legal target.

Two groups in the same extension that can both apply to one receiver and declare the same method or the same operator are `TYHP4367`. `extends string` and `extends string|int` both apply to `string`, so the same member on both is an overlap. Different member names on overlapping targets are fine. Targets that do not overlap, such as `Money` and `\DateTime`, may share a method name. The same member on two separate extensions is an activation conflict (`hide` / `insteadof` on `use extension`), not `TYHP4367`.

A target that does not resolve to a class or built-in is `TYHP3016`. When that block declares an operator and the target is `void`, `never`, `null`, `mixed`, `resource`, `true`, or `false`, the diagnostic is `TYHP3025`.

## `$this`

`$this` is the block target. It is not a source parameter and it is not a named argument. `&$this`, with no type written on it, marks the member by-reference. Use it when the body writes `$this`: assignment, compound assignment, `++` / `--`, or passing `$this` to a by-reference parameter. Writing `$this` without `&$this` is `TYHP4369`. Declaring `&$this` when the body never writes `$this` is `TYHP4370`.

Calling a method on an object `$this`, or assigning one of its properties (`$this->amount = 1`), does not write `$this`. The handle is shared, so the caller sees the mutation without `&`. On a scalar, `array`, or struct target, assigning through `$this` does write it (`$this->field = …`, `$this[$k] = …`, `$this[] = …`), because those values are copied into the parameter.

The PHP parameter is `$this_`. It is `&$this_` only when the member is annotated `&$this`. A by-value member emits `$this_` with no `&`, including when the target is a class, interface, or enum. A by-reference call needs a referenceable receiver (`TYHP4180`); a literal such as `'hello'->sort()` is not one.

```tyhp
<?tyhp

extension IntOps extends int {
    function label(): string { return (string)$this; }

    function bump(&$this): void { $this = $this + 1; }
}
```

## `self`

`self`, `new self()`, and `self::` inside a member are the block target, including a scalar. `extends int` emits `int` (for example `int::class` and a return type of `int`), not the extension class. Name the extension class by writing its name (`MoneyOps`). `static::` and `parent::` in an extension member are `TYHP4368`. An anonymous class nested in the member keeps its own `self` and `static`.

Hover on the extension name shows `extension Name extends Target`, with generics on the name when they were written there (`extension StringOps<T> extends string`). A header with no target shows `extension Name`. Hover on a nested group shows `extends Target` or `extends<T> Target`. A method signature lists the parameters you wrote; `$this` is not one of them.

## Member forms

A Tyhp `extension { }` member has three forms. The form is the contract for what PHP keeps:

| Form | PHP backer method | Tyhp call sites |
|------|-------------------|-----------------|
| Short `fn … => expr;` | **Omitted** — Tyhp-only | Splice `expr` |
| Brace body with a single `return expr;` | **Emitted** — PHP can call it on the backer | Splice `expr` |
| Brace body with multiple statements | **Emitted** | Call the backer method |

Choose a form by what you need:

| Goal | Write |
|------|-------|
| Tyhp-only, no PHP method | `fn … => expr;` |
| Spliced in Tyhp **and** callable from PHP | `function … { return expr; }` |
| Multi-statement logic | `function … { … }` — a real PHP method that Tyhp calls |

The single-`return` brace body is also the way to keep a PHP method when a call site cannot be spliced faithfully. A short `=>` member is erased, so that situation is error `TYHP4181`. The brace form emits a method the call site can fall back to.

A parameter the member writes must be declared `&`, and only those parameters are by reference. See [By-reference parameters](#by-reference-parameters).

Members may carry attributes, the same way class methods and tyhpdef extension members do:

```tyhp
<?tyhp

extension ArrayHelpers extends array {
    #[\Tyhp\Optimize\Pure]
    function sorted(): array {
        array $copy = \array_values($this);
        \sort($copy);
        return $copy;
    }
}
```

`#[\Tyhp\Optimize\Inline]` is still an error (`TYHP4176`). Form decides splicing.

## Compiled PHP Output

Multi-statement members compile to static methods on the extension class. The object the method is called on becomes the first argument. Short `=>` members are spliced into the call site and do not appear on the class. A single-`return` brace member is spliced in Tyhp and still emitted as a PHP method.

```tyhp
<?tyhp

extension StringHelpers extends string {
    function complexStringProcess(): string {
        string $finalString = \trim($this);
        return $finalString;
    }

    fn shortProcess(): string => ' ' . $this;

    function simpleProcess(): string {
        return $this . ' ';
    }
}

string $a = $name->shortProcess();
string $b = $name->simpleProcess();
string $c = $name->complexStringProcess();
```

```php
<?php

class StringHelpers
{
    public static function complexStringProcess(string $this_): string
    {
        $finalString = \trim($this_);
        return $finalString;
    }

    public static function simpleProcess(string $this_): string
    {
        return $this_ . ' ';
    }
}

$a = (' ' . $name);
$b = ($name . ' ');
$c = StringHelpers::complexStringProcess($name);
```

`shortProcess` has no PHP method — PHP cannot call it. `simpleProcess` does, even though Tyhp splices the expression instead of calling it.

If every member is short `=>`, the compiler emits no PHP backer class.

The earlier `StringExtensions` example uses multi-statement members, so every call becomes a static method call:

```php
$text = 'hello_world';
echo StringExtensions::toCamelCase($text);
echo StringExtensions::toSnakeCase($text);
```

## By-reference parameters

A spliced member substitutes the caller's argument where the parameter stood, which behaves like passing by reference. Three rules keep that identical to a real call.

**A written parameter must be declared `&`, and only those parameters are.** If the expression assigns to a parameter, compound-assigns, increments or decrements it in either position (`++$v` or `$v++`), or passes it to a callee's `&` parameter, that parameter must be declared `&`. Declaring `&` on a parameter the expression never writes is equally an error (`TYHP4174`). The receiver uses the `&$this` annotation from [Declaring an Extension](#this): `$a->sort()` with `function sort(&$this)` can splice to `\sort($a, …)`. Writing `$this` without that annotation is `TYHP4369`.

`++` counts as a write in either position. A non-mutating increment is written `$v + 1`.

**An argument for a `&` parameter must be something PHP can reference** (`TYHP4180`). The receiver of a member annotated `&$this` is that argument. These shapes are not:

- literals
- constants
- call results
- `readonly` properties
- properties whose read path is by value: a tyhpdef `{ get; }` hook, `__get`, or `offsetGet`

A tyhpdef `{ &get; }` is referenceable, as are `&__get` and `&offsetGet`.

**A receiver or argument used more than once is evaluated once.** When the receiver or an argument is more than a simple variable or literal and the member reads its parameter more than once (reads behind `&&`, `||`, `??`, or a conditional arm count), the compiler assigns the value to a local at the first read that always runs and reuses it. So `$n->doubled()` with `fn doubled(): int => $this + $this` does not evaluate the receiver twice.

If a read behind a short circuit comes before the first read that always runs, the value cannot be evaluated exactly once at the call site, so the call is not spliced. A member that emits a PHP method is called as a normal method call. An erased member (a short `=>` member) has no method to fall back to and reports `TYHP4181`.

```tyhp
<?tyhp

extension Counters extends int {
    fn bump(&$this): int => ++$this;
}
```

## Extensions on Class Types

Extensions can add methods to any class type, including third-party classes you don't own.

```tyhp
<?tyhp

extension DateTimeExtensions extends \DateTime {
    function isWeekend(): bool {
        $day = (int)$this->format('N');
        return $day >= 6;
    }

    function isBusinessHours(): bool {
        $hour = (int)$this->format('G');
        return $hour >= 9 && $hour < 17 && !$this->isWeekend();
    }
}

$now = new \DateTime();
if ($now->isBusinessHours()) {
    echo 'Office is open';
}
```

```php
<?php

$now = new \DateTime();
if (DateTimeExtensions::isBusinessHours($now)) {
    echo 'Office is open';
}
```

## Generic Extensions

Put the target's type parameters on the extension or on the group. Add further type parameters on the method when that method needs them. Header and group parameters stay on that symbol; the method lists only its own.

```tyhp
<?tyhp

extension IterableExtensions<T> extends iterable<T> {
    function firstOrNull(callable(T): bool $predicate): ?T {
        foreach ($this as $item) {
            if ($predicate($item)) {
                return $item;
            }
        }
        return null;
    }
}

extension ArrayExtensions<T extends int|float> extends array<T> {
    function max(): T {
        if (empty($this)) {
            throw new \RuntimeException('Array is empty');
        }
        return \max($this);
    }

    function mapTo<R>(callable(T): R $fn): array<R> {
        return \array_map($fn, $this);
    }
}

array<int> $numbers = [1, 2, 3];
echo $numbers->max();  // outputs: 3

array<string> $upper = $numbers->mapTo(fn(int $n): string => (string)$n);
```

```php
<?php

$numbers = [1, 2, 3];
echo ArrayExtensions::max($numbers);

$upper = ArrayExtensions::mapTo($numbers, fn(int $n): string => (string)$n);
```

## Extension Operator Overloads

Operators list every operand. `self` in the signature is the block target. `abstract` and `final` are not allowed on extension operators, nor on tyhpdef `extension fn` or `extension operator` members.

```tyhp
<?tyhp

extension StringOperators extends string {
    operator * (self $left, int $right): string
    {
        return \str_repeat($left, $right);
    }
}

string $line = '-' * 40;  // 40 dashes via StringOperators
```

## Extension Operators on Class Types

`self` in the parameter list is the header or group target. An operand of another type is written as that type, so `int + Money` is `operator + (int $left, self $right)`.

```tyhp
<?tyhp

extension MoneyOperators extends Money {
    operator + (self $left, self $right): self {
        return $left->plus($right);
    }

    operator == (self $left, self $right): bool {
        return $left->isEqualTo($right);
    }
}
```

## Generated library tyhpdef

When `tyhp build` emits a library’s public API, a standalone Tyhp `extension StringHelpers { … }` becomes tyhpdef pieces that follow the member's form:

1. A PHP backer class aliased with the reserved suffix, listing **only** members that have a PHP method: `class StringHelpers as StringHelpers__tyhpExtensionBacker`
2. A tyhpdef `extension StringHelpers { … }` whose members are thin `fn` / `operator` mappings

The mapping copies the expression for a short `=>` member and for a single-`return` brace member. A multi-statement member maps onto the backer (`=> StringHelpers__tyhpExtensionBacker::complexStringProcess($this)`). An all-`=>` extension gets no backer stub class at all.

The suffix `__tyhpExtensionBacker` is Tyhp-only; it never appears in emitted PHP. A user type with that Tyhp name is `TYHP4171`.

`tyhp/core` uses the same pattern for multi-statement scalar methods: Tyhp bodies live in `tyhp_src/` (compiled as package source, not listed in `include`), and the tyhpdef declares `class StringExtensions as StringExtensions__tyhpExtensionBacker` plus thin `=>` mappings. All-`=>` catalogs (`IntExtensions`, `FloatExtensions`, `BoolExtensions`) have no backer class.

Generated `package.tyhpdef` copies in-package `global use` / `global use extension` that the library authored. File-level `use extension` is not copied. Loading a package activates `extension { }` blocks for consumers only when that tyhpdef contains `global use extension`.

Same-file Tyhp `extension { }` stays in scope in that file. Class-body tyhpdef `use extension` on a **type** still auto-activates that type’s attached surface for consumers, minus hidden members.

See [Extensions in Tyhpdef](tyhpdef_extensions.md) for the tyhpdef `extension Name { }` syntax (the same header and nested groups; short `fn` / `operator` with `=>` only; empty `{}` is an error).

## Tyhpdef class-body mappings

For the full tyhpdef reference (standalone `extension Name { }`, thin class-body mappings, native vs mapped operators, and `use extension` on a class), see [Extensions in Tyhpdef](tyhpdef_extensions.md).

Inside a tyhpdef class body you can declare `extension fn` and `extension operator` members as thin `=>` mappings. The compiler treats them as a synthetic extension for that class: `$this` in an `extension fn` and `self` in an inline `extension operator` resolve to the enclosing tyhpdef class. These members cannot use `abstract` or `final`. Without `#[\Tyhp\GenericRuntime]` they splice (or erase) — PHP cannot call them. A compiled-library mapping that stamps `GenericRuntime` is not a splice candidate; foreign `$s->jsonDecodeAs<User>()` goes through `\Tyhp\Generic::bind` rather than baking the binder name.

### Operators: native vs mapped

| Form | Meaning | Emitter |
|------|---------|---------|
| `operator +(…): T;` (no `extension`) | Native PHP operator | **No rewrite** — leave `$a + $b` |
| `extension operator +(…): T => …;` | Thin mapping | Splice the `=>` expression |
| `extension operator +(…): T;` (bodyless) | **Illegal** | Diagnostic `TYHP8013` |

```tyhp
<?tyhpdef
namespace Decimal;
final class Decimal {
    // Native on the PECL extension — type-check only; emit keeps `$a + $b`
    operator +(self $left, Decimal|string|int $right): self;
}

class Money {
    public function plus(Money $other): Money;
    public function isEqualTo(Money $other): bool;

    extension operator +(self $left, self $right): self => $left->plus($right);

    extension operator ==(self $left, self $right): bool => $left->isEqualTo($right);

    extension fn formatCurrency(string $locale = 'en_US'): string
        => $locale . ' ' . $this->__toString();

    extension fn shortLabel(): string => $this->formatCurrency();
}
```

## use extension in Tyhpdef Class Bodies

A tyhpdef class can pull in standalone extension declarations with `use extension`, including trait-like adaptations (`as` aliases, `insteadof` precedence). Types that declare `use extension` in tyhpdef can auto-activate those extensions for callers without a separate `use extension` in every Tyhp file (see binder / resolution behavior).

```tyhp
<?tyhpdef
class Money {
    public function plus(Money $other): Money;
    public function format(): string;

    use extension MoneyFormatting {
        MoneyFormatting::format as formatExtended;
    };
}
```

## Importing Extensions with use extension

`use extension` is **opt-in by default**, including for tyhpdef-declared extensions. Extensions from other namespaces or files are imported with `use extension` instead of a regular `use` statement. This makes it explicit that you are bringing extension methods into scope.

An extension declared in your project sources applies in three places: the file that declares it, any file that imports it with `use extension`, and every file once any file declares it with `global use extension`. In any other file a method call is **TYHP4101** (``Symbol `shout` is not found for type `string` ``), and a binary or unary operator from that extension is **TYHP4029**.

```tyhp
<?tyhp

namespace App\Ext;

extension Shout extends string {
    fn shout(): string => \strtoupper($this) . '!';
}

echo "a"->shout(), "\n";   // same file: no import needed
```

```tyhp
<?tyhp

namespace App\Other;

use extension \App\Ext\Shout;

string $s = 'b';
echo $s->shout(), "\n";    // imported: works
```

A file that neither declares nor imports `Shout` gets TYHP4101 for `$s->shout()`.

An `operator convert` declared in an extension follows the same scope. In a file where the extension is active, an `int` passes where the target class is expected and the call compiles to the extension class's static `__from` method. In any other file the conversion does not apply and the argument is TYHP4010. This also holds for first-class callables: `\Probe\takeWallet(...)` accepts an `int` only in files where the conversion is active, and is a plain native callable elsewhere. See [Operator Overloads](tyhp_1600_operatorOverloads.md#conversions-declared-in-an-extension).

```tyhp
<?tyhp

namespace Probe;

class Wallet { public int $amount = 0; }

extension WalletConv extends Wallet {
    operator convert(int $value): self {
        Wallet $w = new Wallet();
        $w->amount = $value;
        return $w;
    }
}

function takeWallet(Wallet $w): int {
    return $w->amount;
}

echo takeWallet(5);   // same file: converts
```

```tyhp
<?tyhp

namespace Other;

use extension \Probe\WalletConv;

echo \Probe\takeWallet(5);   // imported: converts
```

A file without the `use extension` line reports TYHP4010 for `\Probe\takeWallet(5)`.

The import supports trait-like adaptations using curly braces: method `as` aliases, postfix `hide`, and `insteadof` (including on operators). `as` on operators is an error (`TYHP4170`) — use `hide` or `insteadof`. `hide` is a **contextual** keyword only inside `{ }` adaptations (so `function hide()` elsewhere stays valid). A file's adaptations apply to its top-level statements as well as to code inside functions and methods.

```tyhp
<?tyhp

// Import an extension and bring all its methods into scope
use extension App\Extensions\StringExtensions;

// Import with adaptations (like traits)
use extension App\Extensions\ArrayExtensions {
    ArrayExtensions::first as firstItem;
};

string $text = 'hello_world';
echo $text->toCamelCase();  // from StringExtensions

array<int> $nums = [1, 2, 3];
$first = $nums->firstItem();  // aliased from ArrayExtensions::first
```

```tyhp
<?tyhp

use extension StringOperators {
    StringOperators::toUpper as toCC;
    StringOperators::toSnakeCase hide;
    StringOperators::operator *<string> hide;
    operator *<array> hide;   // qualifier optional when this `use` lists one extension
};

use extension StringOperators, RepeatOps {
    RepeatOps::operator *<string> insteadof StringOperators;
};
```

- `operator *<string> hide` hides that target only. `operator * hide` hides every `*` member on that extension.
- `operator convert hide` hides every convert on that extension.
- `operator +<Money> hide` hides all `+` members for that target from this extension (unary and binary together).
- Hide of a name that extension does not declare is `TYHP4173`.
- `insteadof` RHS may be any extension **in scope**, including a same-file `extension { }` that was not listed on this `use`.

`global use extension` (C# `global using`, not PHP `global $var`) activates an extension for the **entire compilation** that loaded that file. `tyhp/core` authors `global use extension \Tyhp\StringExtensions;` (and the matching Array / Int / Float / Bool / Closure extensions) so consumers get `$s->length()` without a per-file import.

```tyhp
<?tyhp

use extension \Tyhp\StringExtensions {
    StringExtensions::toLower hide;
};

string $s = "Hello";
int $len = $s->length();
```

A local `use extension \Tyhp\StringExtensions;` with no adaptations warns (`TYHP4169`). Generated library tyhpdef does **not** emit `global use extension` for the library’s own extensions. See [Use statements](tyhp_0350_useStatements.md#global-use) and [Scalar Pseudo-Objects](tyhp_1000_scalarPseudoObjects.md).

## Chained Extension Method Calls

Extension method calls can be chained. Each link is rewritten independently: a spliced member substitutes its expression; a multi-statement member becomes a static call, with the previous result as the first argument.

```tyhp
<?tyhp

string $result = \trim($input)
    ->toSnakeCase()
    ->truncate(50);
```

```php
<?php

$result = StringExtensions::truncate(
    StringExtensions::toSnakeCase(
        \trim($input)
    ),
    50
);
```

## Access Restrictions

Extension methods can only access public members of the extended type. They cannot access private or protected members because extensions are external to the class hierarchy.

## Best Practices

:::tip
Use extensions to add utility methods to types you don't own — they keep your code clean without subclassing or wrapper patterns.
:::

:::tip
Organize extensions logically by the type they extend (e.g., StringExtensions, ArrayExtensions, DateTimeExtensions).
:::

:::tip
Import only the extensions you need with `use extension` — this is opt-in. Loading a library does not auto-activate its `extension { }` blocks unless that tyhpdef contains `global use extension`. The `tyhp/core` catalog is already globally imported; do not re-import `\Tyhp\StringExtensions` unless you are hiding or renaming methods.
:::

:::tip
Put the target's type parameters on the extension or group, and add method type parameters only when that method needs its own.
:::

:::tip
Keep extension methods pure when possible — they should compute a result from the extended value without side effects.
:::

## Common Mistakes

:::danger
Do not create overlapping extensions for the same type without clear purpose — if two extensions define the same method name for the same type, the compiler reports a conflict.
:::

:::danger
Do not try to access private or protected members from extension methods — extensions can only use the public API of the extended type.
:::

:::danger
Give every extension a header `extends Type` or nested `extends` groups. Members with no target are `TYHP4147`. A header target and nested groups in one extension are `TYHP4362`.
:::

:::danger
Do not use regular use statements for extensions — always use use extension to bring extension methods into scope.
:::

:::danger
Do not re-import `\Tyhp\StringExtensions` (or the other `tyhp/core` scalar extensions) with a local `use extension` unless you are hiding or renaming methods. A redundant non-mutating local `use` warns (`TYHP4169`).
:::

:::danger
Do not write a parameter that a spliced member mutates without `&`, and do not mark `&` on a parameter the expression never writes (`TYHP4174`). Writing `$this` requires `&$this` (`TYHP4369`); `&$this` with no write is `TYHP4370`. A non-mutating increment is `$v + 1`, not `++$v`.
:::

:::danger
Do not put `#[\Tyhp\Optimize\Inline]` on an extension member (`TYHP4176`). Form decides splicing.
:::

```tyhp
<?tyhp

// ERROR TYHP4147: members and no target
// extension Bad {
//     function doSomething(string $value): string { /* ... */ }
// }

// ERROR: conflicting extension methods
// extension StringHelpers1 extends string {
//     function clean(): string { /* ... */ }
// }
// extension StringHelpers2 extends string {
//     function clean(): string { /* ... */ }
// }
// use extension StringHelpers1;
// use extension StringHelpers2;  // Error: conflicting 'clean' method

// ERROR: accessing private member
// extension UserExtensions extends User {
//     function getPasswordHash(): string {
//         return $this->passwordHash;  // Error: private property
//     }
// }
```

## PHP version gating

`#[\Tyhp\Php]` is **illegal** on a Tyhp `extension { }` (**TYHP4304**). Gate an extension with `declare(php=…)` instead — file-level `declare(php=">=8.4");` or a brace block:

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

See [PHP Version Gating](tyhp_0320_phpVersionGating.md).

## Compiler Errors

- An extension with members and no header `extends` or nested `extends` group (`TYHP4147`).
- A header `extends` and a nested group in one extension (`TYHP4362`), or a member outside a group when groups are present (`TYHP4363`).
- A target that is an intersection, `void`, `never`, `mixed`, a type parameter, an object shape, `_`, or a union containing one of those (`TYHP4364`).
- An unused extension or group type parameter (`TYHP4365`), or a method type parameter that reuses one of those names (`TYHP4366`).
- The same method or operator on two overlapping targets in one extension (`TYHP4367`).
- `static::` or `parent::` in an extension member (`TYHP4368`).
- Writing `$this` without `&$this` (`TYHP4369`), or `&$this` when the body never writes `$this` (`TYHP4370`).
- The old member spelling `extends Type $this` or `operator op<Type>` (`TYHP4361`). Put the target on the block. `use extension` adaptations still write `operator +<Money>`.
- A block target that does not resolve to a class or built-in (`TYHP3016`). An operator whose target is `void`, `never`, `null`, `mixed`, `resource`, `true`, or `false` (`TYHP3025`).
- Tyhpdef **class-body** `extension fn` / `extension operator` take the enclosing type as the receiver. They do not use a header `extends`.
- Empty `extension Name {}` (`TYHP4172`).
- `as` on an operator in a `use extension` adaptation (`TYHP4170`); use `hide` or `insteadof`.
- `hide` of a member the extension does not declare (`TYHP4173`).
- Type name colliding with `__tyhpExtensionBacker` (`TYHP4171`).
- Using abstract or final on extension operators or on tyhpdef `extension fn` / `extension operator`.
- A spliced member writes a parameter not declared `&`, declares `&` on a parameter it does not write, or mutates `$this` without `&` (`TYHP4174`).
- A spliced member reduces to itself, directly or through other spliced members (`TYHP4175`).
- `#[\Tyhp\Optimize\Inline]` on an extension member (`TYHP4176`).
- A variable name collides with the generated inline temporary prefix (`TYHP4177`).
- An argument for a `&` parameter is not something PHP can reference (`TYHP4180`).
- An erased member's call site cannot be spliced faithfully (`TYHP4181`).
- Conflicting extension methods for the same type and method name in scope.
- Accessing private or protected members of the extended type from an extension method.
- Using a regular use statement instead of use extension for importing extensions.
- `#[\Tyhp\Php]` on an `extension` declaration (**TYHP4304**). Use `declare(php=…)` (file-level `;` form today).
