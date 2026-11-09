---
title: 'Rhetoric for PHP: Migrations'
---

Rhetoric writes plain PHP migration classes into Laravel's `database/migrations` directory. You apply them with `php artisan migrate`. Each context also has a JSON snapshot, `database/rhetoric/<Context>.snapshot.json`, which is the mapping those migrations already describe.

Both paths are based on the application's database directory. `--path` and `--snapshot` override them for one command. `migrations_path` and `snapshot_path` in `config/rhetoric.php` override the defaults.

The commands are the same whether the models are written in PHP or Tyhp. `--context` is the context class.

## Commands

```bash
php artisan rhetoric:migration AddPostRating --context="App\Data\BlogContext"
php artisan migrate
php artisan rhetoric:pending --context="App\Data\BlogContext"
php artisan rhetoric:show "App\Data\BlogContext"
```

`rhetoric:migration` requires a name. It diffs the current map against the snapshot and writes an anonymous migration class. The file returns that object so Laravel's migrator can run it. When there is no schema change, the command says so and updates the snapshot if only non-schema facts changed.

`--rename=posts.old_slug:slug` records a column rename. Pass it more than once for several columns. The table has to exist in both the snapshot and the map. A changed primary key, a changed table comment, and dropped timestamps are warnings. If the migration drops or narrows data, the command tells you to pass `--defer`.

```bash
php artisan rhetoric:migration DropPostLegacySlug --context="App\Data\BlogContext" --defer
php artisan rhetoric:migration DropPostLegacySlug --context="App\Data\BlogContext" --defer --independent
php artisan rhetoric:migrate-deferred
```

`--defer` leaves the migration for `rhetoric:migrate-deferred`. `--independent` allows a later migration to run before this one. `rhetoric:migrate-deferred` accepts `--connection`, `--set`, and `--only=name` (start at that migration and include everything after it).

`rhetoric:remove-migration --context="App\Data\BlogContext"` deletes the latest Rhetoric migration that has not been applied and puts the previous snapshot back. It reads the application's migration repository.

`rhetoric:pending` exits with a non-zero status when the map and the snapshot differ. A renamed model class or an `onDelete` edit is stored in the snapshot and does not keep failing `pending` after that update.

`rhetoric:baseline --context="App\Data\BlogContext"` writes the snapshot and skips the migration file. Use it when the database already has the schema the map describes.

`rhetoric:show` prints tables, columns, keys, foreign keys, and relations.

From PHP, `$db->createSchema()` and `$db->dropSchema()` apply the map without Artisan. `$db->schemaHas(\Tyhp\Expression::of(\App\Data\Post::class)->rating)` reports whether that column's migration has been applied.

## Auto-migrator

Turn it on with `RHETORIC_AUTO_MIGRATE=true` or `auto_migrate.enabled` in the published config. Pending migrations run as the application boots, one database at a time. The next request compares a cached hash. This runs in every environment except `testing`, unless `auto_migrate.environments` lists a narrower set.

`auto_migrate.trigger` defaults to `boot`. `except_paths` defaults to `up`, so the health route does not migrate. `console` is the list of artisan commands that may migrate during boot. Leave it empty and no artisan command migrates that way. `migrate`, `db:`, `schema:`, `rhetoric:`, `optimize`, `config:`, and `package:discover` are skipped even when listed. `queue` and `octane` default to true. The Octane worker runs the check once.

The lock is a database advisory lock on the connection being migrated (`lock.driver` = `database`), including the write connection on MySQL and PostgreSQL. Set `lock.driver` to `cache` (`lock.store`, `lock.ttl`) when a pooler such as PgBouncer in transaction mode cannot hold a session lock. The marker is a PHP file under `storage/framework/rhetoric` (`marker.store` = `file`). A cache store is optional (`marker.cache_store`). The package does not require the APCu extension.

HTTP waits `wait.http` seconds (10) and then, with `on_timeout` of `throw`, responds 503 with `Retry-After` (`retry_after`, default 15). `continue` serves the request instead. `on_failure` is the same choice after a migration throws. `failure_backoff` (30 seconds, then 600) records the failure so later requests do not all retry it. A database that cannot be reached is recorded the same way, before the lock is taken.

```bash
php artisan rhetoric:auto-migrate
php artisan rhetoric:auto-migrate --status
php artisan rhetoric:auto-migrate --reset
php artisan rhetoric:cache
php artisan rhetoric:clear
```

`--reset` clears the marker and the failure record after you repair a migration that stopped halfway. On MySQL a failed migration can leave earlier statements applied, because those statements are not in a transaction and Laravel records the migration only after `up()` finishes. PostgreSQL, SQL Server, and SQLite wrap each migration in a transaction.

`rhetoric:cache` writes `bootstrap/cache/rhetoric-mapping.php` (or `mapping_cache`) and the migration manifest. It writes the map from the current code. `rhetoric:clear` removes both. `artisan optimize` runs `rhetoric:cache`. `artisan optimize:clear` runs `rhetoric:clear`.

`auto_migrate.deferred.dispatch` sends deferred migrations to `deferred.queue` instead of running them during the request.

When several servers deploy at once, the first one on the new code migrates while older code is still serving. Ship an expanding change first, and mark the contracting change `--defer` until the old code is gone.
