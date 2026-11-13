---
title: 'Rhetoric: Migrations'
---

Rhetoric writes ordinary PHP files under `database/migrations`. `php artisan migrate` runs them with Laravel's migrator. The snapshot next to those files is one JSON document per context, so a pull request shows the mapping diff.

Default paths, resolved from the application's database path:

| Path | Role |
| --- | --- |
| `database/rhetoric/<Context>.snapshot.json` | Last mapping that has a migration or a baseline |
| `database/migrations` | Generated migration files |

Override either with `--snapshot` and `--path`, or with `snapshot_path` and `migrations_path` in `config/rhetoric.php`.

## Write a migration

Register the context, then:

```bash
php artisan rhetoric:migration AddPostRating --context="App\Data\BlogContext"
php artisan migrate
```

`rhetoric:migration` diffs the map against the snapshot and writes one anonymous PHP migration class. The file returns that object so Laravel's migrator can run it. The command prints the path. When the map and the snapshot describe the same schema, it updates the snapshot if only non-schema facts changed, and prints that nothing changed.

`--rename=posts.old_slug:slug` treats that column as a rename. Repeat the option for several columns. A rename whose table is not in both the snapshot and the map is rejected. A changed primary key, a changed table comment, and dropped timestamps are warnings. A migration that drops or narrows data prints a warning telling you to pass `--defer`.

```bash
php artisan rhetoric:migration DropPostLegacySlug --context="App\Data\BlogContext" --defer
php artisan rhetoric:migration DropPostLegacySlug --context="App\Data\BlogContext" --defer --independent
```

`--defer` sets `$deferred` on the migration so the auto-migrator stops before it. `--independent` sets `$independent` as well, which lets a later migration run first. Apply deferred work with `php artisan rhetoric:migrate-deferred`.

`rhetoric:remove-migration --context="App\Data\BlogContext"` deletes the latest Rhetoric migration that has not been applied and restores the previous snapshot. It checks the application's migration repository.

`rhetoric:pending --context="App\Data\BlogContext"` exits non-zero when the map differs from the snapshot. Use it in CI. A snapshot-only edit, such as a renamed model class or an `onDelete` change, does not leave `rhetoric:pending` failing after the snapshot is updated.

`rhetoric:show App\Data\BlogContext` prints tables, columns, keys, foreign keys, and relations, including `Source` on a column and `onUpdate` on a foreign key.

`rhetoric:baseline --context="App\Data\BlogContext"` writes the snapshot and does not write a migration. Use it when the database already matches the map.

Seed rows and column defaults are stored as the values the cast writes. A seed that changes from `null` to `''` is a difference. Foreign keys keep one name when the connection has a table prefix.

## Without Artisan

`$db->createSchema()` and `$db->dropSchema()` apply the map directly. `$db->schemaHas(fn ($post) => $post->rating)` is true after the migration that adds that column has run.

## Auto-migrator

Set `RHETORIC_AUTO_MIGRATE=true` or `auto_migrate.enabled` in `config/rhetoric.php`. Pending migrations then run while the application boots, one database at a time. Later requests compare a cached hash instead of taking the lock again. The check runs in every environment except `testing`, unless `auto_migrate.environments` narrows that list.

The default trigger is `auto_migrate.trigger` of `boot` (`Application::booting()`). `except_paths` defaults to `up`, so the health check does not migrate. `console` lists artisan command names that may migrate while booting. An empty list migrates no artisan command. Commands under `migrate`, `db:`, `schema:`, `rhetoric:`, `optimize`, and `config:`, plus `package:discover`, are skipped either way. `queue` and `octane` default to true. On Octane the boot hook and the worker-start hook share one memoized check.

The lock defaults to a database advisory lock on the connection being migrated (`lock.driver` of `database`), taken on the write connection for MySQL and PostgreSQL. `lock.driver` of `cache` uses a Laravel cache lock (`lock.store`, `lock.ttl`) for a pooler that does not keep a session lock. The marker file lives under `storage/framework/rhetoric` (`marker.store` of `file`). `apcu` and a shared cache store are optional (`marker.store`, `marker.cache_store`). APCu is not required.

`wait.http` is 10 seconds. `wait.console` and `wait.queue` are 300. `on_timeout` of `throw` responds with 503 and `Retry-After` (`retry_after`, default 15). `on_timeout` of `continue` serves the request. `on_failure` chooses the same for a migration that threw. `failure_backoff` (default 30 seconds, then 600) stops every request from retrying a failed migration. A failure before the lock, such as a database that cannot be reached, is recorded the same way.

`rhetoric:auto-migrate` runs the pending set. `--connection` and `--set` limit it. `--status` prints the marker and what is pending. `--reset` clears the marker and the failure record after you have fixed a partial migration. `rhetoric:migrate-deferred` runs deferred migrations and the migrations they hold back. `--only` starts at one migration name and includes everything after it. `auto_migrate.deferred.dispatch` queues that work (`deferred.queue`) instead of running it in the request.

`rhetoric:cache` writes the mapping cache and the migration manifest. The cache file defaults to `bootstrap/cache/rhetoric-mapping.php` (`mapping_cache`). It writes the map the code describes, including when the process loaded an older cache. `rhetoric:clear` removes both. The service provider registers `rhetoric:cache` with `artisan optimize` and `rhetoric:clear` with `artisan optimize:clear`.

MySQL DDL is not transactional. A migration that fails halfway can leave its earlier statements applied, because Laravel records the migration after `up()` returns. Recover by fixing the database and running `rhetoric:auto-migrate --reset`. PostgreSQL, SQL Server, and SQLite run each migration in a transaction.

On a deploy with more than one server, the first server to boot the new release migrates while older servers are still serving. Keep expanding changes and contracting changes in separate deploys, and mark the contract step `--defer`.

PHP callers use the same artisan commands. See [Migrations for PHP](rhetoric_php_migrations.md).
