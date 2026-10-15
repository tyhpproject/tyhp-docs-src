---
title: 'Parsable Lambdas and Expression Trees'
status:
  tier: 1
  story: '16'
  state: complete
  note: 'PropertyPath and Expression trees: TCallableShape, nameof(fn), instanceof/is, serialization, and structural equality'
---

Tyhp supports parsable lambdas — a feature that allows the compiler to capture the abstract syntax tree (AST) of an inline `fn` expression instead of just compiling it to a closure. When a function parameter is typed `PropertyPath<callable(T): R>` or `Expression<callable(T): R>`, passing an inline `fn` expression causes the compiler to emit a data structure describing the expression tree. The receiving function can then inspect the structure of the lambda at runtime — walking property accesses, method calls, operators, and constants — to translate the expression into another domain such as SQL queries, validation rules, or serialization mappings.

The types come from the `tyhp/lambda` package; see [tyhp/lambda](package_lambda.md) for the full API.

:::note
This is the same concept as C#'s `Expression<Func<T, TResult>>`, which powers Entity Framework's LINQ-to-SQL. The parameter type drives the behavior: if a parameter is typed `Expression<callable(T): R>`, the compiler emits an expression tree; if typed `callable` or `\Closure`, the compiler emits a normal closure.
:::

## PropertyPath<callable(T): R> — Type-Safe Property References

`PropertyPath<callable(T): R>` is the simplest form of parsable lambda. It captures a chain of property accesses from an `fn` expression. When a parameter is typed `PropertyPath<callable(T): R>`, the compiler converts `fn ($p) => $p->propA->propB` into a `PropertyPath` object containing the chain `['propA', 'propB']` plus type information.

```tyhp
<?tyhp

use Tyhp\PropertyPath;

class User {
    public function __construct(
        public string $firstName,
        public Address $address,
    ) {}
}

class Address {
    public function __construct(
        public string $city,
        public string $state,
    ) {}
}

class ColumnBuilder<T> {
    public function select(PropertyPath<callable(T): string> $prop): static {
        echo $prop->getPropertyName(), ' | ', $prop->getPath(), ' | ', \implode(',', $prop->getSegments()), "\n";
        return $this;
    }
}

$columns = new ColumnBuilder<User>();

// Single property
$columns->select(fn ($u) => $u->firstName);

// Chained property access
$columns->select(fn ($u) => $u->address->city);
```

Output:

```text
firstName | firstName | firstName
city | address.city | address,city
```

## PropertyPath Members

