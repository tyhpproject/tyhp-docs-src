---
title: 'Rhetoric for PHP: Translation Reference'
---

`where`, `orderBy`, join keys, and `update` assignments take an expression tree. `select` takes the projected type, then that tree: `select(\App\Data\PostSummary::class)($projection)`. Rhetoric turns that tree into SQL and bindings for MySQL, MariaDB, PostgreSQL, and SQLite. Build the tree with `\Tyhp\Expression::of` for a property or a comparison, and with `\Tyhp\Expr` when you need a method call. Both are in [Getting started](rhetoric_php_getting_started.md).

A value passed to `gte`, `same`, `eq`, or `literal` is a bound parameter. `null` uses SQL `NULL`. Comparisons follow PHP: `same` and `eq` are `===`, `notSame` and `neq` are `!==`, and a nullable column compared with `notSame` still matches when the column is `NULL`.

An untranslatable `where` or `orderBy` throws `\Tyhp\Rhetoric\Query\QueryTranslationException`. A `select` that cannot be translated runs in PHP after the rows load. The same query shape reuses its translated SQL.

## Nodes

| In the tree | How you write it from PHP | SQL |
| --- | --- | --- |
| Property | `\Tyhp\Expression::of(Post::class)->rating` | Mapped column |
| Null-safe property | `\Tyhp\Expr::param('post', Post::class)->blog->nullSafe()->name` | Same column or join. The result is nullable |
| Relation path | `\Tyhp\Expression::of(Post::class)->blog->name` | Join |
| `&&` / `\|\|` | `->and()` / `->or()` on the builder | `AND` / `OR` |
| `>=`, `>`, `<=`, `<` | `gte`, `gt`, `lte`, `lt` | The same operator |
| `===` | `same` or `eq` | `=` or `IS NULL`. Two nullable columns with `===` also match when both are `NULL` |
| `!==` | `notSame` or `neq` | `<>` or `IS NOT NULL`, and a nullable column `!==` a value keeps `NULL` rows |
| `==` / `!=` | `\Tyhp\Expr` `looseEq` / `looseNeq` | `=` / `<>` with the null rules for loose comparison |
| `+` `-` `*` `/` `%` | `\Tyhp\Expr` `plus`, `minus`, `times`, `dividedBy`, `mod` | The same operator |
| Concatenation | `\Tyhp\Expr` `concat` | `CONCAT` on MySQL and MariaDB, `\|\|` on PostgreSQL and SQLite |
| Prefix `!` `-` `+` | `not()`, `neg()`, `pos()` | Negation treats unknown as false. Minus wraps the operand. Plus is the operand |
| Ternary | `then()` / `else()` | `CASE WHEN … THEN … ELSE … END` |
| `??` | `coalesce()` | `COALESCE` |
| Cast | `cast('int')`, `cast('float')`, `cast('string')` | `CAST`. Integers and bools are `SIGNED` on MySQL and MariaDB and `INTEGER` otherwise. Floats are `DOUBLE`, `DOUBLE PRECISION`, or `REAL`. Strings are `CHAR` or `TEXT` |
| `instanceof` | `is(Cat::class)` on a mapped property | Discriminator `IN` list, including subclasses |
| Constant | the argument to `gte` / `same`, or `Expr::literal` | `?`. `null` is SQL `NULL` |
| `contains` on an array | `Expr::literal($ids)->call('contains', $idExpr)` | `IN` or `=`. An empty list is `0 = 1` |
| `new` inside a projection | the `select` tree's constructor call | One selected column per argument |

`Expression::of(...)->age->gte(18)->and()->isActive->same(true)` is the comparison form. Method calls, arithmetic, `not()`, `neg()`, `pos()`, `then()`, `else()`, and `coalesce()` are `\Tyhp\Expr`.

## Instance methods

`call('contains', $needle)` and the names below are matched without regard to case.

