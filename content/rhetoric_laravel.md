---
title: 'Rhetoric: Laravel Integration'
---

Rhetoric uses the Laravel connection you already configured in `config/database.php`. A context sets `protected ?string $connection` to that connection's name. `null` is the default connection. Queries and `save()` use that connection. See [Querying](rhetoric_querying.md) and [Saving](rhetoric_saving.md).

## Service provider and config

`Tyhp\Rhetoric\Laravel\RhetoricServiceProvider` merges `config/rhetoric.php`, registers each class in `contexts` as a scoped binding, and installs the mapping archive and the auto-migrator. Resolving a context builds its map. Publish the file with:

```bash
php artisan vendor:publish --tag=rhetoric-config
```

```php
return [
    'contexts' => [
        App\Data\ChirpContext::class,
    ],
    'snapshot_path' => null,
    'migrations_path' => null,
    'mapping_cache' => null,
];
```

`snapshot_path` and `migrations_path` replace `database/rhetoric` and `database/migrations`. `mapping_cache` replaces `bootstrap/cache/rhetoric-mapping.php`. The `auto_migrate` array is documented in [Migrations](rhetoric_migrations.md).

Scoped bindings reset per request, including an Octane request. A queued job or a worker that needs several units of work should not reuse one context. `ContextFactory<T>` constructs a new one each time:

```tyhp
<?tyhp

use App\Data\ChirpContext;
use Tyhp\Rhetoric\ContextFactory;

function factory(): ChirpContext {
    ContextFactory<ChirpContext> $factory = new ContextFactory<ChirpContext>();
    return $factory->create();
}
```

Call `$db->tracker->clear()` when you do keep a context and need to drop what it is tracking. `$db->close()` rejects a later lazy load.

## Commands

| Command | Purpose |
| --- | --- |
| `rhetoric:show {context}` | Print the map |
| `rhetoric:migration {name}` | Write a migration from the snapshot diff |
| `rhetoric:remove-migration` | Delete the latest unapplied Rhetoric migration and restore the snapshot |
| `rhetoric:pending` | Exit non-zero when the map differs from the snapshot |
| `rhetoric:baseline` | Write a snapshot and no migration |
| `rhetoric:scaffold` | Read a database and write models |
| `rhetoric:auto-migrate` | Run pending migrations, or `--status` / `--reset` |
| `rhetoric:migrate-deferred` | Run deferred migrations |
| `rhetoric:cache` | Write the mapping cache and the migration manifest |
| `rhetoric:clear` | Remove them |

`artisan optimize` includes `rhetoric:cache`. `artisan optimize:clear` includes `rhetoric:clear`. Flags are in [Migrations](rhetoric_migrations.md) and [Scaffolding](rhetoric_scaffolding.md).

## Typed queries on Eloquent models

Eloquent stays the right model for framework features that require it, such as `Authenticatable`. Rhetoric can still type a `where` and an `orderBy` against that model. The model needs real properties that read and write attributes. `rhetoric:scaffold --eloquent` generates them. PHP 8.4 or newer is required, because a typed property and Eloquent's `__get` / `__set` both need the native property hooks.

```tyhp
<?tyhp

use App\Models\Article;
use Tyhp\Rhetoric\EloquentQuery;

function titled(string $title): ?Article {
    return EloquentQuery::query<Article>()
        ->where(fn ($article) => $article->title === $title)
        ->orderByDesc(fn ($article) => $article->rating)
        ->first();
}
```

`EloquentQuery::on<Article>('mysql')` selects the connection. `get()` returns an Eloquent collection. `builder()` is the `Eloquent\Builder` after those clauses, for the rest of a Laravel chain. The column name is `#[\Tyhp\Rhetoric\Attributes\Column('title')]` when present, otherwise the snake_case property name. `contains`, `startsWith`, and `endsWith` match `%`, `_`, and `\` in the text literally.

A Rhetoric model and an Eloquent model can share a table. Chirper does this: `User` stays an Eloquent authenticatable, and chirps are Rhetoric models. The example is `tyhp-examples/chirper`.

## Workers

Run `rhetoric:cache` during deploy so the map is a file, not a reflection walk on the first request. For a queue worker, construct a context with `ContextFactory<T>` inside the job, or resolve the scoped context once per job if the worker boots the container per job. `save()` joins a Laravel transaction that is already open.

`QueryInterceptor::beforeExecuting` sees the SQL Laravel is about to run, which is the same stream Telescope and Debugbar observe through the connection.

PHP callers write `ContextFactory::new(\App\Data\ChirpContext::class)()` and `EloquentQuery::query(\App\Models\Article::class)()`. See [Laravel integration for PHP](rhetoric_php_laravel.md).
