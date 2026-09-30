---
title: 'FAQ: Tyhp Syntax'
---

## Do I have to type every variable?

Not explicitly. Tyhp supports type inference on first assignment. When you write `$x = 42;` without a type annotation, Tyhp infers that `$x` is `int`. You only need explicit type annotations when the type cannot be inferred (no initializer) or when you want a wider type than inference would give. Variables without both a type annotation and an inferable initializer always produce an error.

## What happens to types at runtime?

Tyhp's type system is enforced at compile time. Types, generics, and type guards are erased from PHP signatures. The compiled PHP output contains the type hints that PHP itself supports (parameter types, return types, property types). Source type aliases expand to the underlying type in those hints and also emit a `\Tyhp\Type` factory (`UserId()`, `Optional(\Tyhp\Type::int())`) so PHP can name the alias at runtime. A compiled Tyhp library's `package.tyhpdef` stamps `#[\Tyhp\GenericRuntime]` on every emitted generic class, method, and function. Foreign consumer sites use `\Tyhp\Generic::bind`; overlay tyhpdefs that omit the stamp keep erase / inline emit. See [Type Aliases](tyhp_0700_typeAliases.md) and [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md).

## Can I mix Tyhp and PHP files in the same project?

Yes. A Tyhp project can contain both `.tyhp` files (type-checked and compiled) and `.php` files (passed through unchanged). You can even mix Tyhp and PHP within a single file using the `<?tyhp` and `<?php` open tags. Code inside `<?tyhp` blocks is type-checked and compiled; code inside `<?php` blocks is passed through as-is.

## How do generics work without runtime support?

Generics are enforced at compile time. Type parameters are erased from PHP signatures. Same-compilation tracked sites emit factories / `__tyhpGeneric` binders; erased sites stay a plain `new` or plain call. Foreign compiled-library tyhpdefs that stamp `#[\Tyhp\GenericRuntime]` always go through `\Tyhp\Generic::bind(...)(...)`. Overlay tyhpdefs without the stamp keep erase / inline emit. Alias factories (`aliasFactory`) are unchanged.

```tyhp
<?tyhp
function first<T>(array<T> $items): T {
    return $items[0];
}

int $n = first<int>([1, 2, 3]);
```

The compiled PHP has no trace of the generic type parameter `T` — it is used only for compile-time type checking.

## What is the difference between fn (Tyhp arrow functions) and fn (PHP arrow functions)?

In PHP, `fn` creates a short closure (arrow function) with a single expression body. Tyhp extends this: `fn` in Tyhp can also have a block body and supports full type annotations on parameters and return types. Tyhp arrow functions are compiled to PHP closures. The key difference is that Tyhp's `fn` is type-checked and supports generics, while PHP's `fn` has only basic type hints.

## How do I handle nullable types?

All types in Tyhp are non-nullable by default. To allow null, prefix the type with <code>?</code> or use a union type with <code>null</code>:

```tyhp
<?tyhp
?string $name = null;       // nullable via ? prefix
string|null $name2 = null;   // nullable via union
```

Before using a nullable value where a non-nullable type is expected, you must narrow the type with a null check. The Tyhp checker automatically tracks this through control flow analysis:

```tyhp
<?tyhp
function greet(?string $name): string {
    if ($name !== null) {
        // $name is automatically narrowed to string here
        return "Hello, " . $name;
    }
    return "Hello, stranger";
}
```

## Can I use eval() in Tyhp?

By default, `eval()` is disabled in Tyhp for security and type-safety reasons — the compiler cannot verify types inside dynamically evaluated strings. If you absolutely need it, you can re-enable it with `build.allowEval: true` in `tyhp.json`. However, code inside `eval()` is not type-checked. A better alternative is to write the dynamic code in a PHP file and import it via tyhpdef.

## How do extensions differ from traits?

Extensions and traits are both mechanisms for adding functionality to classes, but they work differently. Traits are a PHP feature where methods are copied into a class at the source level. Extensions are a Tyhp feature that lets you add methods to existing classes (even third-party classes) without modifying their source code. Extension methods are compiled to standalone functions that take the target object as the first parameter.

```tyhp
<?tyhp
extension StringExtensions extends string {
    function toTitleCase(): string {
        return \ucwords(\strtolower($this));
    }
}

use extension StringExtensions;
string $title = "hello world"->toTitleCase();
```

## What is `global use`? Is it PHP `global $var`?

No. Tyhp `global use` is like C# `global using`: it prefixes `use` / `use function` / `use const` / `use extension` and applies to the **entire compilation** that loaded that file. It is **not** PHP `global $var`.

