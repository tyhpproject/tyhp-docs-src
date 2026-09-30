---
title: 'PHP Engine Attributes'
status:
  tier: 2
  state: complete
---

PHP Core attributes such as `#[\Deprecated]`, `#[\Override]`, `#[\NoDiscard]`, and `#[\DelayedTargetValidation]` emit as ordinary PHP attributes. Tyhp type-checks them at compile time. The attribute **classes** stay version-gated in `tyhpdef/php`; some **checks** still run when `output.phpVersion` is below the introducing minor. See [PHP Version Gating](tyhp_0320_phpVersionGating.md#engine-attributes-and-outputphpversion).

`tyhp --explain TYHP####` prints the long-form text for each code below.

## `#[\Deprecated]`

`#[\Deprecated]` marks a declaration as deprecated. Using that symbol warns **TYHP4500**. The binder treats the attribute the same way as the tyhpdef `deprecated` keyword — both set deprecation on the symbol, and both produce this one warning.

When `$message` is a string literal, it is appended to the diagnostic after a colon (`{0}` is the name, `{1}` is `: ` plus the message). Omit `$message` and the warning stays the one-argument form `` `{0}` is deprecated ``. `$since` is not part of the short message.

Tyhp warns even when `output.phpVersion` is below 8.4. PHP’s runtime `E_USER_DEPRECATED` is a no-op on older minors; the compile-time warning still fires.

```tyhp
<?tyhp

#[\Deprecated('use bar()')]
function foo(): void {}

foo();  // WARNING TYHP4500: `foo` is deprecated: use bar()
```

On a tyhpdef, `deprecated function baz();` is the same warning without an attribute. See [The deprecated and obsolete Keywords](tyhpdef_deprecatedKeyword.md).

## `#[\Override]`

`#[\Override]` marks a method — and, when `output.phpVersion` is **8.5 or later**, a property — as intended to replace a parent or interface member.

- If no same-name non-private ancestor or interface member exists, that is **TYHP4129**.
- On a target below 8.5, `#[\Override]` on a **property** is a target mismatch (**TYHP4127**).
- On `__construct`, **TYHP4339** always — constructors are exempt from override semantics, even when a parent constructor exists.

Trait method bodies are not checked here; PHP applies the attribute on the composing class.

```tyhp
<?tyhp

class Base {
    public int $x = 0;

    public function label(): string {
        return 'base';
    }
}

class Child extends Base {
    #[\Override]
    public function label(): string {
        return 'child';
    }

    // Legal when output.phpVersion is 8.5 or later and Base has $x:
    #[\Override]
    public int $x = 1;

    // ERROR TYHP4339 at every phpVersion:
    // #[\Override]
    // public function __construct(): void {}
}
```

A method or property that is marked but does not override uses TYHP4129, not TYHP4339.

## `#[\NoDiscard]`

`#[\NoDiscard]` marks a function or method whose return value should be used. A discarded call (an expression statement, or a non-final `for` list item) warns **TYHP4165**. When `$message` is a string literal, it is appended after a colon, the same way as `#[\Deprecated]`.

Use the return (assignment, argument, condition, and so on), or discard it on purpose with `(void)`:

```tyhp
<?tyhp

#[\NoDiscard('check the status')]
function save(): int {
    return 1;
}

function run(): void {
    save();               // WARNING TYHP4165, including ": check the status"
    (void)save();         // OK
    int $n = save();      // OK
    $_ = save();          // OK — assignment is a use
}
```

The warning comes from the **invoked** declaration:

- Calling through an **interface** or **abstract** method does not warn, even if that declaration is marked.
- An **override** does not inherit the warning unless it is itself marked.
- A **trait-imported** method keeps the attribute (PHP copies it onto the using class).

Tyhp reports this even when `output.phpVersion` is below 8.5. `(void)` is native PHP on 8.5 or later; below 8.5 the emitter omits the cast and still treats it as an intentional discard.

## `#[\DelayedTargetValidation]`

On PHP 8.5, `#[\DelayedTargetValidation]` on a declaration defers **target** (`TARGET_*`) errors for **internal** (Core) attributes on that same declaration until `ReflectionAttribute::newInstance()`. Tyhp’s compile-time analogue: when `output.phpVersion` is **8.5 or later** and this attribute is on the declaration, **TYHP4127** is skipped for Core attributes on that declaration.

Functional checks still run. `#[\Override]` that does not override is still TYHP4129. Unused `#[\NoDiscard]` returns are still TYHP4165. `#[\Override]` on `__construct` is still TYHP4339.

Below 8.5 the skip is ignored — target mismatches are still reported.

```tyhp
<?tyhp

class Base {
    public int $x = 0;
}

class Child extends Base {
    // On 8.5, `#[\Override]` on a property is already a legal target, so there is nothing
    // for `#[\DelayedTargetValidation]` to skip here. Base has $x, so this is not TYHP4129 either.
    #[\DelayedTargetValidation]
    #[\Override]
    public int $x = 1;
}

class Orphan {
    // Still TYHP4129: `#[\DelayedTargetValidation]` only skips the TARGET_* check, not the
    // override check. Orphan has no parent, so there is no $y to override.
    #[\DelayedTargetValidation]
    #[\Override]
    public int $y = 1;
}
```

Userland attributes are still target-checked. Only PHP Core engine attributes on that declaration skip TYHP4127.

## `#[\SensitiveParameter]`

`#[\SensitiveParameter]` on a parameter has no use-site diagnostic. In the debugger, marked arguments stay wrapped as `\SensitiveParameterValue`. See [CLI: Xdebug Proxy](cli_xdebugProxy.md).

## Diagnostics

| Code | Severity | When |
|------|----------|------|
| TYHP4500 | Warning | Use of a `#[\Deprecated]` or tyhpdef `deprecated` symbol |
| TYHP4129 | Error | `#[\Override]` on a method or (8.5+) property that does not override |
| TYHP4339 | Error | `#[\Override]` on `__construct` |
| TYHP4165 | Warning | Unused return from a `#[\NoDiscard]` callee |
| TYHP4127 | Error | Attribute target mismatch, including `#[\Override]` on a property below 8.5 |

See the [Diagnostic Code Reference](diagnostics_reference.md) for the compiler’s short messages.

## Common mistakes

:::danger
Don't put `#[\Override]` on `__construct`. That is TYHP4339 at every `output.phpVersion`, including when a parent constructor exists.
:::

:::danger
Don't expect `#[\Override]` on a property to type-check on a target below 8.5. That is TYHP4127 until `output.phpVersion` is 8.5 or later.
:::

:::danger
Don't assume an interface or abstract `#[\NoDiscard]` warns at the call site. Mark the invoked implementor or override.
:::

:::tip
`(void)expr` is the intentional discard for unused `#[\NoDiscard]` returns and for empty `catch` bodies (`(void)$e`). See [Lost and Changed Functionality](tyhp_2900_lostFunctionality.md).
:::
