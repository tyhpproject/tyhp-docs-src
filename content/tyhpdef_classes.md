---
title: 'Classes in Tyhpdef'
status:
  tier: 0
  story: '02'
  state: complete
---

Tyhpdef lets you describe existing PHP classes to the Tyhp compiler. When importing a class, you declare its properties, methods, constants, and relationships (extends, implements). You only need to declare the members you actually use in your Tyhp code — members already defined via an imported interface do not need to be re-declared.

## Basic Class Declaration

Consider a PHP class you want to use from Tyhp:

```php
<?php

class Customer implements Person {
    protected $data;
    public $heightInCentimeters = 23;

    public function __construct($data = []) {
        $this->data = $data;
    }

    // ... implements Person methods ...
}
```

The Tyhpdef declaration provides full type information. Methods are signatures only, ending with semicolons. Optional `??` on a property is the value PHP is **expected** to start with; the live value may differ, and tyhpdef does not define it.

```tyhp
<?tyhpdef

type CustomerData = struct {
    ?string $first_name;
    ?string $last_name;
};

class Customer implements Person {
    public float $heightInCentimeters ?? 23;
    protected CustomerData $data;

    public function __construct(CustomerData $data = []): void;

    // Members from the Person interface are inherited
    // and do not need to be re-declared here.
}
```

## Class Modifiers

Classes can be declared with `abstract` or `final` modifiers. These modifiers control how Tyhp sees the class at compile time. Make sure they match the actual PHP class — declaring a non-final PHP class as final in Tyhpdef will prevent valid subclassing in Tyhp.

```tyhp
<?tyhpdef

abstract class Entity {
    protected int $id;
    public function getId(): int;
    abstract public function getTableName(): string;
}

final class ImmutableConfig {
    public function get(string $key): mixed;
    public function has(string $key): bool;
}
```

## Properties

Properties are declared with visibility modifiers and types. Only public and protected properties should be declared — private properties are not accessible from Tyhp code.

Optional `?? <value>` after the name is the expected PHP start value (`protected ?\Psr\Log\LoggerInterface $logger ?? null;`, `private array $items ?? [];`). Tyhpdef does not assign the property; the live value may differ. Do not write `= <value>` on tyhpdef properties (or on tyhpdef consts). Parameter defaults still use `=`.

When a PHP constructor promotes a parameter, declare the **property** with `??` and keep `=` on the **parameter**:

```tyhp
public int $count ?? 0;
function __construct(int $count = 0): void;
```

Do not write `function __construct(public int $x ?? 0)`.

Storage properties end with a semicolon. Hooked PHP properties (classes, interfaces, and traits) use a **bodyless** hook list: `{ get; set; }`, `{ get; }`, or `{ &get; set; }`. The list is signatures only — no `get { }` or `get =>` bodies. A hooked declaration names one `$name`. Optional `?? <value>` sits before the hook list (`public string $name ?? "x" { get; set; }`). Hooks may include visibility (`private set`) and `final`. Put `#[\Tyhp\Php]` on the property (or wrap with `declare(php=…)`), not on an individual hook (**TYHP8016**).

```tyhp
<?tyhpdef

class Product {
    public int $id;
    public string $name;
    public float $price ?? 0.0;
    public ?string $description ?? null;
    protected array<string> $tags ?? [];
    public readonly string $sku;
}

class Holder {
    public string $hooked { get; set; }
    public int $hookedCount { get; }
    public array $refItems { &get; set; }
    public string $displayName { get; private set; }
}
```

## Methods

Method declarations include the full signature: visibility, optional modifiers (static, abstract, final), the function keyword, parameters with types, and return type. All methods end with a semicolon.

```tyhp
<?tyhpdef

class UserService {
    public function find(int $id): ?\App\Models\User;
    public function findByEmail(string $email): ?\App\Models\User;
    public static function create(string $name, string $email): \App\Models\User;
    abstract protected function validate(\App\Models\User $user): bool;
    final public function delete(int $id): void;
}
```

`tyhp generate_tyhpdef` writes PHP `static` as `self` on parameters and properties (`@param`, `@var`, magic `@method` parameters, `@property`) and keeps `static` on return types (`: static`, magic `@method` returns, including generic arguments such as `Builder<static>`). Harvested method parameters keep optional `=` with a tyhpdef-safe literal, or `= null` when the PHP default is not representable — the same dummy used for harvested implicit-nullable PHP (`string $timezone = null`). The declared type is not widened. See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#harvested-types-defaults-and-attributes).

## Constructors

Constructors are declared using `__construct` and can specify a return type of `: void`. Constructor parameter promotion (public/protected/private on parameters) is supported. Promoted parameters keep `=` for the parameter default; the cloned property uses `??` for PHP's expected start value (`public int $count ?? 0;` plus `function __construct(int $count = 0): void;`).

