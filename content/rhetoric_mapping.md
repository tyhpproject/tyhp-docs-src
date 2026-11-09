---
title: 'Rhetoric: Mapping'
---

A context builds a `Tyhp\Rhetoric\Mapping\ContextMap` the first time `mapping()` runs. Each model becomes a `ModelMap`: table, columns, key, indexes, foreign keys, and relations. Three layers contribute, and a later layer wins:

1. Conventions, from the class and its properties.
2. Attributes in `Tyhp\Rhetoric\Attributes`.
3. The fluent mapper inside `map(Mapper $map)`, including a `ModelMapping<T>` registered with `$map->register()`.

`rhetoric:show App\Data\ChirpContext` prints the map. On PHP 8.3, property hooks are polyfilled and attributes written on a hooked property are not read; put those attributes on an ordinary property, or set the same fact in `map()`.

## Conventions

| Source | Column or table |
| --- | --- |
| Class `Chirp` | table `chirps` |
| Property `userId` | column `user_id` |
| Property `id` of type `int` | primary key, database-generated |
| Property typed as another model, with a `{name}Id` property on this class | `belongsTo` |
| `array<Post>` on `Blog`, and `Post` has `blogId` | `hasMany` |
| `array<Post>` when neither side has the foreign-key property | `belongsToMany`, pivot table the two snake_case names sorted and joined with `_` |

`DateTimeImmutable` properties use the built-in date cast. `bool` is stored as an integer. `int` and backed enums use the built-in casts. A nullable property allows `null` in the column.

## Attributes

Class attributes:

| Attribute | Effect |
| --- | --- |
| `#[Table('users')]` | Table name |
| `#[Timestamps]` | Maintain `created_at` and `updated_at` |
| `#[SoftDeletes]` | `deleted_at`; queries omit those rows until `withTrashed()` or `onlyTrashed()` |
| `#[Keyless]` | No primary key; the model is read-only |
| `#[Index<Post>([nameof(Post::$slug)], unique: true)]` | Index. Repeatable. Also legal on a property |
| `#[ObservedBy(PostObserver::class)]` | Observer class. Repeatable |
| `#[Discriminator('kind')]` | Column that selects the concrete class |
| `#[DiscriminatorValue('cat')]` | Value stored for this class |

Property attributes:

| Attribute | Effect |
| --- | --- |
| `#[Column('blog_id')]` | Column name. Optional second argument is the blueprint type |
| `#[MaxLength(255)]` | String length |
| `#[Precision(12, 2)]` | Decimal precision and scale |
| `#[Text]` | Text column |
| `#[DefaultValue(0)]` | Database default |
| `#[Generated]` | Value comes from the database |
| `#[Comment('...')]` | Column comment |
| `#[Key]` | Part of the primary key. Repeatable for a composite key |
| `#[NotMapped]` | Omit the property |
| `#[Cast(MoneyCast::class)]` | `Cast<TValue, TColumn>` |
| `#[AsJson]` | JSON column |
| `#[Embedded]` | Struct or object stored as prefixed columns |
| `#[Deferred]` | Left out of `SELECT` until the property is read. See [Querying](rhetoric_querying.md) |
| `#[ConcurrencyCheck]` | `save()` requires the loaded value to still match |
| `#[RowVersion]` | Concurrency token the database updates |
| `#[ForeignKey(Blog::class, onDelete: OnDelete::Cascade)]` | Foreign key target, optional referenced column, `OnDelete::Cascade`, `SetNull`, or `Restrict` |
| `#[InverseOf<Blog>(nameof(Blog::$posts))]` | Other side of the relation |

`OnDelete` is `Tyhp\Rhetoric\OnDelete`.

## Fluent mapper

`map` runs after attributes. `model<T>()` returns `ModelMapper<T>`. Property arguments are `PropertyPath` lambdas (`fn ($post) => $post->slug`).

