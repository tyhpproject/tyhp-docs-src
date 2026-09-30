---
title: 'Structs in Tyhpdef'
status:
  tier: 0
  story: '02'
  state: complete
---

Tyhpdef lets you define structs that describe PHP associative array structures to the Tyhp compiler. Structs are value types backed by arrays in PHP but treated as typed objects in Tyhp, providing compile-time property access checking, default values, and structural type compatibility. A struct defined in Tyhpdef works exactly the same as one defined in regular Tyhp code.

:::note
`#[\Tyhp\Php]` is **illegal** on a `struct` declaration (**TYHP4304**), including in `.tyhpdef`. Wrap the struct in `declare(php=…)` instead — see [PHP Version Gating](tyhp_0320_phpVersionGating.md#structs-and-extensions).
:::

## Basic Struct Declaration

A named struct is a `type` alias whose right-hand side is a struct shape. Properties do not have visibility modifiers — all struct properties are public. Inline `struct { … }` is also legal in type position (parameters, returns, unions).

```tyhp
<?tyhpdef

type Credentials = struct {
    string $username;
    string $password;
};
```

This struct describes PHP arrays of the shape `['username' => 'admin', 'password' => 'secret']`. In Tyhp code, you access struct properties with arrow syntax (`$creds->username`) and the compiler translates that to array key access.

## Required vs Optional Properties

A property is required if it is non-nullable and has no default value. A property is optional if it is nullable without a default — it may or may not be present in the array.

```tyhp
<?tyhpdef

type UserProfile = struct {
    string $name;              // Required: non-nullable, no default
    string $email;             // Required
    ?string $bio;              // Optional: nullable, no default
    string $role = "user";     // Has a default value
    ?int $age;                 // Optional
};
```

## Property Aliases

PHP associative arrays can have keys that are not valid PHP variable names. Property aliases let you map a readable Tyhp property name to an arbitrary string array key using the `'key' as $name` syntax.

```tyhp
<?tyhpdef

type EmailEnvelope = struct {
    string $to;
    string $subject;
    string $body;
    ?string 'fromEmailAddress' as $from;
    ?string 'Reply-To' as $replyTo;
    ?string 'Unsubscribe Link @ Your \"Domain\"' as $unsubscribeLink;
};
```

With this declaration, `$envelope->replyTo` in Tyhp compiles to `$envelope['Reply-To']` in PHP.

## Default Values

Properties can have default values. When a struct is instantiated, properties with defaults use those values unless overridden.

```tyhp
<?tyhpdef

type DatabaseConfig = struct {
    string $host = "localhost";
    int $port = 3306;
    string $charset = "utf8mb4";
    ?string $database;
    ?string $username;
    ?string $password;
};
```

## Struct Inheritance

Structs can extend other structs using the `extends` keyword. The child struct inherits all properties from the parent and can add new ones.

```tyhp
<?tyhpdef

type BaseEntity = struct {
    int $id;
    string $createdAt;
    string $updatedAt;
};

type UserEntity = struct extends BaseEntity {
    string $name;
    string $email;
    ?string $avatar;
};
```

:::note
Struct inheritance is structural, not nominal. A struct that happens to have the same properties as another struct is compatible with it, regardless of whether it explicitly extends it.
:::

## Nested Structs

Struct properties can reference other struct types, creating nested structures.

```tyhp
<?tyhpdef

type Address = struct {
    string $street;
    string $city;
    string $state;
    string $zipCode;
    string $country = "US";
};

type Company = struct {
    string $name;
    Address $headquarters;
    ?Address $mailingAddress;
    array<string> $departments;
};
```

## Generic Structs

Structs support generic type parameters, making them reusable across different types.

```tyhp
<?tyhpdef

type ApiResponse<T> = struct {
    bool $success;
    ?T $data;
    ?string $error;
    int $statusCode;
};

type PaginatedResult<T> = struct {
    array<T> $items;
    int $total;
    int $page;
    int $perPage;
    bool $hasMore;
};
```

## Inline struct types

A struct shape may appear in type position without an alias name. Group it with parentheses when it is an arm of `|` / `&`.

```tyhp
<?tyhpdef

function origin(): struct { float $lat; float $lng; };

function maybeOrigin(): (struct { float $lat; float $lng; }) | null;
```

## Using Tyhpdef Structs with Functions

Tyhpdef structs are commonly used to describe the shape of arrays accepted or returned by PHP functions.

```tyhp
<?tyhpdef

type MailOptions = struct {
    string $to;
    string $subject;
    string $body;
    ?string $from;
    ?array<string> $cc;
    ?array<string> $bcc;
};

function sendMail(MailOptions $options): bool;
function getMailConfig(): MailOptions;
```

## Best Practices

:::tip
DO use property aliases when the PHP array keys contain spaces, special characters, or are not valid PHP identifiers. This gives you clean Tyhp property names while matching the actual array structure.
:::

:::tip
DO use nullable types without defaults for truly optional properties. This tells Tyhp the key may not exist in the array.
:::

:::danger
DON'T add visibility modifiers (public, protected, private) to struct properties. All struct properties are implicitly public.
:::

:::danger
DON'T declare methods on structs. Structs are data-only structures — use classes or interfaces for behavior.
:::
