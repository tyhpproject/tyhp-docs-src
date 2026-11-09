---
title: 'Rhetoric: Translation Reference'
---

A `where`, `orderBy`, `select`, `join` key, or `update` assignment is an expression tree. `Tyhp\Rhetoric\Query\Translator` turns that tree into SQL and a list of bindings. The SQL is for MySQL, MariaDB, PostgreSQL, and SQLite. A repeated query reuses the translated statement. An untranslatable `where` or `orderBy` throws `Tyhp\Rhetoric\Query\QueryTranslationException`. A `select` that cannot be translated runs in PHP after the rows load.

`EloquentQuery` uses a smaller translator. It is listed at the end of this page.

Captured variables and literals are bound parameters. They are not concatenated into the SQL. `null` compared with `===` / `!==` follows PHP: a comparison with `null` is `IS NULL` or `IS NOT NULL`, and `$column !== 'a'` keeps the row when the column is `NULL`.

## Nodes

| Node | SQL |
| --- | --- |
| Property access `$post->rating` | The mapped column, qualified by the query's alias |
| Null-safe access `$post->blog?->name` | The same column or join. A null-safe method call is nullable |
| Property path through a relation `$post->blog->name` | A join to that table |
| A property of the context object captured in the lambda | One bound parameter. The value is read from that context when the query runs |
| `&&`, `and`, `\|\|`, `or` | `AND` / `OR`, parenthesized |
| `===`, `==` | `=` , or `IS NULL` when either side is `null`. Strict `===` between two nullable columns also matches when both are `NULL` |
| `!==`, `!=` | `<>`, or `IS NOT NULL`. A nullable column `!==` a value stays true when the column is `NULL` |
| `>`, `>=`, `<`, `<=` | The same operator |
| `+`, `-`, `*`, `/`, `%` | The same operator |
| `.` (string concatenation) | `CONCAT` on MySQL and MariaDB, `\|\|` on PostgreSQL and SQLite |
| Prefix `!` | Negation. A nullable predicate is false when it is unknown, matching PHP |
| Prefix `-` | Arithmetic negation |
| Prefix `+` | The operand |
| Ternary `$c ? $a : $b` | `CASE WHEN c THEN a ELSE b END` |
| `$a ?? $b` | `COALESCE(a, b)` |
| `(int)`, `(integer)`, `(bool)`, `(boolean)` | `CAST` to `SIGNED` on MySQL and MariaDB, `INTEGER` otherwise |
| `(float)`, `(double)` | `DOUBLE` on MySQL and MariaDB, `DOUBLE PRECISION` on PostgreSQL, `REAL` on SQLite |
| `(string)` | `CHAR` on MySQL and MariaDB, `TEXT` on PostgreSQL and SQLite |
| `instanceof` / `is` against a mapped type | The discriminator column, including subclasses. A check that the row's type already satisfies is `1 = 1` |
| Constant, including a captured variable | `?` plus the value. `null` is SQL `NULL` with no binding |
| Nested `fn` passed to a collection `exists` or `countWhere`, or to a group aggregate | The body, correlated to the outer row |
| Array literal or captured array as the receiver of `contains` | `IN (?)` or `=` when the list has one value. An empty list is `0 = 1` |
| `new Type(...)` inside `select` | One column per constructor argument |
| Array literal inside `select` | One column per element |

## Instance methods

Names are matched without regard to case. `startsWith` in source is `startswith` here.

