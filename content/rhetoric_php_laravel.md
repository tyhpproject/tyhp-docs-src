---
title: 'Rhetoric for PHP: Laravel Integration'
---

Rhetoric uses the connection from `config/database.php`. On your context, `protected ?string $connection` is that name, or `null` for the default connection. Queries and `save()` use that connection. See [Querying](rhetoric_php_querying.md) and [Saving](rhetoric_php_saving.md).

## Provider and config

`Tyhp\Rhetoric\Laravel\RhetoricServiceProvider` is registered by the package. It merges `config/rhetoric.php`, binds every class in `contexts` in the scoped container, and attaches the mapping cache and the auto-migrator. The first resolve of a context builds its map.

```bash
php artisan vendor:publish --tag=rhetoric-config
```

```php
return [
    'contexts' => [
        \App\Data\ChirpContext::class,
    ],
    'snapshot_path' => null,
    'migrations_path' => null,
    'mapping_cache' => null,
];
```

`null` keeps the defaults: snapshots in `database/rhetoric`, migrations in `database/migrations`, and the mapping cache at `bootstrap/cache/rhetoric-mapping.php`. The `auto_migrate` keys are in [Migrations](rhetoric_php_migrations.md).

The scoped binding is a new context on the next request, including under Octane. A job that performs more than one unit of work wants a new context per unit. `ContextFactory` takes the context class, then the constructor arguments:

```php
$factory = \Tyhp\Rhetoric\ContextFactory::new(\App\Data\ChirpContext::class)();
$db = $factory->create();
```

`$db->tracker->clear()` drops tracked models if you reuse a context. `$db->close()` makes a later lazy load throw.

## Commands

| Command | Purpose |
| --- | --- |
| `rhetoric:show` | Print the map. The context class is the argument |
| `rhetoric:migration` | Write a migration. The name is the argument |
| `rhetoric:remove-migration` | Remove the latest unapplied Rhetoric migration and restore its snapshot |
| `rhetoric:pending` | Fail when the map and the snapshot differ |
| `rhetoric:baseline` | Write a snapshot only |
| `rhetoric:scaffold` | Generate models from the database |
| `rhetoric:auto-migrate` | Apply pending migrations. `--status` prints state. `--reset` clears a failure |
| `rhetoric:migrate-deferred` | Apply deferred migrations |
| `rhetoric:cache` | Write the mapping cache and the migration manifest |
| `rhetoric:clear` | Delete them |

`php artisan optimize` runs `rhetoric:cache`. `php artisan optimize:clear` runs `rhetoric:clear`.

## Eloquent models

Use Eloquent for a class Laravel must construct itself, such as the authenticatable user. Rhetoric can still filter and sort that model with a typed query on PHP 8.4 or newer. `rhetoric:scaffold --eloquent` writes a property per column that reads and writes the attribute. A name Eloquent's `Model` already uses (`connection`, `table`) is written with a `Value` suffix.

```php
$query = \Tyhp\Rhetoric\EloquentQuery::query(\App\Models\Article::class)();
$article = $query
    ->where(\Tyhp\Expression::of(\App\Models\Article::class)->title->same('Tyhp'))
    ->orderByDesc(\Tyhp\Expression::of(\App\Models\Article::class)->rating)
    ->first();

$onMysql = \Tyhp\Rhetoric\EloquentQuery::on(\App\Models\Article::class)('mysql');
```

`get()` returns an Eloquent collection. `builder()` returns the Eloquent builder so the rest of a Laravel chain can follow. The column is the `Tyhp\Rhetoric\Attributes\Column` name, or the property in snake case. `contains`, `startsWith`, and `endsWith` treat `%`, `_`, and `\` as literal characters.

A Rhetoric model can map the same table an Eloquent model uses. Keep the Eloquent class for authentication and use the Rhetoric class for the rows you query and save through a context.

## Workers

Run `rhetoric:cache` when you deploy so the first request does not rebuild the map by reflection. Inside a queued job, `ContextFactory` gives you a context that no other job is holding. `save()` joins a Laravel transaction that is already open.

Implement `\Tyhp\Rhetoric\Observers\QueryInterceptor` when you want the SQL string before it runs. Telescope and the debug bar see that same connection.
