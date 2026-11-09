---
title: 'CLI: Interop Contract'
status:
  tier: 1
  story: '15'
  state: complete
---

The Tyhp ↔ PHP interop contract is the written ABI between the Tyhp compiler (emitter) and the Tyhp runtime packages (`tyhp/core`, `tyhp/async`, `tyhp/decimal`, `tyhp/lambda`). Compiled Tyhp depends on concrete PHP shapes — class names, method names, and call patterns. This page is the user-facing index for that boundary.

:::note
**Emitter dictates runtime.** The emitter design owns the ABI. Runtime packages implement the shapes the emitter emits; they do not invent alternate public APIs that the compiler is expected to chase. See also `CONVENTIONS.md` §8.
:::

## Why this contract exists

Without an explicit contract, the coupling is implicit: emitter transformers call `\Tyhp\…` by exact FQN and signature, and the runtime must match. When either side changes silently, builds break late. This page writes the contract down, stamps a version on both sides, and keeps a machine-checkable surface so drift is caught early.

## Contract version

Each runtime package stamps the contract it implements in Composer metadata:

```json
{
    "extra": {
        "tyhp": {
            "interopContractVersion": 1
        }
    }
}
```

The compiler constant is `Tyhp.TyhpLang.Interop.InteropContract.CurrentVersion` (currently **1**). When a required runtime package’s stamp does not match the compiler’s current version, the build fails with diagnostic **TYHP5018** (error).

:::warning
`interopContractVersion` is **not** the same as the compiler’s `MAJOR.MINOR.PATCH` (see `VERSIONING.md`) or a package’s Composer semver. A breaking change to an emitted name or signature bumps the interop contract on **both** the compiler and the runtime packages.
:::

## Synthetic dispatch naming

Canonical spellings live in compiler helpers — do not invent parallel schemes. Ownership:

| Kind | Owner |
|------|--------|
| Operator overload methods | `OperatorMethodNameGenerator` (`Tyhp/TyhpLang/Emitter/OperatorMethodNameGenerator.cs`) |
| Generics / property-hook polyfill names | `GeneratedNames` (`Tyhp/TyhpLang/GeneratedNames.cs`) |
| Project conventions pointer | `CONVENTIONS.md` §8 |

### Operators

Every overloadable operator maps to a **single** deterministic method name (no type suffixes, no `_N` collision numbers). Multiple forms of the same operator collapse into one method that dispatches on operand types.

**Binary / comparison**

| Operator | Method |
|----------|--------|
| `+` | `__add` |
| `-` (binary) | `__subtract` |
| `*` | `__multiply` |
| `/` | `__divide` |
| `%` | `__mod` |
| `**` | `__pow` |
| `&` | `__bwAnd` |
| `\|` | `__bwOr` |
| `^` | `__bwXor` |
| `<<` | `__bwSL` |
| `>>` | `__bwSR` |
| `.` (concat) | `__concat` |
| `<` | `__isLessThan` |
| `<=` | `__isLessThanOrEqual` |
| `>` | `__isGreaterThan` |
| `>=` | `__isGreaterThanOrEqual` |
| `==` | `__isEqual` |
| `!=` | `__isNotEqual` |
| `===` | `__isExact` |
| `!==` | `__isNotExact` |
| `<=>` | `__compare` |

**Unary / word**

| Operator | Method |
|----------|--------|
| unary `+` | `__asNumeric` |
| unary `-` | `__negate` |
| `++` | `__increment` |
| `--` | `__decrement` |
| `~` | `__bwNot` |
| `!` | `__not` |
| `empty` | `__isEmpty` |

**Convert**

| Form | Method |
|------|--------|
| convert-from (static factory) | `__from` |
| convert-to `string` | `__toString` |
| convert-to `bool` | `__toBool` |
| convert-to `int` | `__toInt` |
| convert-to `float` | `__toFloat` |
| convert-to `decimal` | `__toDecimal` |
| convert-to other type `T` | `__to{FormattedSegment}` |

Binary/unary/`empty` overloads emit as **static** methods. Convert-to emits as an **instance** method so it can satisfy `\Stringable` and `\Tyhp\Contracts\*Convertible`. Call sites rewrite to `ClassName::__add($l, $r)` (and peers). Feature detail: [Operator Overloads](tyhp_1600_operatorOverloads.md).

