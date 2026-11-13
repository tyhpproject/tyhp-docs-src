---
title: 'Rhetoric for PHP: Querying'
---

A table from your context is a query. Methods such as `where` and `orderBy` return a new query and do not run it. `all()`, `first()`, `count()`, and the other terminal methods run it.

Build a predicate with `\Tyhp\Expression::of`, described in [Getting started](rhetoric_php_getting_started.md). A value you pass to `gte`, `same`, or `eq` is a bound parameter, including a PHP variable. `all()` returns a list of models. `get()` returns an `Illuminate\Support\Collection` of those models.

An untranslatable `where` or `orderBy` throws `\Tyhp\Rhetoric\Query\QueryTranslationException`. The accepted trees are in the [translation reference](rhetoric_php_translation.md).

## Filters, order, and one row

```php
$minRating = 3;
$posts = $db->posts()
    ->where(\Tyhp\Expression::of(\App\Data\Post::class)->rating->gte($minRating))
    ->where(\Tyhp\Expr::param('post', \App\Data\Post::class)->title->call('startsWith', 'Tyhp'))
    ->orderByDesc(\Tyhp\Expression::of(\App\Data\Post::class)->publishedAt)
    ->skip(20)
    ->take(10)
    ->all();

$post = $db->posts()
    ->where(\Tyhp\Expression::of(\App\Data\Post::class)->slug->same($slug))
    ->first();
```

`where` adds an `AND`. Call it again to add another condition, or build both parts on `\Tyhp\Expr` (`and()` returns to the parameter, then `call` is legal):

```php
\Tyhp\Expr::param('post', \App\Data\Post::class)
    ->rating->gte($minRating)
    ->and()->title->call('startsWith', 'Tyhp');
```

`Expression::of(...)->title` is only a property path. `first()` returns `null` when there is no row. `firstOrFail()` throws `\Illuminate\Database\RecordsNotFoundException`. `sole()` throws unless the query has exactly one row.

`orderBy` and `orderByDesc` set the order. `thenBy` and `thenByDesc` append. `latest()` and `oldest()` with no argument use the timestamp column; pass `\Tyhp\Expression::of(Post::class)->publishedAt` to order by that property.

`skip` and `take` apply before `count`, `sum`, `min`, `max`, `avg`, `exists`, `doesntExist`, and `every`.

`paginate($perPage, $pageName, $page, $total)` returns a length-aware Laravel paginator. `simplePaginate` returns a simple paginator. `cursorPaginate($perPage, $cursorName, $cursor)` returns a cursor paginator. The cursor orders by the key to break ties and returns an empty page when the offset does not fit an integer. Cursor pagination rejects a projection and a `union`, `intersect`, or `except`.

Comparisons follow PHP's null rules. `Expression::of(Post::class)->url->notSame('a')` matches rows where `url` is `NULL`.

## The rest of the builder

`withoutGlobalScopes()` drops global scopes. `withTrashed()` and `onlyTrashed()` include soft-deleted rows on a model mapped with `#[SoftDeletes]`. `distinct()`, `tag($comment)`, `lockForUpdate()`, `sharedLock()`, and `fromRaw($sql, $bindings)` shape the statement. `tag` cannot open a nested comment on PostgreSQL. `untracked()` leaves rows out of the identity map. `untrackedWithIdentity()` still returns an instance the map already holds. `toSql()`, `toRawSql()`, and `bindings()` inspect the statement. `toRawSql()` inlines bindings.

`join` and `leftJoin` take another query, the outer key, the inner key, and a result expression. The other query may only contain `where` calls. `groupBy` groups by a property path. On the grouped row, `count`, `sum`, `min`, `max`, and `avg` are SQL. `having` filters groups. `union`, `unionAll`, `intersect`, and `except` combine left to right; later `orderBy`, `skip`, `take`, and aggregates read the combined rows.

A path such as `\Tyhp\Expression::of(Post::class)->blog->name` becomes a join.

## Aggregates

```php
$count = $db->posts()->where(\Tyhp\Expression::of(\App\Data\Post::class)->rating->gt(4))->count();
$found = $db->posts()->where(
    \Tyhp\Expr::literal($ids)->call('contains', \Tyhp\Expr::param('post', \App\Data\Post::class)->id),
)->exists();
```

