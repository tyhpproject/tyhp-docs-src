---
title: 'Tyhpdef Quick Reference'
---

A condensed overview of Tyhpdef syntax — the declaration-only language for describing existing PHP code to the Tyhp compiler. Similar to TypeScript's `.d.ts` files. For full details, follow the link below each feature.

## The Open Tag

Every `.tyhpdef` file starts with the `<?tyhpdef` tag. Supports namespaces (semicolon and braced styles) and `use`/`import` statements. Only declarations are allowed — no function bodies or executable code.

<a href="tyhpdef_openTag.html">See full documentation →</a>

```tyhp
<?tyhpdef

const string APP_NAME;
function myPhpFunction(string $input): int;
```

## Variables and Constants

Declare global PHP variables and constants with types. Use `as` to alias a constant. Top-level `deprecated`/`obsolete` work. Tyhpdef `??` records PHP's expected start value (the live value may differ); `&` is not a tyhpdef form.

<a href="tyhpdef_variablesAndConstants.html">See full documentation →</a>

```tyhp
<?tyhpdef
bool $debugMode;
string $appName;

const string APP_ENV;
const int \MAX_LOOPS_ALLOWED as MAX_LOOPS;
```

## Functions

Declare function signatures with typed parameters (including optional, reference, and variadic), generic type parameters, async functions, function aliases, and extension functions. `fallback function` is a signature PHP defines only when that name is still empty; Composer `autoload.files` order chooses among packages. `declare(ext="name")` / `declare(ext="!name")` keeps a block when that extension's tyhpdef package is loaded or absent. Overlay `partial function` (optionally `as`) merges attributes or renames without restating the signature. Version-specific signatures use `#[\Tyhp\Php("…")]` or `declare(php=…)` in `.tyhpdef`.

<a href="tyhpdef_functions.html">See full documentation →</a>

```tyhp
<?tyhpdef
class UserData {
    public int $id;
}

class Mapper {
    public function map<TValue, TResult extends void|never|mixed>(
        callable(TValue): TResult $callback,
        array<TValue> $array
    ): array<TResult>;
}

async function fetchUserData(int $userId): UserData;
function key_exists as keyExists(int|string $key, array $array): bool;
function toCamelCase(extends string $str): string;

#[\Tyhp\Php(">=8.2 <8.4")]
function example(string $v): mixed;
#[\Tyhp\Php(">=8.4")]
function example(string $v, bool $strict = false): string;
```

## Extensions

Attach Tyhp extension methods and operator overloads to PHP types. **Standalone** `extension Name extends Type { }` (or nested `extends Type { }` groups, with no header target) uses short `fn` / `operator` + `=>` members; `$this` is the block target; return types required; empty `{}` is an error. Class-body `extension fn` / `extension operator` are **thin mappings** (`=>` only, fully erased; PHP cannot call them; `$this` / `self` are the enclosing class). File-level `use extension` is opt-in unless `global use extension`. `tyhp/core` globally imports `\Tyhp\StringExtensions` and the other scalar catalogs. `use extension` on a tyhpdef class auto-activates that type’s attached surface. Bodyless `operator …;` is native PHP passthrough; bodyless `extension operator` is an error. `hide` / operator `insteadof` are allowed; `as` on operators is an error. `#[\Tyhp\Php]` is illegal on `extension { }` (**TYHP4304**); wrap with `declare(php=…)`. Multi-statement bodies live in `tyhp_src/` with `class PhpName as Name__tyhpExtensionBacker`.

<a href="tyhpdef_extensions.html">See full documentation →</a>

```tyhp
<?tyhpdef
class StringOperatorBacker {
    public static function toUpper(string $value): string;
    public static function multiply(string $left, int $right): string;
}

extension StringOperators extends string {
    fn toUpper(): string
        => StringOperatorBacker::toUpper($this);
    operator * (self $left, int $right): string
        => StringOperatorBacker::multiply($left, $right);
}

class Money {
    public function plus(Money $other): Money;
    public function __toString(): string;

    extension operator +(self $left, self $right): self => $left->plus($right);

    extension fn formatCurrency(string $locale = "en_US"): string
        => $locale . " " . $this->__toString();
}

extension MoneyFormatting extends Money {
    fn format(): string => $this->__toString();
}

partial class Money {
    use extension MoneyFormatting {
        MoneyFormatting::format as formatExtended;
    }
}
```

## Interfaces

Declare PHP interfaces with fully typed method signatures, constants, inheritance (`extends`), generic type parameters with constraints, method overloads, and async methods.

