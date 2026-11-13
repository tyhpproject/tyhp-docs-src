---
title: 'Rhetoric: Querying'
---

`Table<T>` extends `Query<T>`. Each builder method returns a new query and does not hit the database. A terminal method runs it. Predicates, orderings, and projections are inline `fn` lambdas. Captured variables become bound parameters.

`all(): array<T>` is the typed list. `get(): Collection<int, T>` is the Laravel collection of the same rows. An untranslatable `where` or `orderBy` throws `Tyhp\Rhetoric\Query\QueryTranslationException`. A `select` the translator cannot turn into columns runs in PHP after the rows load.

The nodes and methods the translator accepts are listed in the [translation reference](rhetoric_translation.md). PHP callers build the same trees with `\Tyhp\Expression::of` and `\Tyhp\Expr`; see [Querying for PHP](rhetoric_php_querying.md).

## Filters, order, and pages

```tyhp
<?tyhp

int $minRating = 3;

array<Post> $posts = $db->posts
    ->where(fn ($post) => $post->rating >= $minRating && $post->title->startsWith('Tyhp'))
    ->orderByDesc(fn ($post) => $post->publishedAt)
    ->thenBy(fn ($post) => $post->id)
    ->skip(20)
    ->take(10)
    ->all();

?Post $post = $db->posts->where(fn ($post) => $post->slug === $slug)->first();
Post $only = $db->posts->where(fn ($post) => $post->slug === $slug)->sole();
```

`first()` is `null` when the query has no row, including `take(0)->first()`. `firstOrFail()` throws `Illuminate\Database\RecordsNotFoundException` when it has none. `sole()` throws when the result is not exactly one row. `take(1)->sole()` reads one row.

`orderBy` and `orderByDesc` replace the order list. `thenBy` and `thenByDesc` append. `latest()` and `oldest()` with no argument order by the timestamp column; pass a lambda to order by that property instead.

`skip` and `take` apply before `count`, `sum`, `min`, `max`, `avg`, `exists`, `doesntExist`, and `every`. `skip` without `take` is sent to SQLite and MySQL.

`paginate($perPage, $pageName, $page, $total)` returns `LengthAwarePaginator<int, T>`. `simplePaginate` returns `Paginator<int, T>`. `cursorPaginate($perPage, $cursorName, $cursor)` returns `CursorPaginator<int, T>`. Cursor pagination orders by the key as a tie-break, stores column values in the cursor, and returns an empty page when the page offset does not fit an integer. It reads mapped models, so it rejects a `select` projection and a `union` / `intersect` / `except` query. A page that has no `orderBy` uses the primary key.

Comparisons follow PHP's null rules. `$post->url !== 'a'` and `!($post->url === 'a')` match rows whose `url` is `NULL`. `every(fn)` fails when the predicate is unknown for a row.

## Shape of the query

| Method | Role |
| --- | --- |
| `where(fn ($row): bool => ...)` | `AND` the predicate |
| `withoutGlobalScopes()` | Drop global scopes for this query |
| `withTrashed()` / `onlyTrashed()` | Soft-deleted rows. Requires `#[SoftDeletes]` |
| `distinct()` | `SELECT DISTINCT` |
| `tag(string $comment)` | SQL comment. The comment cannot open a nested comment on PostgreSQL |
| `lockForUpdate()` / `sharedLock()` | Row lock |
| `fromRaw(string $sql, array $bindings = [])` | Replace the `FROM` clause. Bindings stay parameters |
| `untracked()` | Do not put rows in the identity map |
| `untrackedWithIdentity()` | Skip tracking but still return the instance already in the map |
| `toSql()` / `toRawSql()` / `bindings()` | The statement. `toRawSql()` inlines every binding, including `LIKE` and a tag |

`where` after `select` is rejected when the lambda parameter is not the source model.

A property path through a relation (`fn ($post) => $post->blog->name === 'News'`) becomes a join. `join` and `leftJoin` take another query, the two keys, and a result lambda. The other query may only have `where` filters. `groupBy` returns `Query<Group<T>>`. `Group<T>::$key` is the grouped value; `count()`, `sum`, `min`, `max`, and `avg` on that group are translated and are not computed in PHP. `having` filters groups. `count()` and `exists()` on a grouped query count and test the groups.

`union`, `unionAll`, `intersect`, and `except` combine left to right. `orderBy`, `skip`, `take`, `first`, `count`, `exists`, and the aggregates then read the combined rows.

## Aggregates and existence