| `call` name | SQL |
| --- | --- |
| `contains` on a string | `LIKE` with `%` around the needle. `\`, `%`, and `_` are escaped |
| `startsWith` | `LIKE` prefix |
| `endsWith` | `LIKE` suffix |
| `toLower` | `LOWER` |
| `toUpper` | `UPPER` |
| `trim` | `TRIM`. A string argument is the character list (`TRIM(BOTH ? FROM col)`, or `TRIM(col, ?)` on SQLite) |
| `length` | `CHAR_LENGTH`, or `LENGTH` on SQLite |
| `contains` on an array or list | `IN` |
| `contains` on a JSON column | `JSON_CONTAINS` on MySQL and MariaDB, `@>` on PostgreSQL, `json_each` on SQLite |
| `count`, `sum`, `min`, `max`, `avg` on a grouped query | That aggregate. `sum` / `min` / `max` / `avg` take a selector expression |

A collection `count()` or `exists()` in a predicate, including `exists` with a nested predicate and `countWhere`, is a correlated subquery.

```php
$posts = $db->posts()->where(
    \Tyhp\Expr::param('post', \App\Data\Post::class)->title->call('startsWith', 'Tyhp'),
)->all();
```

## `Sql` methods

Inside a query, `\Tyhp\Rhetoric\Query\Sql` is translated. Build the call with `staticCall`:

```php
\Tyhp\Expr::param('post', \App\Data\Post::class)->staticCall(
    \Tyhp\Rhetoric\Query\Sql::class,
    'year',
    \Tyhp\Expr::param('post', \App\Data\Post::class)->publishedAt,
);
```

| Method | SQL |
| --- | --- |
| `like` | `LIKE` of the two arguments |
| `raw` | The SQL string as written, with no bindings |
| `dateDiff` | Whole days from the first argument to the second. `DATEDIFF` on MySQL and MariaDB, date subtraction on PostgreSQL, `julianday` on SQLite |
| `year`, `month`, `day` | `YEAR` / `MONTH` / `DAY`, or `EXTRACT`, or `strftime` |
| `abs`, `floor` | `ABS`, `FLOOR` |
| `ceiling` | `CEIL` |
| `round` | `ROUND`. The second argument is precision. PostgreSQL casts to `NUMERIC` first |
| `fn` | Your registration. See below |

## Registering a function

`MethodTranslatorRegistry::registerFunction` maps one name to a SQL string per driver. `{0}` and `{1}` are the arguments of `Sql::fn` after the name. Each argument is used once. Drivers you can name: `mysql`, `mariadb`, `pgsql`, `sqlite`, `sqlsrv`.

```php
\Tyhp\Rhetoric\Query\MethodTranslatorRegistry::shared()->registerFunction('soundex', [
    'mysql' => 'soundex({0})',
    'mariadb' => 'soundex({0})',
    'pgsql' => 'soundex({0})',
    'sqlite' => 'soundex({0})',
    'sqlsrv' => 'soundex({0})',
]);

$match = \Tyhp\Expr::param('post', \App\Data\Post::class)->staticCall(
    \Tyhp\Rhetoric\Query\Sql::class,
    'fn',
    'soundex',
    \Tyhp\Expr::param('post', \App\Data\Post::class)->title,
)->same('T310');

$posts = $db->posts()->where($match)->all();
```

`register($method, $closure)` and `registerStatic($class, $method, $closure)` replace a built-in. The closure is `function (\Tyhp\Rhetoric\Query\Translator $translator, $call): \Tyhp\Rhetoric\Query\SqlPiece`. `clear()` drops the registry; the next `shared()` loads the built-ins again.

## Eloquent queries

`EloquentQuery` translates `where` and `orderBy` only. `orderBy` is one column. `where` accepts `and` / `or`, `not`, the comparisons above, null checks, `contains` on a list (`whereIn`), and `contains` / `startsWith` / `endsWith` on a string (`LIKE`, with `%`, `_`, and `\` taken literally). Bind the query as in [Querying](rhetoric_php_querying.md).
