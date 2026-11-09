---
title: 'Rhetoric: Getting Started'
---

`tyhp/rhetoric` is database access for a Laravel application. A **model** is a plain Tyhp class. A **context** is the unit of work: it names a Laravel connection, exposes a `Table<T>` for each model, and tracks the instances you add, load, and change. `save()` writes those changes in one transaction.

Queries take inline `fn` lambdas. The compiler captures each lambda as an expression tree, and Rhetoric translates that tree to SQL with bound parameters. `all()` returns `array<T>`. `get()` returns a Laravel `Collection<int, T>`.

PHP code that does not use Tyhp calls `table(Post::class)()`, `Expression::of`, and the other shapes in [Rhetoric for PHP](rhetoric_php_getting_started.md).

## Install

Rhetoric targets PHP 8.3, 8.4, and 8.5 and Laravel 13. The Composer version uses the same `80N.X.Y` scheme as the other compiled `tyhp/*` packages (`803` for PHP 8.3, `804` for 8.4, `805` for 8.5). Require the pin that matches `output.phpVersion`:

```bash
composer require tyhp/rhetoric:805.0.*
```

That install also brings in `tyhp/core`, `tyhp/lambda`, `illuminate/database`, `illuminate/support`, and `illuminate/console`. Publish the config when you want to register contexts and the auto-migrator:

```bash
php artisan vendor:publish --tag=rhetoric-config
```

`Tyhp\Rhetoric\Laravel\RhetoricServiceProvider` is discovered from the package. It registers every context class listed in `config/rhetoric.php` as a scoped binding, so a new request gets a new context. See [Laravel integration](rhetoric_laravel.md).

## A model

Public properties are columns. A property whose type is another model (or `array` of a model) is a relation. `id` is the primary key and is database-generated when it is a non-null `int`. A camelCase property name is a snake_case column (`userId` is `user_id`, `createdAt` is `created_at`). The table name is the plural snake_case of the class (`Chirp` is `chirps`).

```tyhp
<?tyhp

namespace App\Data;

use Tyhp\Rhetoric\Attributes\MaxLength;
use Tyhp\Rhetoric\Attributes\Timestamps;

#[Timestamps]
class Chirp {
    public int $id = 0;
    public int $userId = 0;
    #[MaxLength(255)]
    public string $message = '';
    public ?\DateTimeImmutable $createdAt = null;
    public ?\DateTimeImmutable $updatedAt = null;
    public ?Author $user = null;
}

#[\Tyhp\Rhetoric\Attributes\Table('users')]
class Author {
    public int $id = 0;
    public string $name = '';
    public string $email = '';
}
```

`#[Timestamps]` writes `created_at` on insert and `updated_at` on insert and update. Attributes, and then the fluent mapper, override these conventions. The full set is [Mapping](rhetoric_mapping.md).

## A context

Subclass `Tyhp\Rhetoric\Context`. `protected ?string $connection` is the Laravel connection name; `null` uses the default connection. Expose each `Table<T>` with `table<T>()`.

```tyhp
<?tyhp

namespace App\Data;

use Tyhp\Rhetoric\Context;
use Tyhp\Rhetoric\Mapping\Mapper;
use Tyhp\Rhetoric\Table;

final class ChirpContext extends Context {
    public Table<Chirp> $chirps { get => $this->table<Chirp>(); }
    public Table<Author> $authors { get => $this->table<Author>(); }

    protected function map(Mapper $map): void {
        $map->model<Chirp>()
            ->belongsTo(fn ($chirp) => $chirp->user)
            ->foreignKey(fn ($chirp) => $chirp->userId);
    }
}
```

Register the class under `contexts` in `config/rhetoric.php`. The container then injects `ChirpContext`.

## Query and save

```tyhp
<?tyhp

use App\Data\Chirp;
use App\Data\ChirpContext;

function feed(ChirpContext $db): array<Chirp> {
    return $db->chirps
        ->with(fn ($chirp) => $chirp->user)
        ->latest()
        ->take(50)
        ->all();
}

function post(ChirpContext $db, int $userId, string $message): void {
    Chirp $chirp = new Chirp();
    $chirp->userId = $userId;
    $chirp->message = $message;
    $db->chirps->add($chirp);
    $db->save();
}
```

`where`, `orderBy`, and `with` accept the lambda and do not run the query. `all`, `first`, `save`, and the other terminal methods do. Captured variables are bound parameters. Continue with [Querying](rhetoric_querying.md) and [Saving](rhetoric_saving.md).

## Where to go next

- [Mapping](rhetoric_mapping.md) — conventions, attributes, and the fluent mapper.
- [Querying](rhetoric_querying.md) — filters, ordering, eager load, and aggregates.
- [Saving](rhetoric_saving.md) — the tracker and `save()`.
- [Migrations](rhetoric_migrations.md) and [Scaffolding](rhetoric_scaffolding.md).
- [Laravel integration](rhetoric_laravel.md) — config, commands, Eloquent queries, workers.
- [Translation reference](rhetoric_translation.md) — every node and method the SQL translator accepts.
- [Coming from EF Core](rhetoric_from_ef.md).
