---
title: 'Tyhp Quick Reference'
---

A condensed overview of Tyhp language features. Each section includes a brief explanation and representative code. Features marked **not in this alpha** are planned (Tier 3) and will not compile yet.

## File Tags and Open Tags

Tyhp files use `<?tyhp` (source) and `<?tyhpdef` (type definitions). File extensions are `.tyhp` and `.tyhpdef`. Strict types are always enforced. Use `declare(output_file=...)` to control compiled output paths.

<a href="tyhp_0000_openTag.html">See full documentation →</a>

```tyhp
<?tyhp
declare(output_file='public/index.php');

$greeting = 'Hello, Tyhp!';
```

## PHP Version Gating

`declare(php="…")` and `#[\Tyhp\Php("…")]` filter declarations against `output.phpVersion` (Composer constraints; `"8.2"` means `8.2.*`). File-level inactive declare skips the file silently. `output.phpVersion` is the oldest PHP the build runs on: a gate true for every later version emits nothing, and one true for only some emits a `\PHP_VERSION_ID` check. `#[\Tyhp\Php]` is illegal on `struct` / `extension` (**TYHP4304**), and in `.tyhp` on a property, class constant, enum case, or interface method (**TYHP4371**). Omit `output.phpVersion` → default `"8.2"` and one **TYHP4306** warning.

<a href="tyhp_0320_phpVersionGating.html">See full documentation →</a>

```tyhp
<?tyhp
#[\Tyhp\Php(">=8.4")]
function array_find(array $array, callable $callback): mixed {
    return null;
}

declare(php=">=8.4") {
    function only_84(): void {}
}

declare(php="<8.4") {
    function only_84(): void {}
}
```

## PHP Engine Attributes

`#[\Deprecated]` warns **TYHP4500** at the use site (literal `$message` is included; still warns below PHP 8.4). `#[\Override]` on a method that does not override is **TYHP4129**; on a property it is legal at PHP 8.5+ (below 8.5: **TYHP4127**); on `__construct` it is always **TYHP4339**. `#[\NoDiscard]` unused returns warn **TYHP4165** from the invoked declaration (`(void)` suppresses; interface/abstract callees do not warn). `#[\DelayedTargetValidation]` at PHP 8.5+ skips target mismatch (**TYHP4127**) for Core attributes on that declaration; functional checks still run.

<a href="tyhp_0330_phpEngineAttributes.html">See full documentation →</a>

```tyhp
<?tyhp
#[\Deprecated('use bar()')]
function foo(): void {}

#[\NoDiscard]
function save(): int {
    return 1;
}

(void)save();
```

## Typed Variables

Locals lead with inference: `$var = …` is the primary form. Write `int $x = …` when inference is not enough (no initializer, or a wider type than the right-hand side). Parameters, properties, and return types still need a type. All types are non-nullable by default. Prefix with `?` for nullable.

<a href="tyhp_0100_typesAndLocals.html">See full documentation →</a>

```tyhp
$sum = 0;                         // inferred as int
$items = [1, 2, 3];               // inferred as array<int>
foreach ($items as $item) {       // inferred from the iterable
    $sum += $item;
}
int $total = $sum;                // explicit when you need a spelled type
?string $nickname = null;         // nullable — inference would not allow null
array<string> $names = ['Alice', 'Bob'];
```

## New and Changed Types

Built-in types gain generic parameters: `array<T>`, `Iterator<K, V>`, `\Closure<callable(TArgs …): TReturn>`. Callable signatures are shapes: `callable(TArgs …): TReturn`. New types include `decimal` for precise arithmetic, `Promise<T>` for async, `\Tyhp\Contracts\ArrayAccessShape<TStruct>` for per-key maps, and `#[\Tyhp\PhpType]` for emitted PHP hints.

<a href="tyhp_0150_newTypes.html">See full documentation →</a>

```tyhp
decimal $price = \Tyhp\decimal('19.99');
callable(string): int $parser;                      // takes string, returns int
\Closure<callable(string): int> $asClosure;         // Closure instance with that shape
Promise<User> $future = fetchUser(42);
```

## Type Narrowing and Guards

Type guard checks (`is_*()`, `instanceof`, `is`, null checks) automatically narrow variable types within the guarded scope. Custom type guard functions use the `$param is Type` return syntax.

<a href="tyhp_0200_typeNarrowingAndGuards.html">See full documentation →</a>

```tyhp
function processValue(mixed $value): string {
    if ($value is string) {
        return \strtoupper($value);  // narrowed to string
    }
    if (\is_int($value)) {
        return (string)$value;       // narrowed to int
    }
    return '';
}

// custom type guard
function isNonEmpty(mixed $v): $v is array {
    return \is_array($v) && \count($v) > 0;
}
```

