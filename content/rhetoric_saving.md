---
title: 'Rhetoric: Saving'
---

A context is the unit of work. Models you `add` or load through a tracked query sit in `$db->tracker`. `save()` compares each instance with the values it was loaded with, then inserts, updates, and deletes inside one database transaction. `save()` returns the number of rows written.

Hydrated models are tracked. `untracked()` on a query skips the map. See [Querying](rhetoric_querying.md).

## Adding and removing

```tyhp
<?tyhp

$blog = new Blog();
$blog->name = 'Tyhp news';
$db->blogs->add($blog);

?Post $post = $db->posts->find(42);
if ($post !== null) {
    $post->rating = 5;
    $db->posts->remove($post);
}

int $written = $db->save();
```

`add` marks the model `Added`. `addMany` does that for a list. `track` attaches an existing instance as `Clean`. `trackAsDirty` attaches it as `Dirty`. `remove` and `removeMany` mark `Deleted`. Calling them on a model that was `Added` and not saved drops it from the tracker instead of issuing a `DELETE`.

`$db->entry($model)` is a `TrackedEntry<T>`. `$entry->state` is `TrackingState::Added`, `Clean`, `Dirty`, `Deleted`, or `Untracked`. `isDirty()` is true for `Added` and `Dirty`. `isDirty(fn ($post) => $post->rating)` is true when that column differs from the snapshot. `getOriginal(fn ($post) => $post->rating)` is the loaded value and throws for an untracked model. `refresh()` re-reads the row into the same instance. `expire()` drops the loaded snapshot so the next read reloads. Both use the same object.

`$db->tracker->clear()` forgets every tracked model. `detectChanges()` refreshes the dirty set. An untouched lazy model is not dirty and is not initialized by the tracker.

## What save writes

`save()` inserts parents before children and deletes children before parents. A generated key is copied into a dependent foreign key, including when the child points at a principal that is already tracked, and when a row references itself. A cycle through a nullable foreign key is an insert followed by an update. A cycle that has no nullable foreign key throws.

Inserts of client-generated UUID and ULID keys are batched. A child is not in the same insert as its principal. Inserts stay within the driver's parameter limit. Deleted rows that share a table and a single key are removed in one statement per 900 keys.

Changing a navigation updates the foreign key. `hasMany` does the same. `belongsToMany` inserts and deletes pivot rows, including rows a new model already held when you `add` it. Moving a model from one loaded collection to another keeps the row and writes the new foreign key. Removing a model from a loaded collection deletes it when that foreign key is not nullable.

`#[Timestamps]` sets `created_at` on insert and `updated_at` on insert and update. `#[ConcurrencyCheck]` and `#[RowVersion]` add the loaded token to the `UPDATE` / `DELETE`. A mismatch throws `Tyhp\Rhetoric\ConcurrencyException`.

`save()` joins a Laravel transaction that is already open. `transaction(fn, $attempts)` runs your closure in a transaction and returns its value. Pass the type argument: `transaction<int>(...)`.

Observers run `saving` / `creating` / `updating` / `deleting` before the write and `saved` / `created` / `updated` / `deleted` after it. `restore` on a soft-deleted model runs `restoring` and `restored`.

## Schema without a migration

`$db->createSchema()` creates the tables, columns, and foreign keys in the current map. `$db->dropSchema()` drops them. `$db->schemaHas(fn ($post) => $post->rating)` reports whether that column's migration has been applied. Day-to-day schema changes go through [Migrations](rhetoric_migrations.md).

## PHP callers

`add` and `save` are the same methods. From PHP, `entry($model)` is an ordinary call and `transaction` takes the return type first: `transaction(\Tyhp\Type::int)($callback)`. See [Saving for PHP](rhetoric_php_saving.md).