```tyhp
<?tyhp

use Tyhp\Rhetoric\Mapping\Mapper;
use Tyhp\Rhetoric\Mapping\ModelMapping;
use Tyhp\Rhetoric\OnDelete;

protected function map(Mapper $map): void {
    $map->conventions(new AppConventions());
    $map->register(new PostMapping());

    $map->model<Post>()
        ->table('posts')
        ->comment('Published posts')
        ->key(fn ($post) => $post->id)
        ->hasIndex(fn ($post) => $post->slug)
        ->unique();

    $map->model<Post>()
        ->column(fn ($post) => $post->title)
        ->maxLength(200);

    $map->model<Post>()
        ->belongsTo(fn ($post) => $post->blog)
        ->inverseOf(fn ($blog) => $blog->posts)
        ->foreignKey(fn ($post) => $post->blogId)
        ->onDelete(OnDelete::Cascade);

    $map->model<Blog>()
        ->hasMany(fn ($blog) => $blog->posts);

    $map->model<Post>()
        ->belongsToMany(fn ($post) => $post->tags)
        ->pivotTable('post_tag')
        ->pivotColumns('post_id', 'tag_id')
        ->using<PostTag>();

    $map->model<Post>()
        ->addGlobalScope(fn ($post) => $post->deletedAt === null)
        ->softDeletes()
        ->observedBy(PostObserver::class)
        ->seed(['title' => 'Hello']);

    $map->model<Audit>()
        ->fromView('audit_posts')
        ->keyless();
}
```

`ModelMapper<T>` also has `alternateKey`, `discriminator`, `discriminatorValue`, and `extraColumn<TValue>(string $name)` for a column with no property. `ColumnMapper` has `name`, `maxLength`, `precision`, `generated`, `comment`, `type`, `text`, `default`, `cast`, `asJson`, and `embedded`. `HasMapper` is what `hasOne`, `hasMany`, and `belongsToMany` return; `hasOne` takes a single model, `hasMany` and `belongsToMany` take `array<TRelated>`. `using<TPivot>()` names the pivot model for `belongsToMany`.

A mapping class keeps one model's fluent configuration together:

```tyhp
<?tyhp

use Tyhp\Rhetoric\Mapping\ModelMapper;
use Tyhp\Rhetoric\Mapping\ModelMapping;

final class PostMapping extends ModelMapping<Post> {
    protected function configure(ModelMapper<Post> $model): void {
        $model->hasIndex(fn ($post) => $post->slug)->unique();
    }
}
```

`$map->register(new PostMapping())` applies it. `$map->intercept($interceptor)` registers a `QueryInterceptor` whose `beforeExecuting(string $sql, array $bindings, Connection $connection)` runs before each statement.

## Casts

Subclass `Tyhp\Rhetoric\Casts\Cast<TValue, TColumn>`. `get` turns a column value into the property; `set` does the reverse. `null` passes through both. Point a property at the class with `#[Cast(MoneyCast::class)]` or `->cast(MoneyCast::class)`. Built-in casts cover `int`, `bool`, `DateTimeImmutable`, and backed enums. A property of a class type that has a cast is a column, not a relation.

## Inheritance, scopes, and views

`#[Discriminator]` plus `#[DiscriminatorValue]` on each subclass is single-table inheritance. A query for a base type hydrates each row as its own class. `instanceof` and `is` in a predicate filter on the discriminator. Derived types keep the root type's global scopes and observers.

`addGlobalScope` adds a predicate to every query for that model. A scope that reads `$this` uses the context that runs the query. `withoutGlobalScopes()` skips them for one query.

`fromView` and `keyless` map a model onto a view or a table with no key. Those models are not inserted or updated.

## Observers

Subclass `Tyhp\Rhetoric\Observers\Observer` and override `creating`, `created`, `updating`, `updated`, `saving`, `saved`, `deleting`, `deleted`, `restoring`, and `restored`. Attach the class with `#[ObservedBy]` or `observedBy`.

## PHP callers

The same attributes and mapper methods are available from PHP. Call `$map->model(\App\Data\Post::class)()` and pass `\Tyhp\Expression::of` paths. See [Mapping for PHP](rhetoric_php_mapping.md).