## Generics

Type parameters on classes, interfaces, traits, enums, functions, and methods. Fully erased at compile time. Supports `extends` constraints and default type parameters.

<a href="tyhp_0500_generics.html">See full documentation →</a>

```tyhp
class Box<T> {
    public function __construct(private T $value): void {}
    public function getValue(): T { return $this->value; }
}

Box<int> $intBox = new Box<int>(42);

function firstOrNull<T>(array<T> $items): ?T {
    return $items[0] ?? null;
}
```

## Generic Defaults

Generic type parameters can have default types with `=`. Defaults must be trailing and can reference earlier parameters.

<a href="tyhp_3500_genericDefaults.html">See full documentation →</a>

```tyhp
class Collection<T = mixed> { ... }
class Pair<T, U = T> { ... }
class Promise<TReturn extends void|mixed = void> { ... }
```

## Type Aliases

The `type` keyword creates named shortcuts for complex type expressions. Supports generics and class-level aliases with visibility. Hints expand to the underlying PHP type. Source aliases also emit a `\Tyhp\Type` factory (`UserId()`, `Optional(\Tyhp\Type::int())`).

<a href="tyhp_0700_typeAliases.html">See full documentation →</a>

```tyhp
type UserId = int;
type Callback = callable(string, int): bool;
type Optional<T = mixed> = T|null;

function f(UserId $id): void {}
\Tyhp\Type $t = typeof(UserId);
Optional(typeof(int));

class UserService {
    public type UserIdType = int;
}
UserService::UserIdType();
```

## Static Value Types

Literal types that represent a single specific value. Enable precise unions as lightweight enums and function overloads with literal dispatch.

<a href="tyhp_0800_staticValueTypes.html">See full documentation →</a>

```tyhp
type HttpMethod = 'GET'|'POST'|'PUT'|'PATCH'|'DELETE';
type Color = 'red'|'green'|'blue';
function getExitCode(): 0|1|2 { return 0; }
```

## Structs

Lightweight value types that compile to PHP associative arrays. PHP sees `array`; there is no runtime shape check. Support typed properties, defaults, array key aliases (`as`), inheritance, anonymous declarations, and updates with `with`.

<a href="tyhp_0400_structs.html">See full documentation →</a>

```tyhp
type Point = struct { float $x; float $y; };

Point $p = new Point() with [x => 10.5, y => 20.3];
Point $p2 = clone $p with [x => 5.0];

type ApiResponse = struct {
    int 'status_code' as $statusCode;
    string $body;
};
```

## Short Function Syntax

Use `fn` for single-expression named functions and methods. Compiles to a standard function with an explicit `return`.

<a href="tyhp_1100_shortFunctionSyntax.html">See full documentation →</a>

```tyhp
fn double(int $n): int => $n * 2;
public fn getValue(): int => $this->value;
fn identity<T>(T $value): T => $value;
```

## Function and Method Overloads

Multiple signatures for different parameter types with specialized return types. Only the implementation body is emitted to PHP. Zero-cost compile-time feature.

<a href="tyhp_1200_functionOverloads.html">See full documentation →</a>

```tyhp
function convert(string|int|float $v, true $toInt): int;
function convert(string|int|float $v, false $toInt): float;
function convert(string|int|float $v, bool $toInt = false): int|float {
    // implementation
}
```

## Scalar Pseudo-Objects

Call methods on scalar types (`string`, `int`, `float`, `bool`, `array`) and `\Closure` using object syntax. Compiles to PHP function calls with zero overhead. The **built-in** catalog ships in `tyhp/core` (`global use extension \Tyhp\StringExtensions` and the matching Array / Int / Float / Bool / Closure files) — no per-file `use extension`. String methods prefer `\mb_*` via `\Tyhp\StringHelper` when mbstring is loaded, and fall back to byte APIs otherwise; `byte` prefix is always byte-oriented (`byteLength()` → `\strlen`). Local `use` only when adapting (`hide` / `as`).

<a href="tyhp_1000_scalarPseudoObjects.html">See full documentation →</a>

```tyhp
$name->contains('World');              // \str_contains($name, 'World')
$name->trim()->toLower();              // \Tyhp\StringHelper::strtolower(\trim($name))
$numbers->mapped(fn($n) => $n * 2);    // \array_map(fn($n) => $n * 2, $numbers)
$price->round(2);                      // \round($price, 2)
```

## Extensions

