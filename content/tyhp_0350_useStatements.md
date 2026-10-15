---
title: 'Use Statements and Imports'
status:
  tier: 0
  story: '02'
  state: complete
---

Tyhp supports all standard PHP use statement forms and adds Tyhp-specific extensions: generic arguments on import aliases, `use extension` for importing extension method providers, and `global use` (compilation-wide, like C# `global using` — **not** PHP `global $var`). Use statements work the same in Tyhp as they do in PHP -- they create aliases for fully-qualified class, function, and constant names.

## Standard Use Statements

All PHP use statement forms are supported in Tyhp. These behave identically to PHP -- they create namespace aliases for the current file.

```tyhp
<?tyhp

// Import a class
use App\Models\User;

// Import with alias
use App\Models\User as UserModel;

// Import a function
use function App\Helpers\formatDate;

// Import a constant
use const App\Config\MAX_RETRIES;
```

A `use const` name is always read from the global namespace, whatever namespace the importing file declares. In `namespace Demo9;`, `use const Demo9\Util\LIMIT;` makes `LIMIT` compile to `\Demo9\Util\LIMIT`, and an alias (`use const Demo9\Util\LIMIT as CAP;`) or a group member resolves the same way.

## Group Use Declarations

Group use declarations import multiple symbols from the same namespace prefix in a single statement.

```tyhp
<?tyhp

// Group import -- same type
use App\Models\{User, Post, Comment};

// Group import -- mixed types
use App\Services\{
    AuthService,
    function validateToken,
    const MAX_LOGIN_ATTEMPTS
};
```

## Compiled PHP Output for Standard Use Statements

Standard use statements pass through to PHP largely unchanged. The emitter automatically prunes unused imports and sorts them alphabetically:

```php
<?php
declare(strict_types=1);

use App\Models\{User, Post, Comment};

use App\Services\{
    AuthService,
    function validateToken,
    const MAX_LOGIN_ATTEMPTS
};
```

## Generic Import Aliases

Tyhp allows generic type arguments on import aliases. This lets you create a local alias for a specific instantiation of a generic class. The generic arguments are compile-time only -- they are erased from the PHP output. The alias becomes a regular PHP use statement without the generic arguments.

```tyhp
<?tyhp

// Import a generic class with specific type arguments
use App\Collections\TypedList as IntList<int>;
use App\Collections\TypedMap as UserMap<string, User>;

// Now IntList is an alias for TypedList<int>
IntList $numbers = new IntList();
$numbers->add(42);        // OK -- int
// $numbers->add('hello');   // Compile error -- string is not int

// UserMap is an alias for TypedMap<string, User>
UserMap $users = new UserMap();
$users->set('admin', new User('Admin'));
```

Compiles to:

```php
<?php
declare(strict_types=1);

use App\Collections\TypedList as IntList;
use App\Collections\TypedMap as UserMap;

$numbers = new IntList();
$numbers->add(42);

$users = new UserMap();
$users->set('admin', new User('Admin'));
```

:::note
The generic arguments on the alias are a compile-time concept. They tell the Tyhp compiler to treat the alias as if it were the generic class with those specific type arguments. In the PHP output, only the plain alias remains.
:::

## Use Extension Statements

The `use extension` statement imports extension method providers into the current scope. Extension methods allow adding methods to existing types without modifying them. When you import an extension, its methods become available on the extended type within the importing file. An extension declared in a file is already in scope in that file. In a file that neither declares nor imports an extension (and where no `global use extension` covers it), calling one of its methods reports **TYHP4101**.

```tyhp
<?tyhp

// Import an extension -- its methods are now available on the extended type
use extension App\Extensions\StringHelpers;

// StringHelpers extends string with methods like toCamelCase()
string $name = 'hello_world';
string $camel = $name->toCamelCase();  // 'helloWorld'
```

Use extension statements also support trait-like adaptation syntax. This allows you to rename methods with `as`, exclude them with postfix `hide`, and pick a winner with `insteadof`. `as` on operators is an error (`TYHP4170`). See [Extensions](tyhp_2100_extensions.md#importing-extensions-with-use-extension) and [Operator overloads](tyhp_1600_operatorOverloads.md#hiding-and-preferring-extension-operators).

```tyhp
<?tyhp

// Import extension with adaptations
use extension App\Extensions\StringHelpers {
    StringHelpers::toCamelCase as toCC;
    StringHelpers::toSnakeCase hide;
}

string $name = 'hello_world';
string $camel = $name->toCC();  // Uses the renamed method
```

## Global use

`global` prefixes any `use` / `use function` / `use const` / `use extension` and applies to the **entire compilation** that loaded that file. This is C# `global using`, **not** PHP `global $var`.

```tyhp
<?tyhp

global use App\Models\User;
global use function App\Helpers\formatDate;
global use const App\Config\MAX_RETRIES;
global use extension \Tyhp\StringExtensions;
```

When a **loaded tyhpdef** contains `global use extension X`, every `.tyhp` file in that compilation sees `X` as imported. `tyhp/core` does this for `\Tyhp\StringExtensions`, `\Tyhp\ArrayExtensions`, `\Tyhp\IntExtensions`, `\Tyhp\FloatExtensions`, `\Tyhp\BoolExtensions`, and `\Tyhp\ClosureExtensions`, so `$s->length()` works with no per-file import. A compiled library that authored in-package `global use` / `global use extension` copies those statements into `package.tyhpdef`. File-level `use` is not copied. Libraries that did not author `global use` stay opt-in.

Same-file Tyhp `extension { }` stays in scope in that file without an import.

### Local `use` overlaying `global use`

A non-`global` `use` in a file (or braced namespace) may re-import a globally included symbol **in order to mutate it for that scope**:

- An `as` alias that changes the short name (`use App\Models\User as UserModel`, `use extension StringExtensions as SE`)
- A non-empty adaptation block (`as` method rename, postfix `hide`, `insteadof`)

Those mutations apply **only** to that file / namespace. Other files still see the unadapted global import.

A local `use` that does **not** mutate is redundant and warns (`TYHP4169`, `CheckerRedundantGlobalImport`). No mutation means: same imported FQN, no `as` (or `as` to the same short name the global import already uses), and either no `{ }` or an empty `{ }`. Group `use` warns **per name** that is globally included and unmutated; names in the same group that do alias or adapt are silent. The statement remains valid.

```tyhp
<?tyhp

// Assume a loaded tyhpdef already has:
//   global use extension \Tyhp\StringExtensions;
//   global use App\Models\User;

use extension \Tyhp\StringExtensions;           // warning TYHP4169 — already globally included
use App\Models\User;                            // warning TYHP4169 — already globally included
use extension \Tyhp\StringExtensions { };       // warning TYHP4169 — empty adaptations

use App\Models\User as UserModel;               // OK — local alias
use extension \Tyhp\StringExtensions {
    StringExtensions::toLower hide;
    StringExtensions::toUpper as toCC;
};                                              // OK — scope-local hide / rename
```

## Compiled PHP Output for Use Extension

Extension method calls compile to static method calls on the extension class. The `use extension` statement itself is removed from the output (resolved at compile time) and replaced with a standard `use` import for the extension class:

```tyhp
<?tyhp

use extension App\Extensions\StringHelpers;

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

## Tyhpdef Use Statements

In tyhpdef files, use statements serve the same purpose -- importing type symbols into the current scope. Tyhpdef files describe external PHP library signatures for the Tyhp compiler. The same use statement forms (including group use, typed use, `use extension`, and `global use`) are supported in tyhpdef files.


```tyhp
<?tyhpdef

// Tyhpdef use statements follow the same syntax
use Some\External\Library\{ClassA, ClassB};
use function Some\External\Library\helperFunction;
use const Some\External\Library\SOME_CONSTANT;

// Tyhpdef can also declare type aliases
type StringOrNull = string|null;
```

## Importing Type Aliases

Import a source type alias with a plain `use`, the same as a class. That import binds the name for type position and for factory calls (`UserId()`). Tyhp source does not need a second `use function`.

```tyhp
<?tyhp

use App\Types\UserId;
use App\Types\Optional;

function f(UserId $id): void { }

\Tyhp\Type $t = typeof(UserId);
Optional(typeof(int));
```

When the factory is used by short name, emitted PHP rewrites the import to `use function App\Types\UserId;`. Hints-only usage still drops the import. Mixed groups split: `use App\Types\{ User, UserId }` emits a class `use` for `User` and `use function` for `UserId` when the factory is used.

## Import Pruning

During compilation, the emitter automatically prunes unused use statements from the PHP output. If a use statement is declared but never referenced in the emitted code, it is removed. The emitter also sorts remaining imports alphabetically and groups them by type (classes, functions, constants) following PHP community conventions.

Imports for Tyhp-only constructs that are erased during emission (generic type parameters, struct types) are automatically removed since they have no PHP equivalent. A `use` of a source type alias stays class-kind in Tyhp. When emitted PHP references the alias factory by short name (`UserId()`, `typeof(UserId)`, `$x is UserId`), that import is rewritten to `use function`. Hints-only usage of an alias is still pruned. Check-only tyhpdef aliases (no `#[\Tyhp\GenericRuntime(aliasFactory: …)]`) never emit a factory, so their imports stay erased. Compiled-library aliases that stamp `aliasFactory` follow the same factory import rewrite as source aliases. Class and method `GenericRuntime` stamps are independent of `aliasFactory` and do not require helpers.

## Best Practices

:::tip
Use group imports to keep use statements organized when importing multiple symbols from the same namespace.
:::

:::tip
Use generic import aliases to create type-safe aliases for specific generic instantiations. This is cleaner than repeating generic arguments everywhere.
:::

:::tip
Use the `use extension` statement to bring extension methods into scope. Extension methods are opt-in unless a loaded tyhpdef (or this file) used `global use extension`. The `tyhp/core` scalar catalog is already globally imported — add a local `use extension \Tyhp\StringExtensions { … }` only to hide or rename methods in that file.
:::

:::tip
Place use statements at the top of the file, before any namespace or class declarations. The emitter handles automatic import pruning, so unused imports are cleaned up in the output.
:::

:::tip
Use trait-like adaptation syntax on `use extension` when you need to rename methods, `hide` them, or pick a winner with `insteadof`. Operators cannot be renamed with `as`.
:::

## Common Mistakes

:::danger
Don't use generic arguments on imports without an alias. The syntax requires `as AliasName<GenericArgs>` -- you cannot write `use App\MyClass<int>;` directly.
:::

:::danger
Don't import extension classes with a plain `use` statement and expect extension methods to work. You must use the `use extension` syntax to activate extension methods on the target type.
:::

:::danger
Don't import struct names in PHP interop code — struct declarations are erased and do not exist at runtime. Source type aliases exist in PHP as functions or static methods returning `\Tyhp\Type`; call `UserId()` / `Optional(\Tyhp\Type::int())` / `UserService::NameType()`, not as PHP types. See [Type Aliases](tyhp_0700_typeAliases.md).
:::

:::danger
Don't re-import a globally included symbol with a local `use` unless you are aliasing it or applying `hide` / `insteadof` / method `as`. A redundant non-mutating local `use` warns (`TYHP4169`).
:::

## Compiler Error Examples

```tyhp
<?tyhp

// ERROR: Generic arguments require an alias
// use App\Collections\TypedList<int>;

// Correct: use 'as' to create a named alias with generic args
use App\Collections\TypedList as IntList<int>;

// ERROR: Extension methods not available without 'use extension'
// (unless a loaded tyhpdef already has `global use extension` for this name)
// use App\Extensions\StringHelpers;  // plain import, not extension import
// $name->toCamelCase();  // method not found on string

// Correct: use 'use extension' to activate extension methods
use extension App\Extensions\StringHelpers;
string $name = 'hello_world';
string $camel = $name->toCamelCase();  // OK
```
