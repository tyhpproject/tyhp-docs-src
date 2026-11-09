---
title: 'Rhetoric for PHP: Scaffolding'
---

`rhetoric:scaffold` reads the database and writes model classes, a context, and a mapping. The files it writes are Tyhp (`.tyhp`). You can run the command from a PHP application and keep calling the resulting context from PHP after those files are compiled, or ignore the generated Tyhp and keep the hand-written PHP models from [Getting started](rhetoric_php_getting_started.md).

The model class is written once. Members the command owns live in a trait under `Generated/`. Running the command again rewrites the trait and leaves the model class in place. `--force` writes the model and context classes again.

```bash
php artisan rhetoric:scaffold --connection=mysql --context=LegacyContext --namespace="App\Data\Legacy"
```

`--context` is required. `--namespace` is the namespace for the models. A context name with no namespace is placed in `--namespace`. `--output` is the directory (the current directory when omitted). `--schema`, `--tables`, and `--exclude` limit which tables and views are read. `--tables` and `--exclude` are comma-separated.

`--attributes` writes each override as an attribute. `--fluent` writes them in the mappings class. Use one of those flags. `--no-pluralize` keeps the table name as the model name. A table named with a PHP reserved word gets a `Model` suffix (`matches` becomes `MatchModel`). Tables that lack the connection prefix are skipped. A table that looks like a pivot but does not reference the related primary keys is written as its own model.

`--baseline` writes the JSON snapshot and no migration. `php artisan rhetoric:baseline --context=LegacyContext` does that for a context that already exists. `--snapshot` chooses the directory. The command writes nothing if the namespace or context name is invalid, or if the baseline snapshot cannot be stored.

```bash
php artisan vendor:publish --tag=rhetoric-stubs
```

Stubs in `stubs/rhetoric` (`model.stub`, `trait.stub`, `context.stub`, `mappings.stub`) replace the package copies. A stub that drops a token the command substitutes is rejected before any file is written.

## Eloquent properties

`--eloquent` writes Eloquent models with typed properties that read and write attributes. PHP 8.4 or newer is required. Do not combine it with `--fluent` or `--baseline`. If the column's property name is already a property of Eloquent's `Model`, such as `connection` or `table`, the property is named with a `Value` suffix and the column name stays the same.

Query those models with `\Tyhp\Rhetoric\EloquentQuery`, shown in [Querying](rhetoric_php_querying.md).
