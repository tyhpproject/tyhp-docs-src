---
title: 'Rhetoric for PHP: Coming from EF Core'
---

Rhetoric is a unit of work and a typed query layer on top of Laravel's database connection. You call it from PHP. The names in the package are the ones in this table. `all()` returns a list of models. `get()` returns an `Illuminate\Support\Collection` of the same rows.

Generic classes are `ContextFactory::new(\App\Data\BlogContext::class)()`. Methods that need a type you pass take it first, as in `table(Post::class)()` and `$db->select(Post::class)($sql, $bindings)`. `entry($model)` and `\Tyhp\Expression::of(Post::class)->rating->gte(3)` are ordinary calls. Both shapes are introduced in [Getting started](rhetoric_php_getting_started.md).

| Concept | EF Core | Rhetoric | Laravel |
| --- | --- | --- | --- |
| Unit of work | `DbContext` | `\Tyhp\Rhetoric\Context` | The context's `$connection` is a name from `config/database.php` |
| Queryable set | `DbSet<T>` | `\Tyhp\Rhetoric\Table`, from `table(Post::class)()` | `DB::table()` is untyped |
| Mapped class | entity | a plain PHP class (a Rhetoric model) | Eloquent model. `EloquentQuery` queries that model and returns it |
| Mapping metadata | `IEntityType` | `\Tyhp\Rhetoric\Mapping\ContextMap` and `ModelMap` | |
| Fluent configuration | `ModelBuilder`, `EntityTypeBuilder<T>` | `Mapper`, `ModelMapper` | |
| Per-model configuration | `IEntityTypeConfiguration<T>` | the `ModelMapper` from `$map->model(Post::class)()` in `map()` | |
| Configuration hook | `OnModelCreating` | `map(Mapper $map)` on the context | |
| Change tracker | `ChangeTracker` | `$db->tracker` | |
| Tracked handle | `EntityEntry` | `TrackedEntry` from `$db->entry($model)` | |
| State | `EntityState` | `\Tyhp\Rhetoric\Tracking\TrackingState`: `Added`, `Clean`, `Dirty`, `Deleted`, `Untracked` | |
| Save | `SaveChanges()` | `save()` | `$model->save()` on Eloquent |
| Eager load | `Include` / `ThenInclude` | `with()` / `thenWith()` | `with()` |
| Explicit load | `Entry().Collection().Load()` | `$db->load($model, $path)` and `loadMissing` | `$model->load()` |
| One row | `First`, `FirstOrDefault`, `Single` | `firstOrFail`, `first`, `sole` | the same names |
| Filters | `HasQueryFilter` / `IgnoreQueryFilters` | `addGlobalScope` / `withoutGlobalScopes` | global scopes |
| Value conversion | `ValueConverter` | `\Tyhp\Rhetoric\Casts\Cast`, `#[Cast]` | `CastsAttributes` |
| Save pipeline | `SaveChangesInterceptor` | an `Observer` attached with `observedBy` | model observers |
| Bulk update / delete | `ExecuteUpdate` / `ExecuteDelete` | `update`, `delete`, `increment` on a query | the query builder |
| Raw SQL | `FromSql`, `SqlQuery<T>` | `fromRaw`, `$db->select(Post::class)($sql, $bindings)`, `statement` | `DB::select`, `DB::statement` |
| Concurrency failure | `DbUpdateConcurrencyException` | `\Tyhp\Rhetoric\ConcurrencyException` | |
| Create schema | `EnsureCreated` | `$db->createSchema()` | |

```php
$posts = $db->posts()
    ->where(\Tyhp\Expression::of(\App\Data\Post::class)->rating->gte(3))
    ->where(\Tyhp\Expr::param('post', \App\Data\Post::class)->title->call('startsWith', 'Tyhp'))
    ->with(\Tyhp\Expression::of(\App\Data\Post::class)->blog)
    ->orderByDesc(\Tyhp\Expression::of(\App\Data\Post::class)->publishedAt)
    ->take(10)
    ->all();
```

`php artisan rhetoric:migration AddRating --context="App\Data\BlogContext"` writes a Laravel migration. The snapshot is JSON in `database/rhetoric`. See [Migrations](rhetoric_php_migrations.md).