`PropertyPath` extends `Expression`, so it has every `Expression` member listed [below](#expression-members) as well as the members here. The constructor takes `$sourceType` and `$resultType` as strings and passes them to the parent `Expression`, which stores the result type as `$returnType`.

:::member[readonly array<string> $path]
The property names in the access chain, in order. For `fn (User $u) => $u->address->city`, this is `['address', 'city']`.
:::

:::member[getPropertyName(): string]
Returns the final property name (last element of the path). For `fn (User $u) => $u->address->city`, returns `'city'`.
:::

:::member[getPath(): string]
Returns the full dot-notation path string. For `fn (User $u) => $u->address->city`, returns `'address.city'`.
:::

:::member[getSegments(): array<string>]
Returns the path as an array of property names.
:::

:::member[getValue(mixed $source): __CallableReturnType<TCallableShape>]
Reads the property chain from `$source` and returns the value. For a null-safe chain, a `null` link yields `null`.
:::

## PropertyPath Compiled PHP Output

When you pass an `fn` expression to a `PropertyPath` parameter, the compiler emits a `\Tyhp\PropertyPath` construction. The original `fn` is included as the callable argument so the path can be executed directly.

```tyhp
<?tyhp

$columns->select(fn ($u) => $u->address->city);
```

```php
<?php

$columns->select(\Tyhp\Generic::bind(\Tyhp\PropertyPath::class, null)(
    \User::class,
    'string',
    ['address', 'city'],
    fn(\User $u): string => $u->address->city
));
```

## Nullable Property Chains

`PropertyPath` supports null-safe property access. Nullable chains are allowed, and the path records which links used `?->`.

```tyhp
<?tyhp

class User {
    public function __construct(
        public ?Address $billing = null,
    ) {}
}

class ColumnBuilder<T> {
    public function selectMaybe(PropertyPath<callable(T): ?string> $prop): static {
        echo $prop->getPath(), "\n";
        return $this;
    }
}

$columns = new ColumnBuilder<User>();

// Nullable chain — the result type is ?string
$columns->selectMaybe(fn ($u) => $u->billing?->city);
```

Output:

```text
billing.city
```

The emitted construction passes `nullSafeFlags`, which records whether each link used `?->`. The expression tree then contains `NullSafeAccessExpression` nodes for those links rather than plain property access:

```php
<?php

$columns->selectMaybe(\Tyhp\Generic::bind(\Tyhp\PropertyPath::class, null)(
    \User::class,
    '?string',
    ['billing', 'city'],
    fn(\User $u): ?string => $u->billing?->city,
    nullSafeFlags: [false, true]
));
```

`getValue()` returns `null` when a null-safe link is `null`:

```tyhp
<?tyhp

function readMaybe(User $user, PropertyPath<callable(User): ?string> $path): void {
    $value = $path->getValue($user);
    echo $value ?? 'null', "\n";
}

readMaybe($ada, fn ($u) => $u->billing?->city);   // Ada has no billing address
readMaybe($ada, fn ($u) => $u->address->city);
```

Output:

```text
null
Oslo
```

## Expression<callable(T): R> — Full Expression Trees

`PropertyPath<callable(T): R>` extends `Expression<callable(T): R>`. `Expression` supports full expression trees: any supported inline `fn` body — not just property chains — can be captured as a tree of expression nodes. This enables runtime inspection of comparison operators, method calls, binary expressions, captured variables, and more.

`Expression` takes one type argument: the callable shape of the lambda. `Expression<callable(User): string>` is a single-parameter lambda taking `User` and returning `string`. `Expression<callable(T, T): int>` is a two-parameter lambda returning `int`. Zero-parameter lambdas are `Expression<callable(): R>`.

```tyhp
<?tyhp

use Tyhp\Expression;

class QueryBuilder<T> {
    public function where(Expression<callable(T): bool> $predicate): static {
        echo $predicate->body->nodeType, ' ', $predicate->returnType, "\n";
        return $this;
    }

    public function select(Expression<callable(T): string> $selector): static {
        echo $selector->body->nodeType, ' ', $selector->returnType, "\n";
        return $this;
    }
}

int $minAge = 18;

$query = new QueryBuilder<User>();
$query->where(fn ($u) => $u->age > $minAge && $u->isActive);
$query->where(fn ($u) => $u->getFullName() === 'Ada Lovelace');
$query->select(fn ($u) => $u->firstName);
```

The `fn` expressions are converted to `Expression` trees because the parameter types are `Expression<callable(T): R>`.

Output:

```text
binary bool
binary bool
propertyAccess string
```

### Expression Members

:::member[readonly ExpressionNode $body]
The expression tree root node representing the `fn` body.
:::

:::member[readonly array<ParameterExpression> $parameters]
The lambda parameters as `ParameterExpression` nodes.
:::

:::member[readonly \Closure<TCallableShape> $callable]
The compiled closure for execution. Every `Expression` carries its original compiled closure so it can be executed directly.
:::

:::member[readonly string $returnType]
The resolved return type of the expression, as a type string.
:::

:::member[mixed $lastResult]
The last value produced by `__invoke` or `PropertyPath::getValue`.
:::

:::member[__invoke(__CallableParametersRest<TCallableShape> ...$args): __CallableReturnType<TCallableShape>]
Executes the expression by delegating to the stored callable. This makes an `Expression` callable via `$expr($arg)`.
:::

:::member[compile(): \Closure<TCallableShape>]
Returns the stored compiled closure.
:::

:::member[equals(\Tyhp\Expression $other): bool]
Structural equality; see [Expression Serialization](#expression-serialization).
:::

### Expression Builders

`Expression` also offers static helpers for building predicates without an inline `fn`:

:::member[static of<T extends object>(__ClassName<T> $sourceType, string|array ...$segments): \Tyhp\PropertyPathBuilder<T>]
Starts a fluent property-path builder for the property chain `$segments` of `$sourceType`.
:::

:::member[and(?\Tyhp\Expression<TCallableShape> $other = null): \Tyhp\Expression]
Combines this predicate with `$other` using `&&`. Without an argument, it starts a fluent continuation.
:::

:::member[or(?\Tyhp\Expression<TCallableShape> $other = null): \Tyhp\Expression]
Combines this predicate with `$other` using `||`. Without an argument, it starts a fluent continuation.
:::

:::member[static andAll(\Tyhp\Expression<callable(mixed): bool> $first, \Tyhp\Expression<callable(mixed): bool> $second, \Tyhp\Expression<callable(mixed): bool> ...$rest): \Tyhp\Expression<callable(mixed): bool>]
Combines two or more predicates with `&&`.
:::

:::member[static orAll(\Tyhp\Expression<callable(mixed): bool> $first, \Tyhp\Expression<callable(mixed): bool> $second, \Tyhp\Expression<callable(mixed): bool> ...$rest): \Tyhp\Expression<callable(mixed): bool>]
Combines two or more predicates with `||`.
:::

`andAll` and `orAll` take `Expression<callable(mixed): bool>` arguments. See [tyhp/lambda](package_lambda.md) for how they combine predicates and for the complete member reference.

## Expression Node Types

Expression trees are built from a hierarchy of node types. Every node extends `ExpressionNode` and carries a `type` string and a `nodeType` identifier. The `type` string is the node's resolved type; for a literal it is the literal's type (for example `'int'`, `'string'`, or `'18'`).

:::member[ParameterExpression]
Represents a lambda parameter (`$x`). Properties: `string $name`, `string $paramType`, `int $index`. `nodeType`: `parameter`.
:::

:::member[PropertyAccessExpression]
Represents a property access (`$x->firstName`). Properties: `ExpressionNode $object`, `string $property`. `nodeType`: `propertyAccess`.
:::

:::member[NullSafeAccessExpression]
Represents a null-safe property access (`$x?->address`). Properties: `ExpressionNode $object`, `string $property`. `nodeType`: `nullSafeAccess`.
:::

:::member[MethodCallExpression]
Represents a method call (`$x->getFullName()`). Properties: `ExpressionNode $object`, `string $method`, `array<ExpressionNode> $arguments`. `nodeType`: `methodCall`.
:::

:::member[StaticMethodCallExpression]
Represents a static method call (`Str::lower(...)`). Properties: `string $class`, `string $method`, `array<ExpressionNode> $arguments`. `nodeType`: `staticMethodCall`.
:::

:::member[BinaryExpression]
Represents a binary operation (`$x->age > 18`). Properties: `ExpressionNode $left`, `string $operator`, `ExpressionNode $right`. `nodeType`: `binary`.
:::

:::member[UnaryExpression]
Represents a unary operation (`!$x->isDeleted`). Properties: `string $operator`, `ExpressionNode $operand`, `bool $isPrefix`. `nodeType`: `unary`.
:::

:::member[ConstantExpression]
Represents a literal value (`18`, `'hello'`, `true`, `null`), a class constant (`User::ADULT_AGE`), or a captured variable from the enclosing scope. Properties: `mixed $value`. `nodeType`: `constant`.
:::

:::member[TernaryExpression]
Represents a ternary expression (`$x->a ? $x->b : $x->c`). For the short form `$x->a ?: $x->c`, `$ifTrue` is `null`. Properties: `ExpressionNode $condition`, `?ExpressionNode $ifTrue`, `ExpressionNode $ifFalse`. `nodeType`: `ternary`.
:::

:::member[CoalesceExpression]
Represents a null coalescing expression (`$x->nickname ?? $x->name`). Properties: `ExpressionNode $left`, `ExpressionNode $right`. `nodeType`: `coalesce`.
:::

:::member[ArrayAccessExpression]
Represents an array access (`$x->tags[0]`). Properties: `ExpressionNode $array`, `ExpressionNode $index`. `nodeType`: `arrayAccess`.
:::

:::member[CastExpression]
Represents a type cast (`(string) $x->value`). Properties: `string $targetType`, `ExpressionNode $operand`. `nodeType`: `cast`.
:::

:::member[NewExpression]
Represents a `new` expression (`new Money($x->amount)`). Properties: `string $class`, `array<ExpressionNode> $arguments`. `nodeType`: `new`.
:::

:::member[InstanceofExpression]
Represents an `instanceof` or `is` check (`$x->value is int`, `$x instanceof Address`). Properties: `ExpressionNode $operand`, `string $targetType`. `nodeType`: `instanceof`.
:::

## Expression Tree Compiled PHP Output

When you pass an `fn` expression to an `Expression<callable(T): R>` parameter, the compiler emits node constructors wrapped in a `\Tyhp\Expression`. The tree is built bottom-up: leaf nodes first, then their parents. Node constructors take their members positionally, with the node's `type` string last; the `Expression` itself takes `body`, `parameters`, `callable`, and `returnType`.

```tyhp
<?tyhp

int $minAge = 18;
$query->where(fn ($u) => $u->age > $minAge);
```

```php
<?php

$query->where(\Tyhp\Generic::bind(\Tyhp\Expression::class, null)(
    body: new \Tyhp\Expression\BinaryExpression(
        new \Tyhp\Expression\PropertyAccessExpression(
            new \Tyhp\Expression\ParameterExpression('u', \User::class, 0),
            'age',
            'int'
        ),
        '>',
        new \Tyhp\Expression\ConstantExpression($minAge, 'int'),
        'bool'
    ),
    parameters: [new \Tyhp\Expression\ParameterExpression('u', \User::class, 0)],
    callable: fn(\User $u): bool => $u->age > $minAge,
    returnType: 'bool'
));
```

```tyhp
<?tyhp

$query->where(fn ($u) => $u->getFullName() === 'Ada Lovelace');
```

```php
<?php

$query->where(\Tyhp\Generic::bind(\Tyhp\Expression::class, null)(
    body: new \Tyhp\Expression\BinaryExpression(
        new \Tyhp\Expression\MethodCallExpression(
            new \Tyhp\Expression\ParameterExpression('u', \User::class, 0),
            'getFullName',
            [],
            'string'
        ),
        '===',
        new \Tyhp\Expression\ConstantExpression('Ada Lovelace', 'string'),
        'bool'
    ),
    parameters: [new \Tyhp\Expression\ParameterExpression('u', \User::class, 0)],
    callable: fn(\User $u): bool => $u->getFullName() === 'Ada Lovelace',
    returnType: 'bool'
));
```

## Captured Variables

Variables from the enclosing scope that are referenced in the lambda body become `ConstantExpression` nodes in the expression tree. Their values are read when the expression tree is constructed, at runtime. This enables patterns where runtime values are embedded in the tree. A captured variable must be definitely assigned where the `fn` appears (**TYHP4324**).

```tyhp
<?tyhp

int $minAge = 18;
string $requiredRole = 'admin';

// $minAge and $requiredRole are captured as ConstantExpression nodes
$query->where(fn ($u) => $u->age > $minAge && $u->role == $requiredRole);

// At runtime, the expression tree contains:
// - BinaryExpression(&&)
//   - BinaryExpression(>)
//     - PropertyAccessExpression('age')
//     - ConstantExpression(18)        ← captured $minAge
//   - BinaryExpression(==)
//     - PropertyAccessExpression('role')
//     - ConstantExpression('admin')   ← captured $requiredRole
```

## ExpressionVisitor

The `ExpressionVisitor` abstract class provides a visitor pattern for walking expression trees. Library authors extend `ExpressionVisitor` to build SQL translators, serialization mappers, validation rule generators, and other domain-specific interpreters. `visit()` returns `mixed`, so a translator that composes strings narrows each result before using it.

```tyhp
<?tyhp

use Tyhp\Expression\BinaryExpression;
use Tyhp\Expression\ConstantExpression;
use Tyhp\Expression\ExpressionNode;
use Tyhp\Expression\ExpressionVisitor;
use Tyhp\Expression\PropertyAccessExpression;

class SqlWhereVisitor extends ExpressionVisitor {
    public function visitBinary(BinaryExpression $node): mixed {
        string $left = $this->sql($node->left);
        string $right = $this->sql($node->right);
        return "{$left} {$node->operator} {$right}";
    }

    public function visitPropertyAccess(PropertyAccessExpression $node): mixed {
        return $node->property;
    }

    public function visitConstant(ConstantExpression $node): mixed {
        if ($node->value is string) {
            return "'" . \addslashes($node->value) . "'";
        }
        return \var_export($node->value, true);
    }

    private function sql(ExpressionNode $node): string {
        mixed $result = $this->visit($node);
        return $result is string ? $result : '?';
    }
}

class VisitQuery<T> {
    public function where(Expression<callable(T): bool> $predicate): string {
        $visitor = new SqlWhereVisitor();
        $sql = $visitor->visit($predicate->body);
        return $sql is string ? $sql : '';
    }
}

int $minAge = 18;

echo (new VisitQuery<User>())->where(fn ($u) => $u->age > $minAge), "\n";
echo (new VisitQuery<User>())->where(fn ($u) => $u->firstName === 'Ada'), "\n";
```

Output:

```text
age > 18
firstName === 'Ada'
```

## Multi-Parameter Expressions

Expression trees support multi-parameter lambdas for comparison-style expressions. Write the callable shape on `Expression`: `Expression<callable(T, T): int>` for comparators.

```tyhp
<?tyhp

class SortableList<T> {
    public function sortBy(Expression<callable(T, T): int> $comparator): static {
        echo \count($comparator->parameters), ' ', $comparator->parameters[0]->name, ' ', $comparator->parameters[1]->name, "\n";
        return $this;
    }
}

(new SortableList<User>())->sortBy(fn ($a, $b) => $a->lastName <=> $b->lastName);
// The Expression tree has two ParameterExpression nodes
```

Output:

```text
2 a b
```

## nameof Integration

The `nameof` compile-time function accepts a property-chain arrow function for lightweight, refactoring-safe property name extraction. `nameof` always returns the **last** segment of the chain. Use `PropertyPath` when the full chain is needed.

```tyhp
<?tyhp

string $col = nameof(fn (User $u) => $u->firstName);       // 'firstName'

// Nested paths still yield the last segment:
string $city = nameof(fn (User $u) => $u->address->city);  // 'city'
```

## Expression Serialization

Expression trees can be serialized to JSON using `ExpressionSerializer`. This enables passing expression trees across API boundaries, such as client-side query building sent to a server. The JSON object has `parameters`, `returnType`, and `body` keys.

```tyhp
<?tyhp

use Tyhp\Expression;
use Tyhp\Expression\ExpressionSerializer;

Expression<callable(User): bool> $expr = fn ($u) => $u->age > 18;
string $json = ExpressionSerializer::toJson($expr);
echo $json, "\n";

// Structural equality ignores the compiled closures — two independently
// constructed trees with the same shape compare equal.
bool $same = ExpressionSerializer::equals($expr, $expr);
bool $alsoSame = $expr->equals($expr);
echo $same ? 'true' : 'false', ' ', $alsoSame ? 'true' : 'false', "\n";
```

Output:

```text
{
    "parameters": [
        {
            "name": "u",
            "index": 0,
            "type": "User"
        }
    ],
    "returnType": "bool",
    "body": {
        "nodeType": "binary",
        "type": "bool",
        "operator": ">",
        "left": {
            "nodeType": "propertyAccess",
            "type": "int",
            "property": "age",
            "object": {
                "nodeType": "parameter",
                "type": "User",
                "name": "u",
                "index": 0
            }
        },
        "right": {
            "nodeType": "constant",
            "type": "18",
            "value": 18
        }
    }
}
true true
```

## Type System Integration

Expression trees integrate with the type system as follows:

- `Expression<callable(T): R>` is callable: `$expr($userInstance)` runs the stored closure. `compile()` returns `\Closure<callable(T): R>`.
- An `Expression` can be passed to a PHP function parameter declared `callable`, such as `\array_filter($items, $expr)`.
- An `Expression<callable(T): R>` value can be passed to a `callable(T): R` parameter with the same shape. A `\Closure` parameter accepts any `Expression`-typed argument: the compiler passes its `->callable`, whether the argument is a variable (annotated or inferred) or a call result.
- When a parameter is declared `Expression<callable(T): R>` and you pass an inline `fn`, a generic `R` is inferred from the `fn` body, for example `function select<R>(Expression<callable(Person): R> $selector): R`.
- `PropertyPath<callable(T): R>` is a subtype of `Expression<callable(T): R>`. Code accepting `Expression` also accepts `PropertyPath`.
- An `Expression` value passed to an `Expression` parameter must have the same callable shape; otherwise the argument is rejected with **TYHP4010**.
- When passing a regular `fn` expression to a `callable` or `\Closure` parameter (not `Expression`), the compiler emits a normal closure — no expression tree.
- The parameter type drives the behavior: only `Expression<>` and `PropertyPath<>` parameters trigger expression tree generation.

## Supported Expression Types

The following expressions are supported inside `fn` expressions that target `Expression<callable(T): R>` parameters:

- Property access: `$x->prop`
- Null-safe property access: `$x?->prop`
- Method calls: `$x->method(...)`
- Static method calls: `Class::method(...)`
- Binary operators:
  - arithmetic: `+`, `-`, `*`, `/`, `%`, `**`
  - string concatenation: `.`
  - comparison: `==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`, `<=>`
  - logical: `&&`, `||`, `and`, `or`, `xor`
  - bitwise and shift: `&`, `|`, `^`, `<<`, `>>`
- Unary operators: `!`, `-`, `+`, `~`
- Literals: `int`, `float`, string literals without interpolation, `true`, `false`, `null` (in any case)
- Class constants: `Class::CONST`, and `Class::class`
- Captured variables from the enclosing scope
- Array access: `$x->items[$i]`
- Ternary and short ternary: `$x ? $y : $z`, `$x ?: $y`
- Null coalescing: `$x ?? $y` (a `CoalesceExpression`)
- Type casts: `(string) $x->value`
- `new` expressions: `new Money($x->amount)`
- `instanceof` and `is` checks: `$x->value is int`, `$x instanceof Address`
- Parenthesized sub-expressions

## Unsupported Expression Types

The following expressions produce **TYHP4322** — "Expression trees do not support `<kind>` expressions; simplify the fn body" — when used inside a parsable `fn` expression. The kind appears in the message:

| Expression | Kind in the message |
| --- | --- |
| Function calls: `\strlen($x->name)`, `$callback($x)` | `function call` |
| Assignments, compound assignments (`+=`, `??=`), and destructuring | `assignment` |
| Increment and decrement: `$x->age++`, `--$x->age` | `increment` |
| String interpolation: `"hi {$x->name}"` | `string interpolation` |
| `match` expressions | `match` |
| `throw` expressions | `throw` |
| `await` expressions | `await` |
| `yield` expressions | `yield` |
| Nested `fn` or `function` expressions | `nested fn` |
| Null-safe method calls: `$x?->method()` (property `?->` is supported) | `nullsafe method call` |
| `clone` | `clone` |
| `include` / `require` | `include` |
| `\|>` pipe | `pipe` |
| `new class { ... }` | `anonymous class` |
| `@` error suppression | `error suppression` |
| Dynamic member names: `$x->{$name}` | `dynamic member` |
| Array literals: `[1, 2]`, `[...$x]` | `array literal` |
| First-class callables: `$x->name(...)`, `strlen(...)` | `first-class callable` |
| Shell commands: `` `ls` `` | `shell command` |
| `isset($x->name)` | `isset` |
| `empty($x->name)` | `empty` |
| `nameof(...)` | `nameof` |
| `print` | `print` |
| `exit` | `exit` |

Any other construct that has no tree form is reported by name too, spelled in lower-case words.

A `fn` body is a single expression. A block body, such as `fn ($x) => { return true; }`, is a syntax error.

## Library Author Guide: Type-Safe Query Builder

This example demonstrates how a library author consumes expression trees to build type-safe queries. The query builder accepts `Expression` parameters for conditions and `PropertyPath` parameters for column references.

```tyhp
<?tyhp

use Tyhp\Expression;
use Tyhp\PropertyPath;

class UserQuery<T> {
    /** @var array<Expression<callable(T): bool>> */
    private array $conditions = [];
    private ?string $selectColumn = null;
    private ?string $orderColumn = null;

    public function where(Expression<callable(T): bool> $predicate): static {
        $this->conditions[] = $predicate;
        return $this;
    }

    public function select<R>(PropertyPath<callable(T): R> $selector): static {
        $this->selectColumn = $selector->getPropertyName();
        return $this;
    }

    public function orderBy<R>(PropertyPath<callable(T): R> $prop): static {
        $this->orderColumn = $prop->getPropertyName();
        return $this;
    }

    public function describe(): string {
        return \count($this->conditions) . ' condition(s), select ' . ($this->selectColumn ?? '*') . ', order by ' . ($this->orderColumn ?? '-');
    }
}

// User code — fully type-safe, refactoring-safe
int $minAge = 18;

$people = (new UserQuery<User>())
    ->where(fn ($u) => $u->age > $minAge && $u->isActive)
    ->select(fn ($u) => $u->firstName)
    ->orderBy(fn ($u) => $u->lastName);
echo $people->describe(), "\n";
```

Output:

```text
1 condition(s), select firstName, order by lastName
```

## Using Expression as a Callable

Every `Expression` carries its compiled closure, so it can be called directly. This allows code that receives an `Expression` to either inspect the tree or just execute it.

```tyhp
<?tyhp

use Tyhp\Expression;
use Tyhp\Expression\ExpressionNode;

function process(Expression<callable(User): bool> $predicate, User $user): void {
    // Option 1: Inspect the expression tree
    ExpressionNode $body = $predicate->body;
    echo $body->nodeType, "\n";

    // Option 2: Just call it (delegates to the stored closure)
    bool $result = $predicate($user);
    echo $result ? 'true' : 'false', "\n";

    // Option 3: Get the raw closure
    \Closure<callable(User): bool> $fn = $predicate->compile();
    echo $fn($user) ? 'true' : 'false', "\n";
}

process(fn ($u) => $u->age >= 18, $ada);
```

Output:

```text
binary
true
true
```

## Best Practices

:::tip
Use `PropertyPath<callable(T): R>` for simple property references in ORM column mappings, validation, and serialization configuration. It is lightweight and covers the most common use case.
:::

:::tip
Use `Expression<callable(T): R>` when you need to inspect the full structure of a predicate — comparisons, boolean logic, method calls — such as building SQL WHERE clauses or DSL translators.
:::

:::tip
Extend `ExpressionVisitor` to build domain-specific translators rather than manually type-switching on expression node types.
:::

:::tip
Use `nameof` with a property-chain `fn` for refactoring-safe property name extraction instead of hardcoded strings.
:::

:::tip
Every `Expression` carries its compiled callable. Design your API to accept `Expression<callable(T): R>` even if you sometimes just want to execute it — the caller can pass an `fn` expression and the library can either inspect or call it.
:::

## Common Mistakes

:::danger
Don't use parsable lambdas for regular callbacks where you only need to execute the function. Expression trees have construction overhead — use `callable` or `\Closure` when you don't need to inspect the tree.
:::

:::danger
Don't pass non-`fn` arguments to `PropertyPath` parameters, or anything other than an inline `fn` or an existing `Expression` value to `Expression` parameters. Passing a variable that holds a plain closure produces **TYHP4320** (for `PropertyPath`) or **TYHP4323** (for `Expression`).
:::

:::danger
Don't use unsupported constructs (function calls, assignments, `match`, `await`, string interpolation) inside parsable `fn` expressions. Expression trees only support single-expression bodies made of the node types listed above.
:::

:::danger
Don't pass method calls or binary expressions to a `PropertyPath` parameter — `PropertyPath` only supports simple property access chains (`fn ($x) => $x->a->b`). Use `Expression` for more complex expressions.
:::

```tyhp
<?tyhp

function findColumn(PropertyPath<callable(User): string> $prop): string {
    return $prop->getPropertyName();
}

// OK — inline fn expression
findColumn(fn ($u) => $u->firstName);

// ERROR — not an inline fn expression
// $myFn = fn (User $u): string => $u->firstName;
// findColumn($myFn);  // TYHP4320

// ERROR — not a property chain
// findColumn(fn ($u) => $u->getFullName());  // TYHP4321

// OK — use Expression for method calls
function findExpr(Expression<callable(User): string> $expr): string {
    return $expr->body->nodeType;
}
echo findExpr(fn ($u) => $u->getFullName());  // methodCall
```

## Compiler Errors

- **TYHP4320**: Parameter of type `PropertyPath<callable(T): R>` requires an inline fn expression — reported when a non-`fn` argument, including an `Expression` value, is passed to a `PropertyPath` parameter.
- **TYHP4321**: `PropertyPath` expression must be a simple property access chain — reported when the `fn` body contains method calls, operators, literals, array access, or other non-property-access expressions in a `PropertyPath` context.
- **TYHP4322**: Expression trees do not support `<kind>` expressions — reported when an unsupported expression (see the table above) is used in an `Expression` `fn` body.
- **TYHP4323**: Parameter of type `Expression<callable(T): R>` requires an inline fn expression — reported when an argument that is neither an inline `fn` nor an `Expression` value (a plain closure variable, a `function` closure, `null`) is passed to an `Expression` parameter.
- **TYHP4324**: Captured variable `$name` in expression tree must be definitely assigned — reported when a captured variable may not be initialized where the `fn` appears.
- **TYHP4010**: Argument of type `Expression<callable(A): B>` is not assignable to parameter of type `Expression<callable(C): D>` — reported when an `Expression` value of a different callable shape is passed.
