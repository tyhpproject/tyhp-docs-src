---
title: 'Rhetoric for PHP: Getting Started'
---

`tyhp/rhetoric` is a Composer package for database access in a Laravel application. You call it from ordinary PHP. A **model** is a plain class. A **context** is the unit of work: it names a Laravel connection, hands you a typed table for each model, and tracks the instances you add, load, and change. `save()` writes those changes in one transaction.

This section does not assume you write Tyhp. The same package, called from Tyhp, is documented under [Rhetoric](rhetoric_getting_started.md).

## Install

Rhetoric runs on PHP 8.3, 8.4, and 8.5 with Laravel 13. Pick the Composer pin whose `80N` prefix matches the PHP you run (`803` for 8.3, `804` for 8.4, `805` for 8.5):

```bash
composer require tyhp/rhetoric:805.0.*
```

Composer also installs `tyhp/core`, `tyhp/lambda`, `illuminate/database`, `illuminate/support`, and `illuminate/console`. Publish the config to register your contexts:

```bash
php artisan vendor:publish --tag=rhetoric-config
```

`Tyhp\Rhetoric\Laravel\RhetoricServiceProvider` registers each class in `config/rhetoric.php` under `contexts` as a scoped container binding.

## Calling a generic from PHP

A generic class is constructed with `new`, then the constructor arguments. `type` returns the `\Tyhp\Type` for that binding:

```php
use Tyhp\Type as T;

$box = \Vendor\Box::new(T::int)(42);
$type = \Vendor\Box::type(T::int);
```

`T::int` is the `int` builtin, a `\Tyhp\BuiltIn` value. `T::int()` is that builtin as a `\Tyhp\Type`. A class-string such as `\App\Data\Post::class` is a type argument on the Rhetoric methods below. Further factories are on [Packages for PHP](php_packages.md).

Pass the type, then the value arguments, for `table`, `model`, `belongsTo`, `hasOne`, `hasMany`, `belongsToMany`, `using`, `extraColumn`, `transaction`, `select` on a context, `select` on a query, `EloquentQuery::query`, and `EloquentQuery::on`. `entry($model)` and `\Tyhp\Expression::of` are ordinary calls. The model, or the class-string passed to `Expression::of`, supplies the type.

When the class or the callable is chosen at runtime, `\Tyhp\Generic::bind` accepts `T::int`, a `\Tyhp\Type`, or a class-string. `\_gnrc` does the same and does not construct:

```php
$box = \Tyhp\Generic::bind($className, T::int)->new(42);
$same = \_gnrc($className, T::int)->new(42);
```

Query and mapping trees use the fluent builders from `tyhp/lambda`:

```php
\Tyhp\Expression::of(\App\Data\User::class)->age->gte(18)->and()->isActive->same(true);
```

`gte` is `>=`, `same` is `===`. `eq` / `neq` are `===` / `!==` as well (`eq` matches `same`). `gt`, `lt`, and `lte` are the other comparisons. `and()` and `or()` with no argument continue the predicate from the same model. A string method is an `\Tyhp\Expr` chain, because `Expression::of(...)->title` is a property path and does not accept a method call:

```php
\Tyhp\Expr::param('post', \App\Data\Post::class)->title->call('startsWith', 'Tyhp');
```

## A model

Public properties are columns. A property typed as another model is a relation. `id` is the primary key. A camelCase name becomes a snake_case column (`userId` is stored as `user_id`). The table name is the plural snake_case of the short class name unless you set it.

A PHP `array` type does not say what the array holds. A collection relation names its model with `#[\Tyhp\PropertyType]` on the property, as `Author` would for its chirps:

```php
#[\Tyhp\PropertyType('array<App\\Data\\Chirp>')]
public array $chirps = [];
```

```php
namespace App\Data;

use Tyhp\Rhetoric\Attributes\MaxLength;
use Tyhp\Rhetoric\Attributes\Table;
use Tyhp\Rhetoric\Attributes\Timestamps;

#[Timestamps]
class Chirp
{
    public int $id = 0;
    public int $userId = 0;
    #[MaxLength(255)]
    public string $message = '';
    public ?\DateTimeImmutable $createdAt = null;
    public ?\DateTimeImmutable $updatedAt = null;
    public ?Author $user = null;
}

#[Table('users')]
class Author
{
    public int $id = 0;
    public string $name = '';
    public string $email = '';
}
```

`#[Timestamps]` fills `created_at` on insert and `updated_at` on insert and update. See [Mapping](rhetoric_php_mapping.md).

## A context

Extend `\Tyhp\Rhetoric\Context`. `$connection` is the Laravel connection name; leave it `null` for the default. `table` is protected, so a subclass passes the model class and returns the table:

```php
namespace App\Data;

use Tyhp\Rhetoric\Context;
use Tyhp\Rhetoric\Mapping\Mapper;
use Tyhp\Rhetoric\Table;

final class ChirpContext extends Context
{
    protected ?string $connection = null;

    public function chirps(): Table
    {
        return $this->table(Chirp::class)();
    }

    public function authors(): Table
    {
        return $this->table(Author::class)();
    }

    protected function map(Mapper $map): void
    {
        $chirps = $map->model(Chirp::class)();
        $chirps->belongsTo(Author::class)(\Tyhp\Expression::of(Chirp::class)->user)
            ->foreignKey(\Tyhp\Expression::of(Chirp::class)->userId);
    }
}
```

List `\App\Data\ChirpContext::class` in `config/rhetoric.php` under `contexts`.

## Query and save

```php
$chirps = $db->chirps()
    ->with(\Tyhp\Expression::of(\App\Data\Chirp::class)->user)
    ->latest()
    ->take(50)
    ->all();

$chirp = new \App\Data\Chirp();
$chirp->userId = $userId;
$chirp->message = $message;
$db->chirps()->add($chirp);
$db->save();
```

`all()` returns a list of models (`array`). `get()` returns an `Illuminate\Support\Collection`. Chain `where` before `first` when you want one row:

```php
$one = $db->chirps()
    ->where(\Tyhp\Expression::of(\App\Data\Chirp::class)->id->same($id))
    ->first();
```

`Expression::of` compares and walks properties. A table comes from `table(Chirp::class)()`. Continue with [Querying](rhetoric_php_querying.md) and [Saving](rhetoric_php_saving.md).

## Where to go next

- [Mapping](rhetoric_php_mapping.md)
- [Querying](rhetoric_php_querying.md)
- [Saving](rhetoric_php_saving.md)
- [Migrations](rhetoric_php_migrations.md) and [Scaffolding](rhetoric_php_scaffolding.md)
- [Laravel integration](rhetoric_php_laravel.md)
- [Translation reference](rhetoric_php_translation.md)
- [Coming from EF Core](rhetoric_php_from_ef.md)
