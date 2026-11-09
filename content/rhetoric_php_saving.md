---
title: 'Rhetoric for PHP: Saving'
---

The context tracks models you add and models a query loads. `save()` compares each one with the values from when it was loaded or added, then inserts, updates, and deletes in one transaction. The return value is how many rows were written.

`untracked()` on a query leaves those rows out of the map. See [Querying](rhetoric_php_querying.md).

## Adding and removing

```php
$blog = new \App\Data\Blog();
$blog->name = 'Tyhp news';
$db->blogs()->add($blog);

$post = $db->posts()->find(42);
if ($post !== null) {
    $post->rating = 5;
    $db->posts()->remove($post);
}

$written = $db->save();
```

`add` marks the model added. `addMany` takes a list. `track` attaches an existing instance as clean. `trackAsDirty` attaches it as dirty. `remove` and `removeMany` mark it deleted. Removing a model that was added and not saved drops it from the tracker.

`entry` reads the type from the model:

```php
$entry = $db->entry($post);
$state = $entry->state;
$ratingChanged = $entry->isDirty(\Tyhp\Expression::of(\App\Data\Post::class)->rating);
$original = $entry->getOriginal(\Tyhp\Expression::of(\App\Data\Post::class)->rating);
$entry->refresh();
```

`$entry->state` is a `\Tyhp\Rhetoric\Tracking\TrackingState` case: `Added`, `Clean`, `Dirty`, `Deleted`, or `Untracked`. `isDirty()` with no argument is true for added and dirty models. `getOriginal` throws when the model is untracked. `refresh()` re-reads the row into the same instance. `expire()` clears the snapshot so the next read loads again.

`$db->tracker->clear()` forgets every tracked model. A lazy model that has not been touched is not dirty, and the tracker does not initialize it.

## What save writes

Parents are inserted before children. Children are deleted before parents. A generated key is copied into the foreign key that points at it, including a row that references itself. A cycle through a nullable foreign key is inserted, then updated. A cycle with no nullable foreign key throws.

Changing a relation writes the foreign key. Many-to-many saves insert and delete pivot rows, including rows a new model already held when you called `add`. Moving a model between two loaded collections keeps the row and writes the new foreign key. Taking a model out of a loaded collection deletes it when the foreign key cannot be null.

`#[Timestamps]` sets `created_at` on insert and `updated_at` on every write. `#[ConcurrencyCheck]` and `#[RowVersion]` require the loaded token to still match. A mismatch throws `\Tyhp\Rhetoric\ConcurrencyException`.

`save()` joins a Laravel transaction that is already open. `transaction` takes the closure's return type, then the closure:

```php
use Tyhp\Type as T;

$written = $db->transaction(T::int)(
    function () use ($db): int {
        return $db->save();
    },
);
```

The second argument is how many times to attempt the transaction. Observers run `saving`, `creating`, `updating`, and `deleting` before the write, and `saved`, `created`, `updated`, and `deleted` after it.

## Schema helpers

`$db->createSchema()` creates the mapped tables. `$db->dropSchema()` drops them. `schemaHas` takes one property path:

```php
$ready = $db->schemaHas(\Tyhp\Expression::of(\App\Data\Post::class)->rating);
```

Ongoing schema changes are [Migrations](rhetoric_php_migrations.md).