### GeneratedNames (generics & property hooks)

| Pattern | Example / spelling |
|---------|-------------------|
| Layout-2 method binder | declared name (`decode`), `layouts: [2]` |
| Layout-1 callable and `#[\Tyhp\InferGeneric]` companion | `name__tyhpGeneric`, `layouts: [1]` |
| Generic class factory (layout 1) | `new_<MangledFqn>__tyhpGeneric` |
| Generic init hook | `__initGenerics__tyhpGeneric` |
| Generic bag | `$__tyhpGeneric` |
| Polyfill get hook | `__get_<prop>__tyhpPropertyHook` |
| Polyfill set hook | `__set_<prop>__tyhpPropertyHook` |
| Polyfill init hook | `__initPropertyHooks__tyhpPropertyHook` |
| Extension `$this` receiver rename | `$this_` (`GeneratedNames.ExtensionReceiverThisAlias`) |

These identifiers (except the extension-receiver rename, which is emit-only) are reserved by the checker so user code cannot collide with generated symbols.

### Extensions

Extension methods keep their declared method name. Call sites rewrite instance-style calls into static dispatch with the receiver first:

```php
ExtensionClass::method($receiver, /* …args */);
```

When the author names the receiver `$this` (the documented spelling), emit renames that parameter to `$this_` in the static method signature and rewrites body references (including nested closures) accordingly — PHP rejects a parameter literally named `$this`. Other receiver names emit unchanged.

Null-safe extension calls short-circuit with a temporary receiver binding. See [Extensions](tyhp_2100_extensions.md).

## Type erasure

Tyhp features that exist for type-checking often leave no (or a reduced) PHP footprint:

