---
title: 'Rhetoric: Coming from EF Core'
---

Rhetoric is the unit-of-work and typed-query package for a Laravel application. The names below are the ones in the current API. `all()` returns `array<T>`. `get()` returns `Collection<int, T>`, the Laravel collection of the same rows.

| Concept | EF Core | Rhetoric | Laravel |
| --- | --- | --- | --- |
| Unit of work | `DbContext` | `Context` | A context names a connection from `config/database.php` |
| Queryable set | `DbSet<T>` | `Table<T>` via `$this->table<T>()` | `DB::table()` is untyped SQL |
| Mapped class | entity | model | Eloquent model. `EloquentQuery` queries one of those directly |
| Mapping metadata | `IEntityType` | `Mapping\ContextMap`, `Mapping\ModelMap` | |
| Fluent configuration | `ModelBuilder`, `EntityTypeBuilder<T>` | `Mapper`, `ModelMapper<T>` | |
| Per-model configuration | `IEntityTypeConfiguration<T>` | `ModelMapping<T>` | |
| Configuration hook | `OnModelCreating` | `map(Mapper $map)` | |
| Change tracker | `ChangeTracker` | `Tracker` (`$db->tracker`) | |
| Tracked handle | `EntityEntry` | `TrackedEntry<T>` (`$db->entry($model)`) | |
| State | `EntityState` | `TrackingState`: `Added`, `Clean`, `Dirty`, `Deleted`, `Untracked` | `isDirty()`, `isClean()` |
| Save | `SaveChanges()` | `save()` | `$model->save()` |
| Eager load | `Include` / `ThenInclude` | `with()` / `thenWith()` | `with()` |
| Explicit load | `Entry().Collection().Load()` | `$db->load($model, fn)` and `loadMissing` | `$model->load()` |
| One row | `First`, `FirstOrDefault`, `Single` | `firstOrFail`, `first`, `sole` | the same names |
| Filters | `HasQueryFilter` / `IgnoreQueryFilters` | `addGlobalScope` / `withoutGlobalScopes` | global scopes |
| Value conversion | `ValueConverter` | `Cast<TValue, TColumn>`, `#[Cast]` | `CastsAttributes` |
| Save pipeline | `SaveChangesInterceptor` | observers (`observedBy`) | model observers |
| Bulk update / delete | `ExecuteUpdate` / `ExecuteDelete` | `update(fn)` / `delete()` / `increment()` on a query | query builder `update` / `delete` |
| Raw SQL | `FromSql`, `SqlQuery<T>`, `ExecuteSql` | `fromRaw`, `$db->select<T>()`, `$db->statement()` | `fromRaw`, `DB::select`, `DB::statement` |
| Concurrency failure | `DbUpdateConcurrencyException` | `ConcurrencyException` | |
| Create schema | `EnsureCreated` | `$db->createSchema()` | |

A filter is a lambda, not a string:

```tyhp
array<Post> $posts = $db->posts
    ->where(fn ($post) => $post->rating >= 3 && $post->title->startsWith('Tyhp'))
    ->with(fn ($post) => $post->blog)
    ->orderByDesc(fn ($post) => $post->publishedAt)
    ->take(10)
    ->all();
```

Migrations are Laravel PHP files written by `rhetoric:migration`, not `dotnet ef migrations add`. The snapshot is JSON under `database/rhetoric`. See [Migrations](rhetoric_migrations.md).

PHP callers use the same type names and build lambdas with `\Tyhp\Expression::of`. See [Coming from EF Core (PHP)](rhetoric_php_from_ef.md).