```tyhp
<?tyhpdef

class DatabaseConnection {
    public function __construct(
        string $host,
        int $port = 3306,
        ?string $database = null
    ): void;

    public function query(string $sql): array<mixed>;
    public function close(): void;
}
```

## Constants

Class constants are declared with visibility, the const keyword, a type, and a name. Optional `?? <value>` is the expected PHP start value (same meaning as on properties). Do not write `= <value>` on a tyhpdef const.

A child class that redeclares the same constant must keep that type. Omitting the type on the child infers it from the ancestor that first declared the constant. A different type is an error.

```tyhp
<?tyhpdef

class HttpStatus {
    public const int OK ?? 200;
    public const int NOT_FOUND;
    public const int INTERNAL_ERROR;
    public const string DEFAULT_CONTENT_TYPE;
}
```

## Extends and Implements

Classes can extend a parent class and implement one or more interfaces, mirroring PHP's inheritance model.

```tyhp
<?tyhpdef

class AdminUser extends \App\Models\User implements \Stringable, \JsonSerializable {
    public function getRole(): string;
    public function __toString(): string;
    public function jsonSerialize(): mixed;
}
```

## Generic Classes

Classes support generic type parameters with optional constraints. Generics enable type-safe descriptions of PHP classes that work with different types.

```tyhp
<?tyhpdef

class Collection<T> {
    public function add(T $item): void;
    public function get(int $index): T;
    public function count(): int;
    public function toArray(): array<T>;
    public function filter(callable(T): bool $predicate): Collection<T>;
    public function map<U>(callable(T): U $transform): Collection<U>;
}

// Generic class with constraint and extends
class TypedRepository<T extends Entity> extends Repository<T> {
    public const int DEFAULT_PAGE_SIZE;
    public function paginate(int $page, int $size): array<T>;
    async public function saveAsync(T $entity): T;
}
```

`tyhp generate_tyhpdef` writes PHPDoc `@template` tags as these headers. Unqualified class names in a bound (`@template T of Repository<object>`) become FQCNs using `use` imports, unique PHP / `\Psr\*` shorts, and types declared in the same package. Native `extends` / `implements` / trait `use` prefer a same-package declared type over a unique PHP / `\Psr\*` short of the same name. Template parameters (`T`) and builtins stay unqualified. A bound written without type arguments is completed from that type's own default, else its constraint, else `mixed`. See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md#harvested-types-defaults-and-attributes).

## Trait Usage

Classes in Tyhpdef can declare trait usage. Trait conflict resolution and aliasing syntax works the same as in PHP.

```tyhp
<?tyhpdef

class AuditableUser {
    use TimestampedEntity, SoftDeletes {
        SoftDeletes::delete insteadof TimestampedEntity;
        TimestampedEntity::delete as hardDelete;
    }

    public function getAuditLog(): array<string>;
}
```

## Operators

When a PHP type already supports an operator at runtime (engine magic, a PECL extension, `DateTime` comparison, and similar), declare it as a bodyless `operator` member. Tyhp type-checks expressions such as `$a < $b` against the signature. The emitter leaves the PHP operator in place — it does **not** rewrite the site to `__add` or any other method.

The declaration is signature-only: `operator`, the token, typed parameters, a return type, and a semicolon. There is no body and no visibility modifier.

```tyhp
<?tyhpdef

class Instant {
    operator +(self $left, DateInterval $right): Instant;
    operator <=>(self $left, Instant $right): int;
}
```

Binary operators take two parameters; unary operators take one. The same operator can be overloaded for different operand types, the same way methods can.

```tyhp
<?tyhpdef

class Decimal {
    operator +(self $left, Decimal $right): self;
    operator +(self $left, int|float|string $right): self;
    operator +(self $value): int|float;

    operator convert(int $value): self;
    operator convert(self $value): string;
}
```