<a href="tyhpdef_interfaces.html">See full documentation →</a>

```tyhp
interface Repository<T> {
    public function find(int $id): ?T;
    public function save(T $entity): void;
}

interface Stream extends Readable, Writable {
    public function close(): void;
}
```

## Classes

Declare PHP classes with properties (including optional `??` expected start values and bodyless hooked `{ get; set; }` / `{ &get; }`), methods, constructors (with parameter promotion — property `??`, parameter `=`), constants (`??` only, not `=`), extends/implements, generics, trait usage, native `operator` members, class aliasing with `as`, and base/`include` `partial` (additive members; duplicate = error; missing target = error; `omit` is overlay-only). A reserved-word short name (`is`, `isset`, …) is written fully qualified (`class \Hamcrest\Core\Is`). Overlay last-wins brace `partial`, header-only `partial class Foo<T>;`, `partial function`, and `omit` are documented in [Tyhpdef Overlays](tyhpdef_overlays.md).

<a href="tyhpdef_classes.html">See full documentation →</a>

```tyhp
class Collection<T> {
    public function add(T $item): void;
    public function map<U>(callable(T): U $transform): Collection<U>;
}

class Holder {
    public string $name { get; set; }
    public array $items { &get; set; }
}

class \Vendor\LongNamespace\SomeClass as ShortName {
    public function doWork(): void;
}
```

## Overlays

`extra.tyhp.package` `"include"` on `composer.json` is the baseline (duplicates error). `"overlay"` loads after, stubs then hand, last Tyhp name wins. Overlay brace `partial` replaces listed members (missing target = warning). Overlay `partial class Foo<T> implements …;` (also interface / trait / enum) replaces written header clauses and keeps unlisted members. Overlay `partial function` merges attributes onto an existing callable without restating the signature. `partial function X as Y;` and `partial class X as Y;` **rename** the current Tyhp name unless the same overlay file also keeps `X`. Match later overlays to the live Tyhp name. `omit` hides a symbol (overlay-only). `// @overlay-against:` stamps the Layer 1 signature. `tyhp overlay create` / `stamp`. `tyhp symbol_tree` dumps the bound names.

<a href="tyhpdef_overlays.html">See full documentation →</a>

```tyhp
<?tyhpdef
// @overlay-against: interface Iterator
partial interface Iterator<TKey = mixed, TValue = mixed> extends \Traversable<TKey, TValue>;
partial interface Iterator {
    public function current(): TValue;
}

omit function \array_map();

#[\Tyhp\Optimize\Pure]
partial function \str_contains;
partial function \strtolower as str2LC;
partial function \strtoupper;
partial function \strtoupper as str2UC;

partial class SplObjectStorage;
partial class SplObjectStorage as ObjectStorage;
```

## Extern names

Name-only placeholders for types, functions, or constants this package mentions but does not own (`suggest` / `require-dev` Composer peers, optional extensions, author-only tyhpdefs). Legal in tyhpdef signatures; not usable in `.tyhp` (`TYHP4307`). A real declaration of the same name silently replaces the placeholder. Use `extern \Name;` when the kind is unknown. When the kind is known, write the same kind as the originating declaration (`extern interface` for an `interface`); a mismatch is `TYHP8029`. `tyhp build` writes author-only owners into `package.tyhpdef`; `--package-path` / `--source` write `_tyhpdef/externs.tyhpdef`.

<a href="tyhpdef_extern.html">See full documentation →</a>

```tyhp
<?tyhpdef
extern \Elastica\Client;
// @provided-by: tyhpdef/php-ext-curl
extern class \CurlHandle;
extern interface \Psr\Log\LoggerInterface;
extern function \bcadd;
extern const \GMP_ROUND_PLUSINF;
```

## Enums

Declare unit enums (no backing value) and backed enums (`string` or `int`). Supports case values, methods, interface implementation, constants, aliasing, and deprecated cases. Every enum is `\UnitEnum` (and `\BackedEnum` when backed) without listing those interfaces; harvested stubs may keep them. Do not redeclare `cases` / `from` / `tryFrom`.

<a href="tyhpdef_enums.html">See full documentation →</a>

```tyhp
enum HttpMethod: string {
    case GET = "GET";
    case POST = "POST";
    case PUT = "PUT";
}

enum Permission: int implements \Stringable {
    case Read = 1;
    case Write = 2;
    public function __toString(): string;
}
```

## Traits