```tyhp
int $count = $db->posts->where(fn ($post) => $post->rating > 4)->count();
bool $any = $db->posts->where(fn ($post) => $ids->contains($post->id))->exists();
bool $all = $db->posts->every(fn ($post) => $post->rating > 0);
int|float $sum = $db->posts->sum(fn ($post) => $post->rating);
```

`count()` is `COUNT(*)`. `exists()` and `doesntExist()` test whether the query has a row. None of the three takes an argument; narrow the query with `where` first. `every(fn)` takes a predicate. `min` and `max` return `int|float|string|null`. `avg` returns `?float`. An array `contains` becomes `IN (...)`. One value becomes `=`.

`select` projects a constructor call or an array. The column list is the translated arguments.

```tyhp
array<PostSummary> $rows = $db->posts
    ->select(fn ($post) => new PostSummary($post->id, $post->title, $post->blog->name))
    ->all();
```

## Loading relations

`with(fn ($post) => $post->blog)` eager-loads that navigation. An optional `constrain` predicate filters the related query. `thenWith` continues from the previous include. Each relation is a separate query, and the instances come from the identity map. `singleQuery()` loads the includes in the same statement. `singleQuery()` together with `first`, `sole`, `skip`, or `take` switches back to one query per relation so each parent keeps all of its children.

```tyhp
$db->load($post, fn ($post) => $post->blog);
$db->loadMissing($post, fn ($post) => $post->comments);
```

`load` always queries. `loadMissing` queries when that navigation is not already loaded. A collection's `count()` or `exists()` in a predicate is a subquery, including `exists(fn)` and `countWhere(fn)` from the array extensions Rhetoric adds.

## Identity, chunks, and lazy rows

`find($id)` and `findOrFail($id)` return the tracked instance when that key is already loaded. A model removed from the tracker but not yet saved is missing (`find` returns `null`). String keys such as `'007'` and `'7'` stay distinct. `find` applies the discriminator, the soft-delete filter, and global scopes.

`reference($id)` returns the model for that key and does not query until a property other than the key is read. The first such read loads every pending model of that class. `#[Deferred]` columns are omitted from the original `SELECT` and filled, with the other pending models of that class, on first access. A changed deferred column saves without loading the rest.

Lazy loads are off until `lazyLoading(true)`. `preventLazyLoading()` makes that access throw and leaves the model unloaded. `close()` makes a later load throw. Touching a lazy model after the context that created it is gone throws; it does not use a dead connection.

`cursor()` yields one row at a time. `lazy(int $count = 1000)` yields in chunks of that size. `chunk` and `chunkById` call you with each `array<T>` and stop when the callback returns `false`. These follow `untracked()` / `untrackedWithIdentity()`. `Query::lazy` is this generator. It is unrelated to `lazyLoading()`.

## Bulk writes

These statements do not change the tracker. They throw when the query has `skip`, `take`, `distinct`, `groupBy`, `having`, `join`, or a set operation.

```tyhp
int $deleted = $db->posts->where(fn ($post) => $post->deletedAt !== null)->delete();
int $bumped = $db->posts->where(fn ($post) => $post->blogId === $blogId)->increment(fn ($post) => $post->rating);
int $updated = $db->posts
    ->where(fn ($post) => $post->blogId === $blogId)
    ->update(fn (Assignments<Post> $set) => $set->assign(
        fn ($post) => $post->rating,
        fn ($post) => $post->rating + 1,
    ));
```

`decrement` subtracts. On a soft-delete model, `delete()` sets `deleted_at` and `restore()` clears it. `Context::restore($model)` does that for one tracked instance.

## Eloquent models

`EloquentQuery::query<Article>()` and `EloquentQuery::on<Article>($connection)` run a typed `where` and `orderBy` through that Eloquent model's builder and return the Eloquent model. The column is the `Column` attribute, or the property name in snake case. `get()` returns an `Eloquent\Collection`. `first()` returns `?T`. `builder()` is the Eloquent builder after the typed clauses. This requires PHP 8.4 or newer, so a typed property can read and write the attribute. `rhetoric:scaffold --eloquent` writes those properties. See [Laravel integration](rhetoric_laravel.md).

## Raw SQL on the context

```tyhp
array<Post> $rows = $db->select<Post>('select * from posts where id = ?', [1]);
bool $ok = $db->statement('update posts set rating = rating + 1 where id = ?', [1]);
int $affected = $db->affectingStatement('delete from posts where id = ?', [1]);
int $written = $db->transaction<int>(function () use ($db): int {
    return $db->save();
});
```

`transaction` takes a closure and an optional attempt count.