`extension operator` is a different member: it maps Tyhp operator usage onto PHP methods and **requires** a thin `=>` expression. Use it when the PHP type has methods such as `plus()` but does not implement the operator natively. See [Extensions in Tyhpdef](tyhpdef_extensions.md#native-vs-mapped-operators). A bodyless `extension operator +(…): T;` is an error (`TYHP8013`).

## Partial types (base / include)

`partial` is legal on tyhpdef `class` / `enum` / `interface` / `trait` in base and `include` files. It **adds** members to a type that already exists in this compilation’s include set.

- Additive members only — it does not change generics, `extends`, `implements`, or flags.
- Duplicate member → error (`TYHP8002`).
- Missing target type → error (`TYHP8014`). Include-load order among additive partials does not matter (the type must exist somewhere in the include set).
- `omit` is **illegal** here (overlay-only, `TYHP8017`).

```tyhp
<?tyhpdef

class Box {
    public function get(): int;
}

partial class Box {
    public function extra(): int;
}
```

```tyhp
<?tyhpdef

// ERROR TYHP8014: no matching type in the include set
// partial class DoesNotExist {
//     public function extra(): void;
// }

// ERROR TYHP8002: duplicate member
// partial class Box {
//     public function get(): int;
// }
```

Do not use `partial` to attach standalone extensions. See [Extensions in Tyhpdef](tyhpdef_extensions.md). Overlay files also use brace `partial` (last-wins member replace, missing target = warning), header-only `partial class Foo<T> implements …;` (written header clauses replace; omitted clauses and members stay), overlay `partial function` (attribute merge / rename), and `omit`. Header `;` is overlay-only (`TYHP8034`). See [Tyhpdef Overlays](tyhpdef_overlays.md#overlay-partial-header-form-partial-class-foo).

## PHP version gating

On tyhpdef **classes** (and interfaces, enums, traits, and their members), use `#[\Tyhp\Php("…")]` (positional or `version:`). File-level `declare(php="…");` and brace `declare(php="…") { … }` also parse in `.tyhpdef`.

On a hooked property, put `#[\Tyhp\Php]` on the **property**, not on `get` or `set` (**TYHP8016**):

```tyhp
<?tyhpdef

#[\Tyhp\Php(">=8.4")]
public string $name { get; set; }
```

`#[\Tyhp\Php]` is illegal on `struct` and on tyhpdef `extension { }` (**TYHP4304**). See [PHP Version Gating](tyhp_0320_phpVersionGating.md).

`tyhpdef/php` authors Closure, Fiber, Generator, and ArrayAccess generics in Layer 3 overlays (`_tyhpdef/overlays/Ext.Core.tyhpdef`). `\Closure` is `\Closure<TCallableShape, TThis, TScope>`; spell signatures as `\Closure<callable(int): string>`. `\Fiber` is `Fiber<TResume, TCallableShape>`. Generator functions declare `\Generator` / `\Generator<K, V>` / the four-arg form. See [New and Changed Types](tyhp_0150_newTypes.md).

## Reserved-word type names

PHP allows a class, interface, trait, or enum whose short name is a reserved word (`is`, `isset`, and similar). In a `.tyhpdef`, write that declaration with a leading-backslash fully-qualified name so the parser treats it as a name rather than a keyword:

```tyhp
<?tyhpdef

namespace Hamcrest\Core {
    class \Hamcrest\Core\Is {
        public function matches(mixed $item): bool;
    }
}
```

`tyhp generate_tyhpdef` emits this form. Hand-written include and overlay files use the same spelling. Alias headers keep the PHP name fully qualified: `class \Hamcrest\Core\Is as IsMatcher { … }`. Inside a `namespace { }`, a harvested `extern function` whose short name is a reserved word is written the same way (`extern function \Some\Ns\isset;`).

## Class Aliasing

When the PHP class name differs from what you want to use in Tyhp, you can alias it using the `as` keyword. The original fully-qualified PHP class name comes first, followed by `as` and the Tyhp alias. A reserved-word PHP name is fully qualified on the left of `as` as well (see [Reserved-word type names](#reserved-word-type-names)).

```tyhp
<?tyhpdef

class \Vendor\LongNamespace\SomeVeryLongClassName as ShortName {
    public function doWork(): void;
}
```

## Deprecated and Obsolete

The class itself can be marked `deprecated` or `obsolete` (top-level). Member-level markers parse but are not enforced in this alpha.

```tyhp
<?tyhpdef

deprecated class LegacyAuth {
    public function login(string $user, string $pass): bool;
}

class Auth {
    public function loginWithPassword(string $pass): bool;
    public function loginWithToken(string $token): bool;
}
```

## Best Practices

:::tip
DO declare only public and protected members. Private members are not accessible from Tyhp code and should be omitted from your Tyhpdef declarations.
:::

:::tip
DO match the abstract/final modifiers to the actual PHP class. Mismatched modifiers cause compile-time or runtime errors.
:::

:::tip
DO use bodyless `operator …;` when the PHP type already implements the operator natively. Do not give that member a body.
:::

:::danger
DON'T include ordinary method bodies, hook bodies (`get { }` / `get =>`), or `=` property/const initializers
in class declarations. Methods and storage properties end with a semicolon. Use `?? <value>` when you
need to record PHP's expected start value. Hooked properties use a
bodyless `{ get; set; }` list. Mapping Tyhp operators onto PHP methods uses `extension operator`
with a required `=>` expression; see [Extensions in Tyhpdef](tyhpdef_extensions.md#native-vs-mapped-operators).
:::


:::danger
DON'T re-declare methods that are already defined on an imported interface the class implements. The compiler inherits those signatures automatically.
:::