Add methods and operator overloads to existing types without modifying their source. A member's form decides what PHP keeps: short `fn … => expr;` is Tyhp-only (spliced, no PHP method); a single-`return` brace body is spliced in Tyhp **and** callable from PHP on the backer; a multi-statement body is a real PHP method that Tyhp calls. Imported via opt-in `use extension` (or `global use extension` in a loaded tyhpdef — `tyhp/core` scalars are already on). Generated library tyhpdef emits a backer class (`Name__tyhpExtensionBacker`) plus thin `extension { }` mappings. File-level `use` is not copied; in-package `global use extension` that the library authored is. Adaptations: method `as`, postfix `hide`, operator `insteadof` (`as` on operators is an error).

<a href="tyhp_2100_extensions.html">See full documentation →</a>

```tyhp
extension StringExtensions extends string {
    function toCamelCase(): string { ... }
}

use extension App\Extensions\StringExtensions;
$text->toCamelCase();  // StringExtensions::toCamelCase($text)

use extension StringOperators {
    StringOperators::toSnakeCase hide;
    operator *<string> hide;
};
```

## Object Declaration Changes

Constructors may omit the return type (same as `: void`) or write `: parent(args...)` to chain. Constructor property promotion works as in PHP, including `readonly`.

<a href="tyhp_1300_newObjectDeclSyntax.html">See full documentation →</a>

```tyhp
class Point {
    public function __construct(
        public readonly float $x,
        public readonly float $y
    ): void {}
}

class NamedPoint extends Point {
    public function __construct(
        public string $name,
        float $x, float $y
    ): parent($x, $y) {}
}
```

## The `with` Keyword

Sets properties on objects and structs after `new`, `clone`, or in place. Object `with` mutates identity; struct `with` rebinds an array — the same distinction as passing an object vs passing an array into a PHP function. Combined with `readonly` properties, `clone $obj with [...]` leaves the original unchanged.

<a href="tyhp_2200_withKeyword.html">See full documentation →</a>

```tyhp
$user = new User('Alice', 30) with [role => 'admin'];
$updated = clone $user with [name => 'Bob', age => 25];
```

## Operator Overloads

Define custom operator behavior on classes and enums. Supports binary, unary, comparison, conversion, and special operators (`true`/`false`/`empty`/`null`). Calls are rewritten to method calls in PHP output. Extension operators can be hidden or preferred with `hide` / `insteadof`; they cannot be renamed with `as`.

<a href="tyhp_1600_operatorOverloads.html">See full documentation →</a>

```tyhp
class Vector {
    operator +(self $l, self $r) => new static($l->x + $r->x, $l->y + $r->y);
    operator ==(self $l, self $r) => $l->x === $r->x && $l->y === $r->y;
    operator convert(int $v) { return new static((float)$v); }
}
```

## Trait Requirements

Traits can declare `extends` and `implements` requirements. Enforced at compile time and erased from PHP output.

<a href="tyhp_2000_traitRequirements.html">See full documentation →</a>

```tyhp
trait Cacheable extends Entity implements Serializable {
    // can safely use Entity and Serializable members
}
```

## The `internal` Modifier

Omits the declaration from the published `package.tyhpdef`. Emitted as `public` (members) or unprefixed (top-level) in PHP. Cannot combine with `public` / `protected` / `private` (`TYHP4002`).

<a href="tyhp_3100_internalModifier.html">See full documentation →</a>

```tyhp
internal class InternalHelper { ... }
internal function computeHash(string $data): string { ... }
internal const MAX_RETRIES = 3;
```

## Null-Conditional Assignment (not in this alpha)

Assignment through `?->` on the left-hand side. If any `?->` in the chain encounters null, the assignment becomes a no-op. Works with all assignment operators.

<a href="tyhp_3300_nullConditionalAssignment.html">See full documentation →</a>

```tyhp
$config?->theme = 'dark';
$user?->address?->city = 'Berlin';
$obj?->count += 1;
```

## Disposables and the `:=` Operator

Deterministic resource management via `IsDisposable`/`AsyncIsDisposable` interfaces. `:=` (using assignment) auto-disposes on scope exit. `using` blocks provide explicit try/finally disposal.

<a href="tyhp_2300_disposables.html">See full documentation →</a>

```tyhp
$db := new DatabaseConnection($dsn);
// $db->dispose() called automatically at scope exit

using ($db = new DatabaseConnection($dsn)) {
    $db->query('SELECT ...');
}

using await ($conn = new AsyncConnection($url)) { ... }
```

## Async and Await

First-class `async`/`await` using PHP Fibers. Async functions return `Promise<T>` and lower to `Promise::_async` / `_await`. Blocking PHP I/O blocks the `tyhp/async` loop. Includes combinators (`Promise::all`, `race`, `batch`, `timeout`), async iteration, and cancellation tokens.

<a href="tyhp_2600_asyncAndAwait.html">See full documentation →</a>