| Call | SQL |
| --- | --- |
| `$text->contains($needle)` | `LIKE` with the needle between `%`. `\`, `%`, and `_` in the needle are escaped |
| `$text->startsWith($prefix)` | `LIKE` with the prefix and a trailing `%`, escaped the same way |
| `$text->endsWith($suffix)` | `LIKE` with a leading `%` and the suffix |
| `$text->toLower()` | `LOWER` |
| `$text->toUpper()` | `UPPER` |
| `$text->trim()` | `TRIM`. One string argument is the characters to trim: `TRIM(BOTH ? FROM col)` except SQLite, which uses `TRIM(col, ?)` |
| `$text->length()` | `CHAR_LENGTH`. SQLite uses `LENGTH` |
| `$ids->contains($post->id)` | `IN` or `=` |
| `$jsonColumn->contains($value)` on a JSON column | `JSON_CONTAINS` on MySQL and MariaDB, `@>` on PostgreSQL, `json_each` on SQLite |
| `$group->count()` | `COUNT(*)` |
| `$group->sum($selector)`, `min`, `max`, `avg` | That function around the selector. `avg` is a float |
| A collection `count()` or `exists()`, including `exists(fn)` and `countWhere(fn)` | A correlated subquery |

`contains`, `startsWith`, and `endsWith` take one string constant (a captured string is a constant in the tree).

## `Sql` methods

`Tyhp\Rhetoric\Query\Sql` methods are translated. Calling them in PHP outside a query runs the PHP body (`like` is a regular expression, the date parts use `DateTimeImmutable`). Inside a query they become SQL.

| Call | SQL |
| --- | --- |
| `Sql::like($value, $pattern)` | `LIKE`, both sides translated. The pattern is the caller's pattern |
| `Sql::raw($sql)` | The string constant, with no bindings |
| `Sql::dateDiff($start, $end)` | Whole calendar days from start to end. MySQL and MariaDB use `DATEDIFF(end, start)`. PostgreSQL subtracts the two dates. SQLite uses `julianday` of each date |
| `Sql::year($value)`, `month`, `day` | `YEAR` / `MONTH` / `DAY` on MySQL and MariaDB. `EXTRACT` on PostgreSQL. `strftime` on SQLite |
| `Sql::abs($value)` | `ABS` |
| `Sql::floor($value)` | `FLOOR` |
| `Sql::ceiling($value)` | `CEIL` |
| `Sql::round($value)` | `ROUND`. A second argument is the precision. PostgreSQL casts the value to `NUMERIC` first |
| `Sql::fn($name, ...$args)` | The SQL registered for `$name` on the current driver |

## Registering a function

`Sql::fn` looks up a name on `Tyhp\Rhetoric\Query\MethodTranslatorRegistry`. You register one name and the SQL for each driver. `{0}`, `{1}`, … are the arguments after the name, in order. Every argument has to appear once.

```tyhp
<?tyhp

use Tyhp\Rhetoric\Query\MethodTranslatorRegistry;
use Tyhp\Rhetoric\Query\Sql;

MethodTranslatorRegistry::shared()->registerFunction('soundex', [
    'mysql' => 'soundex({0})',
    'mariadb' => 'soundex({0})',
    'pgsql' => 'soundex({0})',
    'sqlite' => 'soundex({0})',
    'sqlsrv' => 'soundex({0})',
]);

array<Post> $posts = $db->posts
    ->where(fn ($post) => Sql::fn('soundex', $post->title) === 'T310')
    ->all();
```

`register(string $method, Closure $translate)` replaces an instance-method translation. `registerStatic(string $class, string $method, Closure $translate)` replaces a static call. The closure receives the `Translator` and the call node and returns a `SqlPiece`. `clear()` drops the shared registry so the next `shared()` seeds the built-in methods again.

`Sql::fn` inside a Tyhp lambda is the registration above. The PHP form is in [the PHP translation reference](rhetoric_php_translation.md).

## Eloquent queries

`EloquentQuery` translates `where` and `orderBy` into calls on `Eloquent\Builder`. `orderBy` is one column of that model. `where` accepts `AND` / `OR`, prefix `!`, the comparisons in the table above, `null` checks (`whereNull` / `whereNotNull`), `contains` on a list (`whereIn` / `whereNotIn`), and `contains` / `startsWith` / `endsWith` on a string column (`LIKE` with `%`, `_`, and `\` escaped). A nullable column `!==` a value is `<>` or `NULL`, matching PHP.