A local (non-`global`) `use` may re-import a globally included symbol to give that file an alias or adaptations (`hide`, `insteadof`, method `as`). A local `use` that does not mutate warns (`TYHP4169`, `CheckerRedundantGlobalImport`). See [Use statements](tyhp_0350_useStatements.md#global-use).

## How do I write code that differs by PHP version?

Use gates against `output.phpVersion`, the oldest PHP the build runs on: `declare(php="…")` (file- or block-level) and `#[\Tyhp\Php("…")]` (positional or `version:`). Constraints are Composer syntax; `"8.2"` means the whole `8.2.*` minor. The gates themselves are not written to PHP; a gate that holds for only some versions at or above `output.phpVersion` becomes a `\PHP_VERSION_ID` check. `#[\Tyhp\Php]` is illegal on `struct` and `extension` (**TYHP4304**), and in `.tyhp` on a property, class constant, enum case, or interface method (**TYHP4371**) — use `declare(php=…)` (file-level `;` for Tyhp extensions today). See [PHP Version Gating](tyhp_0320_phpVersionGating.md).

## Why is there one `tyhpdef/php` stubs package instead of one per PHP minor?

Almost all of the `tyhpdef/php` builtin surface is the same on 8.2–8.5. The small differences are version-gated in that single package; the compiler keeps only the declarations that match your `output.phpVersion`. You do not install `tyhpdef/php-8.2` vs `tyhpdef/php-8.4`.

## What are structs used for?

Structs provide a typed alternative to raw associative arrays. They define a fixed set of named, typed properties and are compiled to PHP arrays by default. Structs are value types — they are copied on assignment and compared by value, not by reference — and use structural (schema-based) typing, meaning two structs with compatible shapes are interchangeable.

```tyhp
<?tyhp
type Point = struct {
    float $x;
    float $y;
};

Point $p = new Point() with [x => 1.0, y => 2.5];
float $distance = \sqrt($p->x ** 2 + $p->y ** 2);
```

## How do I use async/await?

Tyhp provides async/await syntax for asynchronous programming. Named async functions are declared with the unwrapped value type (the compiler wraps `Promise<T>`). `await` suspends until a promise resolves. An `async { ... }` block is itself a `Promise<T>` — use it when you want running async work rather than a callable. At compile time, async/await is transformed into promise-based PHP code using the `tyhp/async` runtime package.

```tyhp
<?tyhp
async function fetchUser(int $id): User {
    Response $response = await httpClient->get("/users/{$id}");
    return User::fromJson($response->body());
}

function after(Promise<User> $pending): Promise<string> {
    return async {
        User $user = await $pending;
        return $user->name;
    };
}
```

## How do I swallow an exception on purpose?

Empty `catch` blocks warn **TYHP4121** because they often hide real failures. A comment inside the braces does not count as a statement. Name the exception and discard it with `(void)$e` — the same intentional-discard syntax as unused `#[\NoDiscard]` returns. Catch the specific type you expect when you can. See [PHP Engine Attributes](tyhp_0330_phpEngineAttributes.md).

```tyhp
<?tyhp
try {
    $rp = new \ReflectionProperty($class, $name);
} catch (\ReflectionException $e) {
    (void)$e;
}
```

## When should I write `callable` vs `\Closure`?

Use `callable` / `callable(TArgs …): TReturn` for any invokable: closures, functions, methods, and `__invoke` objects. Use `\Closure` / `\Closure<callable(TArgs …): TReturn>` when you need a Closure **object** (`bind`, `bindTo`, `call`, `fromCallable`) or the class type. Every Closure is callable via `__invoke`; not every callable is a Closure. Assert a specific Closure or Fiber generic shape with `as`. See [New and Changed Types](tyhp_0150_newTypes.md#the-closuretcallableshape-tthis-tscope-type).

## What is the declared return type of a generator?

A function that contains `yield` returns a Generator object. Write `: \Generator`, `: \Generator<TKey, TValue>`, or the full four-arg form — not the type of `return` inside the body. That inner value is `TReturn`, read with `$g->getReturn()` after exhaustion. Bare `\Generator` infers all four arguments from the body. See [New and Changed Types](tyhp_0150_newTypes.md#the-generatortkey-tvalue-tsend-treturn-type).

## Can my class implement `\Traversable`?

Implement `\Iterator` or `\IteratorAggregate` instead. `\Traversable` is an engine interface; only those two may extend it. Listing `\Traversable` on a user class, enum, interface, or trait is **TYHP4326**. See [New and Changed Types](tyhp_0150_newTypes.md#the-traversabletkey-tvalue-type).

## How do `#[\Deprecated]`, `#[\Override]`, and `#[\NoDiscard]` work?

They are PHP Core attributes. Tyhp checks them at compile time:

- `#[\Deprecated]` — use-site warning **TYHP4500**. A string-literal `$message` is included. The tyhpdef `deprecated` keyword is the same warning. Still warns when `output.phpVersion` is below 8.4.
- `#[\Override]` — **TYHP4129** if the method (or, at PHP 8.5+, property) does not override. On a property below 8.5: **TYHP4127**. On `__construct`: always **TYHP4339**.
- `#[\NoDiscard]` — unused return **TYHP4165** from the invoked declaration. Interface and abstract callees do not warn; overrides do not inherit the warning unless marked. `(void)` suppresses. Still warns below PHP 8.5.
- `#[\DelayedTargetValidation]` — at PHP 8.5+, skip target mismatch (**TYHP4127**) for Core attributes on that declaration. Functional checks still run.

See [PHP Engine Attributes](tyhp_0330_phpEngineAttributes.md).

## Do enumerations implement `\UnitEnum`?

Yes. Every enum is `\UnitEnum` without a written `implements`. A backed enum is also `\BackedEnum`. `cases()` resolves on every enum; backed `from()` / `tryFrom()` resolve as well. Classes, interfaces, and traits must not list `\UnitEnum` or `\BackedEnum` (**TYHP4337**). Enums must not list them either, and must not redeclare `cases`, `from`, or `tryFrom` (**TYHP4338**). See [New and Changed Types](tyhp_0150_newTypes.md#the-unitenum-and-backedenumtvalue-types).