```tyhp
async function fetchUser(int $id): User {
    return await $repo->find($id);
}

Promise<int> $pending = async {
    return await fetchCount();
};

array $results = await Promise::all([$fetchA, $fetchB, $fetchC]);

foreach (await $queue->messagesAsync() as Message $msg) {
    // process messages asynchronously
}
```

## Parsable Lambdas and Expression Trees

When a parameter is typed `PropertyPath<callable(T): R>` or `Expression<callable(T): R>`, an inline `fn` is captured as a data structure instead of compiling to a closure. Enables building SQL queries, validation rules, etc. at runtime.

<a href="tyhp_3000_parsableLambdas.html">See full documentation →</a>

```tyhp
$query->select(fn ($u) => $u->address->city);  // PropertyPath
$query->where(fn ($u) => $u->age > 18 && $u->isActive); // Expression tree

Expression<callable(User): bool> $expr = fn ($u) => $u->age > 18;
```

## Object Shapes and `__New<T>`

A `type` alias whose RHS is `object { … }` is a structural object type (instance duck typing). `__New<Shape>` additionally requires a concrete public constructor (`new T(...)`). Class-name strings are `__ClassName<Shape>` / `__ClassName<__New<Shape>>`. Erased to `object` (or nominal conjuncts from an intersection).

<a href="tyhp_3400_newTypeConstraint.html">See full documentation →</a>

```tyhp
type Named = object {
    public function __construct(string $name): void;
    public function ping(): void;
};

function create<T extends __New<Named>>(string $name): T {
    return new T($name);
}
```

## Compile-Time Constructs

Four compile-time constructs. `nameof` and many `default` / `variable_exists` uses fold to literals; `typeof` emits a `\Tyhp\Type` value.

<a href="tyhp_2700_compileTimeConstructs.html">See full documentation →</a>

```tyhp
nameof($user->name);        // 'name' — refactoring-safe string name
typeof(int);                // \Tyhp\Type::int()
typeof(UserId);             // UserId()
typeof(Optional<int>);      // Optional(\Tyhp\Type::int())
default(int);               // 0 — zero value for a type
variable_exists($x);        // true/false literal
```

## Use Statements and Imports

All PHP `use` forms plus generic import aliases (`use Foo as Bar<int>`), `use extension` for importing extension method providers, and `global use` (compilation-wide, like C# `global using` — not PHP `global $var`). A local `use` may re-import a globally included symbol to alias or adapt it; a redundant non-mutating local `use` warns (`TYHP4169`). Unused imports are auto-pruned.

<a href="tyhp_0350_useStatements.html">See full documentation →</a>

```tyhp
use App\Collections\TypedList as IntList<int>;
IntList $numbers = new IntList();

use extension App\Extensions\StringHelpers;
$camel = $name->toCamelCase();

global use extension \Tyhp\StringExtensions;
```

## The Mixed Type

`mixed` is the top type and always requires type guard narrowing before any type-specific operations — there is no setting that relaxes this, and no permissive counterpart (Tyhp has no equivalent of TypeScript's `any`). Prefer generics or union types when the accepted types are known.

<a href="tyhp_0600_theMixedType.html">See full documentation →</a>

## Dynamic Language Features

Variable variables, variable functions, dynamic property/method access, and dynamic instantiation require type narrowing via special `__` types (`__ClassName`, `__FunctionName`, `__PropertyName<T>`, etc.) before use.

<a href="tyhp_2400_dynamicLanguageFeatures.html">See full documentation →</a>

```tyhp
__ClassName $cls = 'App\\Models\\User';
if (\class_exists($cls)) {
    $obj = new $cls();
}
```

## PHP Magic Methods

All PHP magic methods are supported with additional type safety. `mixed`-returning magic methods (`__get`, `__call`, etc.) require type narrowing before use. Extension methods take priority over `__call`. The compiler may generate `__clone()` helpers when `with` updates `readonly` properties.

<a href="tyhp_2500_phpMagicMethods.html">See full documentation →</a>

## Including Files

`include`/`require`/`include_once`/`require_once` all require static string paths or constants — no dynamic includes. The compiler performs PSR-4 output splitting with one PHP file per class.

<a href="tyhp_0300_includingFiles.html">See full documentation →</a>

## Lost and Changed Functionality

Tyhp disables `eval()`, short open tags (`<?`), and untyped catch blocks. Undeclared property writes are allowed only on exact `\stdClass`; other types declare properties or use `__get`/`__set`. All types must be declared or inferred. All catch blocks require a typed variable. Dynamic features require type narrowing.

<a href="tyhp_2900_lostFunctionality.html">See full documentation →</a>