Declare PHP traits with typed properties, methods, constants, abstract methods, and generic type parameters. Generic traits specify concrete type arguments when used in Tyhp code.

<a href="tyhpdef_traits.html">See full documentation →</a>

```tyhp
<?tyhpdef
trait Collection<T> {
    public function add(T $item): void;
    public function getItems(): array<T>;
}
```

```tyhp
<?tyhp
class User {}

class UserList {
    use Collection<User>;
}
```

## Structs

Value types backed by PHP associative arrays. Named as `type Name = struct { … };`. Support required and optional properties, property aliases for non-identifier array keys, defaults, inheritance, nesting, generics, and inline `struct { … }` in type position.

<a href="tyhpdef_structs.html">See full documentation →</a>

```tyhp
type UserProfile = struct {
    string $name;
    ?string $bio;
    string $role = "user";
};

type ApiResponse<T> = struct {
    bool $success;
    ?T $data;
    ?string 'Reply-To' as $replyTo;
};
```

## Type Aliases

Create named aliases for complex type expressions using the `type` keyword. Supports generic parameters with constraints. Allowed at root level or inside namespace blocks. Tyhpdef aliases are type-only: they do not emit a PHP factory; `typeof` inlines the body.

<a href="tyhpdef_typeAliases.html">See full documentation →</a>

```tyhp
type Scalar = int|float|string|bool;
type StatusCode = 200|301|302|404|500;
type Result<T, TError extends \Throwable> = T|TError;
type Predicate<T> = callable(T): bool;
```

## Namespaces

Both braced and semicolon-style namespace declarations. Multiple namespaces per file allowed. PHP items can be imported into a different tyhpdef namespace using leading-backslash fully-qualified names.

<a href="tyhpdef_namespaces.html">See full documentation →</a>

```tyhp
namespace App\Models {
    class User { public int $id; public string $name; }
}

namespace EL {
    class \EmailerLib\Emailer {
        public function __construct(string $subjectLine): void;
    }
}
```

## Import Aliases

Alias a namespaced PHP class with `as` (`\Vendor\LegacyApi as Api`). Methods inside that declaration can be aliased the same way. Only the aliased name is available in Tyhp.

<a href="tyhpdef_importAliases.html">See full documentation →</a>

```tyhp
<?tyhpdef
class User {
    public int $id;
}

class \Vendor\LegacyApi as Api {
    public string $usr_nm;
    public function get_usr as getUser(int $id): ?User;
}
```

## Overloaded Functions and Methods

Declare multiple signatures for the same function/method name to describe PHP functions with varying parameter types and return types. Supports static value type overloads, generic overloads, and async overloads.

<a href="tyhpdef_overloadedFunctions.html">See full documentation →</a>

```tyhp
<?tyhpdef
class DecodeObject {}
class User {
    public int $id;
}

type DecodeAssoc = array<string, mixed>;

function decode_json(string $json, true $assoc): DecodeAssoc|null;
function decode_json(string $json, false $assoc): DecodeObject|null;
function decode_json(string $json, null $assoc = null): DecodeObject|null;

class UserRepo {
    public function find(int $id): ?User;
    public function find(string $uuid): ?User;
    public function find(array<string, mixed> $criteria): array<User>;
}
```

## The `deprecated` and `obsolete` Keywords

`deprecated` produces a compiler warning but still compiles. `obsolete` produces a compiler error and blocks compilation. Both must appear before all other modifiers. In this alpha they are enforced on **top-level** functions, classes, interfaces, traits, enums, constants, and variables — not on class/interface members or enum cases.

<a href="tyhpdef_deprecatedKeyword.html">See full documentation →</a>

```tyhp
<?tyhpdef
class \Vendor\Connection {}

deprecated function \vendor_connect(string $server, string $user, string $pass): \Vendor\Connection|false;
obsolete function \vendor_md5(string $string, bool $binary = false): string;
```

## Runtime Errors and Exceptions

When tyhpdef declarations don't match actual PHP code, runtime errors can occur. Declare exception hierarchies and document throws with `@throws` (documentation only in this alpha).

<a href="tyhpdef_runTimeErrorsAndExceptions.html">See full documentation →</a>

```tyhp
<?tyhpdef
class \Vendor\JsonException extends \Exception {
    public function __construct(
        string $message = "",
        int $code = 0,
        ?\Throwable $previous = null
    ): void;
}

/** @throws \Vendor\JsonException When encoding fails */
function \vendor_encode(mixed $value): string|false;
```