| Feature | At runtime | See |
|---------|------------|-----|
| **Generics** | Type parameters erased from signatures. A layout-2 method is `name(types)(args)` under the declared name. `#[\Tyhp\InferGeneric]` keeps the plain call and a `name__tyhpGeneric` companion (`layouts: [1]`). Erased callables stay plain methods, `layouts: [1]`. PHP calls `Box::new(T::int)(42)` and `Box::type(T::int)`. A Tyhp `new` of a foreign class uses `\Tyhp\Generic::bind`. `Generic::bind` binds layout 1 and layout 2 with `\Tyhp\TypeLike|string`. | [Generics](tyhp_0500_generics.md) |
| **Type aliases** | Hints expand to the underlying PHP type. Source `.tyhp` aliases exist at runtime as namespace functions or class static methods returning `\Tyhp\Type` (`UserId()`, `Optional(\Tyhp\Type::int())`, `UserService::NameType()`), not as PHP types. Tyhpdef aliases stay type-only (`typeof` inlines the body) unless they stamp `aliasFactory`. | [Type Aliases](tyhp_0700_typeAliases.md) |
| **Type guards / narrowing** | Compile-time only; `is` / guard checks lower to ordinary PHP boolean tests (`instanceof`, `\is_string($x)` when `#[\Tyhp\NativeTypeTest]` is on that guard, otherwise `\Tyhp\Type::is`). Object-shape aliases always use `\Tyhp\Type::is` with a `Type::objectShape(...)` descriptor (existence-only matching). | [Type Narrowing and Guards](tyhp_0200_typeNarrowingAndGuards.md) |
| **`#[\Tyhp\NativeTypeTest]`** | Compile-only (`#[\Tyhp\NoEmit]`). Never appears in emitted PHP. Picks which type-guard function or concrete static method is the native `$x is T` lowering. | [Functions in Tyhpdef](tyhpdef_functions.md#native-type-tests-tyhpnativetypetest) |
| **`#[\Tyhp\EraseGeneric]`** | Compile-only (`#[\Tyhp\NoEmit]`). Opts a property, promoted constructor parameter, or whole class out of Mechanism C property tracking. | [Generics](tyhp_0500_generics.md) |
| **`#[\Tyhp\GenericRuntime]`** | Runtime-visible stamp on every emitted generic class/method/function (`erased`, `layouts`, optional `factory`/`binder`/`aliasFactory`). Not `NoEmit`. | [Generics](tyhp_0500_generics.md) |
| **`#[\Tyhp\PropertyType]`** | Runtime-visible stamp on a property or promoted constructor parameter whose PHP hint loses its Tyhp type (type arguments, struct types, source type aliases). Its one argument is the full type in the `\Tyhp\Type::parse()` format (`'array<App\\Post>'`); `\Tyhp\Type::fromProperty()` reads it. Types that mention a class type parameter are not stamped. | [Generics](tyhp_0500_generics.md#declared-property-types-at-runtime) |
| **Structs** | Declarations erased; values are associative arrays | [Structs](tyhp_0400_structs.md) |
| **Callable signature utilities** | Compile-time only; `__CallableReturnType<T>` erases to the callable's return type (or `mixed` while `T` is still unbound); `__CallableParametersStruct<T>` / `__CallableParametersTuple<T>` erase to `array` (struct-as-array). Tuple bags use int keys `0..n-1` (`$_1`, `$_2`, … aliases, same shape family as `CallableArgs*`). `__CallableParametersRest<T>` is a pack: value-position `Rest<T> ...$args` unpacks at the call; inside a callable-shape parameter list it auto-splices. `__CallableParametersSlice<T, TStart, TMin>` selects a parameter or a tail of parameters. Rest/Slice erase to `mixed` so PHP does not demand each unpacked argument be an array. Defaulted parameters are optional struct fields at check time; optionality does not survive erasure. ExtStandard `\call_user_func` / `\call_user_func_array` / zip `\array_map` tyhpdefs use these utilities; emit is still the PHP builtins (no new `\Tyhp\*` types, no contract bump) | [New Types](tyhp_0150_newTypes.md) |
| **`internal`** | Stripped; members emit `public`, top-level unprefixed. Omitted from `package.tyhpdef`. | [internal modifier](tyhp_3100_internalModifier.md) |

What **survives** is whatever the emitter explicitly lowers into calls on the runtime surface below (operators, disposables, async, property-hook polyfills, generic bags, `with`, `PropertyPath` / expression trees, and so on).

## Runtime entry points

FQNs the contract covers. Packages are identified by their Composer names (`tyhp/core`, `tyhp/async`, `tyhp/lambda`, …).

### Emitter `RequirePackage` today

The emitter currently records required Composer packages via `EmitContext.RequirePackage` for:

- **`tyhp/core`** — generics, `Type`/`NamedType`, property-accessor polyfill, `ObjectHelper`, convertible contracts, operator overload exceptions, …
- **`tyhp/async`** — `Promise`, await, async wrappers, async disposal paths, …
- **`tyhp/lambda`** — `PropertyPath` and full `Expression` trees construction at call sites

Those packages are what the build action can auto-wire into a project’s `composer.json` from emit.

### Required contract surface (all packages)

Even when the emitter does not yet `RequirePackage` a package for every call site, the following FQNs are part of the **written** interop surface (direct calls and future emit):

#### `tyhp/core`

| FQN | Role |
|-----|------|
| `\Tyhp\Type` | Runtime type values / checks (`Type::check`, `Type::is`, `Type::objectShape`, …) |
| `\Tyhp\NamedType` | Named type arguments in the generic bag |
| `\Tyhp\GenericObject` | Per-instance generic argument bag |
| `\Tyhp\PropertyAccessor` | Property-hook polyfill registrations |
| `\Tyhp\PropertyAccessorObject` | Host for registered accessors (`$__tyhpPropertyHook`) |
| `\Tyhp\ObjectHelper` | Object-form `with` / clone-with lowering |
| `\Tyhp\Contracts\IsDisposable` | Sync disposable protocol |
| `\Tyhp\Concerns\HasGenerics` | Trait wiring the generic bag |
| `\Tyhp\Generic` | `Generic::bind` for a class or callable chosen at runtime, and for explicit types on layout 1 and layout 2. Takes `\Tyhp\TypeLike|string` |
| `\Tyhp\GenericRuntime` | Runtime-visible stamp on emitted generic declarations |
| `\Tyhp\PropertyType` | Runtime-visible declared-type stamp on properties and promoted constructor parameters |
| `\Tyhp\Concerns\UsesPropertyAccessors` / `HasPropertyAccessors` / `HandlesGet` / `HandlesSet` / `HandlesIsset` / `HandlesUnset` / `BootsTraits` | Property-accessor polyfill concerns |
| `\Tyhp\Contracts\{Convertible,StringConvertible,BoolConvertible,IntConvertible,FloatConvertible}` | Convert-to interfaces |
| `\Tyhp\Exceptions\InvalidParametersForOperatorOverloadException` | Operator dispatch miss |
| `\Tyhp\Exceptions\AggregateException` | Multi-error disposal |
| `\Tyhp\Exceptions\{InvalidTypeException,IncompatibleTypeException,PropertyNotFoundException}` | Key type/property failures |

#### `tyhp/decimal`

| FQN | Role |
|-----|------|
| `\Tyhp\Decimal` | Decimal value type |
| `\Tyhp\Contracts\DecimalConvertible` | Convert-to decimal |

Contract surface for decimal operators / convert targets and direct use. The emitter does not currently list `tyhp/decimal` via `RequirePackage` for every decimal path; projects that use decimal still depend on the package.

#### `tyhp/async`

| FQN | Role |
|-----|------|
| `\Tyhp\Promise` | Async wrappers, `_await`, `_async`, `run` |
| `\Tyhp\EventLoop` | Fiber / timer loop |
| `\Tyhp\CancellationToken` / `\Tyhp\CancellationTokenSource` | Cancellation |
| `\Tyhp\DisposableScope` | `:=` disposable scopes |
| `\Tyhp\Contracts\AsyncIsDisposable` | Async disposal |

#### `tyhp/lambda`

| FQN | Role |
|-----|------|
| `\Tyhp\Expression` | Expression-tree root; runtime base for `PropertyPath` |
| `\Tyhp\Expr` | Fluent tree builder — emit target for `Expression` arguments |
| `\Tyhp\Expression\ExpressionNode` (and `Expression\*` node types) | Tree nodes, built by `\Tyhp\Expr` |
| `\Tyhp\PropertyPath` | Property-path expressions — emit target through `PropertyPath::on` |

**PropertyPath emit ABI:** when a call argument targets `PropertyPath<callable(T): R>` and the argument is an inline property-chain `fn`, the emitter lowers to a chain with one property step per segment, ended by `backedBy` with the original `fn`:

```php
\Tyhp\PropertyPath::on(\SourceType::class)   // or a builtin type string such as 'string'
    ->segment
    /* … */
    ->backedBy(fn (/* … */): ResultType => /* original chain */);
```

A segment read through `?->` is preceded by `nullSafe()`, so the runtime builds a `NullSafeAccessExpression` for that hop instead of a `PropertyAccessExpression`:

```php
\Tyhp\PropertyPath::on(\User::class)->billing->nullSafe()->city->backedBy(fn(\User $u): ?string => $u->billing?->city);
```

**Expression emit ABI:** when a call argument targets `Expression<callable(T): R>` and the argument is an inline arrow `fn`, the emitter lowers to a `\Tyhp\Expr` chain ended by `backedBy` with the original `fn`, which returns the `\Tyhp\Expression`:

```php
\Tyhp\Expr::param('u', \User::class)->age->gt(18)->backedBy(fn(\User $u): bool => $u->age > 18);
```

The chain uses these builder calls:

- `Expr::param(name, type, index)` starts at a parameter; `index` is passed when the `fn` has several parameters.
- A property read is a property step (`->age`), or `prop('name')` when the name matches a builder method. `nullSafe()` precedes a `?->` hop.
- `call(name, ...args)`, `staticCall(Class::class, name, ...args)`, and `make(Class::class, ...args)` build method calls, static calls, and `new`.
- Operators are builder methods: `gt`, `gte`, `lt`, `lte`, `eq` (`===`), `neq` (`!==`), `looseEq` (`==`), `looseNeq` (`!=`), `spaceship`, `plus`, `minus`, `times`, `dividedBy`, `mod`, `pow`, `concat`, `bitAnd`, `bitOr`, `bitXor`, `shiftLeft`, `shiftRight`, `not`, `neg`, `pos`, `bitNot`, `and`, `or`, `xor`, `coalesce`, `then` / `else`, `is`, `cast`, and `at` (array access).
- A nested arrow `fn` is `Expr::closure([Expr::param(...), …], <body chain>, 'returnType')`, and an array literal is `Expr::arrayOf([values], [keys])`.
- Captured variables, literals, and class constants are passed as plain PHP arguments (`->gt($minAge)`, `->value(User::FLAG)`), so their values are read when the chain runs.

A nested `fn` passed to a method's `callable`, `Expression`, or `PropertyPath` parameter becomes an `Expr::closure` node:

```php
\Tyhp\Expr::param('u', \User::class)->tags->call('any', \Tyhp\Expr::closure([\Tyhp\Expr::param('t', \Tag::class)], \Tyhp\Expr::param('t', \Tag::class)->label->eq('vip'), 'bool'))->backedBy(fn(\User $u): bool => $u->tags->any(fn(\Tag $t): bool => $t->label === 'vip'));
```

Parameter types use the `\Tyhp\Type::parse()` format. A parameter whose type has type arguments or is a struct is passed as a string (`'App\Table<App\Blog>'`, `'struct App\Address'`) instead of `Fqn::class`; a property node's type is the declared property type (`\Tyhp\Type::fromProperty()`). The tree's return type comes from the backing closure's return type.

`Expression` takes one type argument: the callable shape (`Expression<callable(User): string>`; `Expression<callable(): R>` for zero parameters). That shape is a checker/type-system convention; the emitted chain is the same for every shape.

`tyhp build` emits those chains for an inline `fn`. The emitted file is the same whether or not the `tyhp` module is loaded.

On a parameter typed `Expression` or `PropertyPath`, the emitted hint is `\Tyhp\Expression|\Closure` or `\Tyhp\PropertyPath|\Closure`. A nullable parameter keeps `|null`. The value body starts with a prologue that calls `fromClosure` when the argument is a `\Closure`, passing the parameter's callable shape. A promoted constructor parameter, a by-reference or variadic parameter, a property-hook parameter, an inline closure's own parameter, a parameter typed as a union with a type other than `null`, and a parameter with `#[\Tyhp\PhpType]` keep the spelled type and get no prologue. A closure variable in `.tyhp` is still TYHP4323 (`Expression`) or TYHP4320 (`PropertyPath`).

`nameof(fn ($x) => $x->a->b)` is a compile-time fold to the last property segment (a string literal). It does not emit `PropertyPath` / `Expression` construction.

`ExpressionSerializer::toJson` / `equals` and `Expression::equals` are **runtime library APIs** (not emitter call patterns). User code that calls them depends on `tyhp/lambda` the same way any other package type does.

When a `PropertyPath` / `Expression` value is passed where `\Closure` is expected, emit extracts the stored closure as `$expr->callable` (public readonly property on `\Tyhp\Expression`). Where `callable` is expected, the object is passed through (`__invoke`).

Feature detail: [Parsable Lambdas](tyhp_3000_parsableLambdas.md).

## Emitted docblocks

PHP that calls compiled Tyhp, and PHPStan or Psalm run on that PHP, can rely on docblock tags wherever the native declaration drops a type Tyhp checked. The tags are on in every build profile and do not depend on `output.comments`.

`emit.docblocks` defaults to `"lossy-only"`: a tag is written only when it says more than the PHP hint (`array<int, User>` becomes native `array` plus `@param array<int, \App\User>`). `"all"` tags every signature type. `"off"` writes none of the generated tags. `emit.docblockDialect` (`"both"` by default, or `"phpstan"`, `"psalm"`, `"phpdoc"`) is parsed and validated and does not change the text. Shared tags are unprefixed.

What a consumer can rely on, when the checker had the type: `@param`, `@param-out` for a by-ref parameter, `@return`, `@var`, `@template` (with `of`, variance, and a default when the parameter has them), `@extends`, `@implements`, `@use`, and `@internal`. `@throws` is not generated; an author `@throws` is kept. Symbol names in generated tags are fully qualified, and a `use … as` alias is the real name. `self`, `parent`, and `static` stay relative. A struct is `array{…}` with optional keys as `key?:`. A callable is `callable(int): string`. `class-string` is used for a class, interface, or enum name.

An author docblock's summary stays above the tags. `@tyhp` emitter directives and `/@@ … @@/` blocks pass through. An author analysis tag wins per key; the generator fills gaps. `output.comments: false` drops the prose and keeps the directives and the analysis tags.

The compiler does not run PHPStan or Psalm. The full spelling and merge rules are on [Emitted Docblocks](cli_emittedDocblocks.md).

## Lowering protocols (index)

Brief map from Tyhp construct → PHP runtime pattern. Goldens live under the conformance suite; prefer those over re-deriving internals from this page.

| Construct | Lowering sketch | Goldens / docs |
|-----------|-----------------|----------------|
| Disposables `:=` | `\Tyhp\DisposableScope::create()` + `using` / try-finally fallback | `tests/conformance/story11/disposables/`; [Disposables](tyhp_2300_disposables.md) |
| Async / await | `\Tyhp\Promise::_async` / `_await` / `run`; return type `\Tyhp\Promise` | `tests/conformance/story11/async/`; [Async and Await](tyhp_2600_asyncAndAwait.md) |
| `with` / clone-with | `\Tyhp\ObjectHelper::with(…)` (or native PHP 8.5 `clone(…)` when targeted) | `tests/conformance/story11/with/`; [with keyword](tyhp_2200_withKeyword.md) |
| Operators | Static/`__to*` calls via `__add`, … | `tests/conformance/story11/operator-overloads/`; [Operator Overloads](tyhp_1600_operatorOverloads.md) |
| Generics | Erasure. Layout 2 is the declared-name binder. Layout-1 companions are `name__tyhpGeneric`. Class factories and `__initGenerics__tyhpGeneric` stay the layout-1 class machinery | `tests/conformance/story11/generics/`; [Generics](tyhp_0500_generics.md) |
| Property hooks (PHP &lt; 8.4) | Strip native hooks; `UsesPropertyAccessors` + `PropertyAccessor` registration; `__get_/__set_*__tyhpPropertyHook` | hook suites (native ≥ 8.4/8.5); polyfill paths in emitter |
| Expression trees / PropertyPath | `\Tyhp\PropertyPath::on(…)->segment…->backedBy($fn)` (`nullSafe()` before `?->` hops); `\Tyhp\Expr::param(…)->…->backedBy($fn)` for `Expression` (nested `fn` → `Expr::closure`); parameter hint `\Tyhp\Expression\|\Closure` or `\Tyhp\PropertyPath\|\Closure` with a `fromClosure` prologue; `\Closure` sites → `$path->callable` | `tests/Tyhp.Tests/Emitter/PropertyPathEmitterTests.cs`, `ExpressionEmitterTests.cs`; [Parsable Lambdas](tyhp_3000_parsableLambdas.md) |
| PHP 8.5 surface / lower targets | Pipe, `(void)`, `clone(…)`, exit/die, attributes | `tests/conformance/story14_5/` |

A thin index suite lives under `tests/conformance/story15/` (operators, extensions, generics erasure, structs, disposables, async, expression trees). Fuller emit coverage remains in `tests/conformance/story11/` and `tests/conformance/story14_5/` — see the conformance README.

## Compatibility policy

- **Additive** changes (new optional runtime helpers the emitter does not yet call, new convertible targets that do not rename existing methods) may ship without bumping `interopContractVersion`. A minor bump is optional documentation hygiene.
- **Breaking** changes — any rename or signature change of an emitted call, synthetic method, or required FQN — require bumping `interopContractVersion` on the compiler (`InteropContract.CurrentVersion`) **and** on every affected runtime package’s `extra.tyhp.interopContractVersion`.
- **PHP matrix** — which PHP minor a release supports is coordinated with the `tyhpdef/php` / `tyhpdef/php-ext-*` packages and the PHP-encoded compiler **MAJOR** in `VERSIONING.md`. Contract bumps and MAJOR bumps are independent axes; both may move in the same release when an ABI and a PHP target change together.

## Machine-checkable surface

`InteropContractSurface` enumerates emitter-required runtime symbols (the contract surface). Conformance tests assert that each symbol is declared — with the documented namespace and keyword — in the owning package’s committed `package.tyhpdef`. The tyhpdef is the checked source of truth because emitted `src/` PHP is regenerated (and `dist/` is not committed).

:::tip
When changing emit call patterns, update `OperatorMethodNameGenerator` / `GeneratedNames`, the runtime packages, `InteropContractSurface`, this page, and bump `interopContractVersion` if the change is breaking — in that order of truth: **code helpers → runtime → surface enum → docs → version stamp**.
:::