`count()` is `COUNT(*)`. `exists()` and `doesntExist()` test whether the query has a row. None of the three takes an argument; narrow the query with `where` first. `sum`, `min`, `max`, and `avg` take a property expression. `every` takes a predicate and fails when a row makes the predicate unknown.

`select` takes the projected type, then the expression that builds the value: `select(\App\Data\PostSummary::class)($projection)`. When that tree cannot be translated, Rhetoric loads the rows and runs the projection in PHP.

## Relations, chunks, and lazy rows

```php
$posts = $db->posts()
    ->with(\Tyhp\Expression::of(\App\Data\Post::class)->blog)
    ->all();

$db->load($post, \Tyhp\Expression::of(\App\Data\Post::class)->blog);
$db->loadMissing($post, \Tyhp\Expression::of(\App\Data\Post::class)->comments);
```

`with` accepts a second `constrain` expression that filters the related query. `thenWith` continues the previous include. Each relation is its own query unless you call `singleQuery()`. `singleQuery()` with `first`, `sole`, `skip`, or `take` uses one query per relation so each parent keeps its children.

`find($id)` returns the tracked instance when that key is loaded, and `null` when the model was removed but not saved. `findOrFail` throws when the row is missing. Both apply the discriminator, soft-delete filter, and global scopes.

`reference($id)` returns the model and waits to query until a property other than the key is read. That read loads every pending model of the class. A `#[Deferred]` column is omitted until it is read. Call `$db->lazyLoading(true)` before relying on that load. `$db->preventLazyLoading()` makes the access throw and leaves the model unloaded. `$db->close()` makes a later load throw.

`cursor()` yields one model at a time. `lazy(1000)` yields chunks of that size. `chunk` and `chunkById` pass each list to a callback and stop when the callback returns `false`. `lazy` here is the chunk generator.

## Bulk statements

`update`, `delete`, `increment`, and `decrement` do not use the tracker. They throw when the query has `skip`, `take`, `distinct`, `groupBy`, `having`, a join, or a set operation.

```php
$updated = $db->posts()
    ->where(\Tyhp\Expression::of(\App\Data\Post::class)->blogId->same($blogId))
    ->update(function (\Tyhp\Rhetoric\Query\Assignments $set): void {
        $set->assign(
            \Tyhp\Expression::of(\App\Data\Post::class)->rating,
            \Tyhp\Expr::param('post', \App\Data\Post::class)->rating->plus(1),
        );
    });
```

`increment` and `decrement` take the column expression and an optional amount. On a soft-delete model, `delete()` sets `deleted_at` and `restore()` clears it.

## Eloquent models

On PHP 8.4 or newer, `\Tyhp\Rhetoric\EloquentQuery` runs a typed `where` and `orderBy` on an existing Eloquent model and returns that model:

```php
$articles = \Tyhp\Rhetoric\EloquentQuery::query(\App\Models\Article::class)()
    ->where(\Tyhp\Expression::of(\App\Models\Article::class)->title->same('Tyhp'))
    ->orderByDesc(\Tyhp\Expression::of(\App\Models\Article::class)->rating)
    ->get();
```

`on` takes the model, then the connection:

```php
$onMysql = \Tyhp\Rhetoric\EloquentQuery::on(\App\Models\Article::class)('mysql');
```

`first()` returns the model or `null`. `builder()` is the Eloquent builder. A property's column is its `Column` attribute, or the property name in snake case. `php artisan rhetoric:scaffold --eloquent` writes properties that read and write attributes. See [Laravel integration](rhetoric_php_laravel.md).

## Raw SQL

`select` on the context takes the row type, then the SQL and a list of bindings. `transaction` takes the closure's return type, then the closure:

```php
use Tyhp\Type as T;

$rows = $db->select(\App\Data\Post::class)(
    'select * from posts where id = ?',
    [1],
);
$db->statement('update posts set rating = rating + 1 where id = ?', [1]);
$affected = $db->affectingStatement('delete from posts where id = ?', [1]);
$written = $db->transaction(T::int)(
    function () use ($db): int {
        return $db->save();
    },
);
```
