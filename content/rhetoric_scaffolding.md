---
title: 'Rhetoric: Scaffolding'
---

`rhetoric:scaffold` reads a database and writes Tyhp models, a context, and a mapping. The model class is written once. Generated members live in a trait under `Generated/`, and a later scaffold rewrites that trait. Pass `--force` to write the model and context classes again.

```bash
php artisan rhetoric:scaffold --connection=mysql --context=LegacyContext --namespace="App\Data\Legacy"
```

`--context` is required. A name with no namespace is placed in `--namespace`. `--output` is the directory for the `.tyhp` files; the default is the current directory. `--connection` selects a Laravel connection. `--schema` limits the schema. `--tables` and `--exclude` are comma-separated lists of tables and views.

`--attributes` writes each override once as an attribute on the model. `--fluent` writes those overrides once in the mappings class. Pass one of them. The default, with neither flag, follows the attribute style (`--attributes` is the explicit form of that default). `--no-pluralize` uses the table name as the model name. A table whose name PHP reserves (`matches`) becomes a class with a `Model` suffix (`MatchModel`). A table that does not have the connection's prefix is skipped. A pivot candidate whose foreign keys are not the related models' primary keys stays an ordinary model.

`--baseline` writes `database/rhetoric/<Context>.snapshot.json` and does not write a migration. `rhetoric:baseline --context=LegacyContext` does the same for a context you already have. `--snapshot` sets that directory. A bad namespace, a bad context name, or a baseline snapshot that cannot be saved stops the command before it writes files.

Publish the stubs and edit them. A scaffold reads `stubs/rhetoric` in the application when those files exist.

```bash
php artisan vendor:publish --tag=rhetoric-stubs
```

The package stubs are `model.stub`, `trait.stub`, `context.stub`, and `mappings.stub`. A published stub that omits a token the scaffold fills in is rejected before anything is written.

## Eloquent models

`--eloquent` writes Eloquent models whose typed properties read and write attributes. It requires PHP 8.4 or newer. It cannot be combined with `--fluent` or `--baseline`. A column whose property name is already declared on Eloquent's `Model` (`connection`, `table`) gets a `Value` suffix on the property and keeps its column name. Those models are what `EloquentQuery` queries. See [Laravel integration](rhetoric_laravel.md).

PHP projects use the same command. The generated files are Tyhp. See [Scaffolding for PHP](rhetoric_php_scaffolding.md) if you call Rhetoric from PHP and want the flags without the language pages.
