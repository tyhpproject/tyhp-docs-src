---
title: 'Templates'
---

A `.tyhp` file can mix Tyhp statements and HTML. Between `<?tyhp` blocks, the HTML is emitted as written. `<?= expr ?>` is a Tyhp echo: the expression is parsed and checked as Tyhp, and the compiler emits `echo` with no escaping. In a `.php` file, `<?=` stays a PHP echo and is not type-checked.

A template is a function or method. Its parameters are the template's types. `include` and `require` are TYHP4801, so a template is called, not included. See [Including Files](tyhp_0300_includingFiles.md).

## Echo

```tyhp
<?tyhp

class Person {
    public function __construct(public string $name) {}
}

function userCard(Person $user): void { ?>
    <h1><?= $user->name ?></h1>
<?tyhp }
```

The heading is emitted as `echo $user->name;`.

Tyhp keywords are active inside the echo. `is`, `typeof`, `with`, and `nameof` parse as Tyhp:

```tyhp
<?tyhp

function label(mixed $x): void { ?>
    <span><?= $x is string ? $x : "" ?></span>
<?tyhp }
```

A comma-separated list is one echo, the same as PHP: `<?= $title, $title ?>` emits `echo $title, $title;`.

The expression follows the same rules as `echo`. A value that cannot be echoed is **TYHP4120**. A missing member is **TYHP4101**. The diagnostic is reported on the `.tyhp` line of the `<?= ?>` tag.

Nothing is escaped. Encode the text yourself when the value is not trusted, the same as a PHP `<?=`.

## Loops and conditionals

Loops and conditionals are `<?tyhp` blocks around the HTML. The alternative syntax `if (…):` / `endif;` and `foreach (…):` / `endforeach;` parses and checks. The emitter writes ordinary brace `if` and `foreach`.

```tyhp
<?tyhp

function listItems(array<string> $items, bool $show): void {
    if ($show):
        ?>
        <p>shown</p>
        <?tyhp
    endif;
    foreach ($items as string $item):
        ?>
        <li><?= $item ?></li>
        <?tyhp
    endforeach;
}
```

## Whitespace

HTML is emitted as it appears in the `.tyhp` file, including indentation that sits in the source before `<?tyhp`. The pretty-printer does not reindent that HTML. A single newline directly after `?>` is swallowed, the same as PHP. The spaces on the following line are part of the output.

```tyhp
<?tyhp

function heading(string $title): void { ?>
    <h1><?= $title ?></h1>
<?tyhp }
```

The four spaces before `<h1>` are printed. The newline between `?>` and those spaces is not.

## Tagless projects

`source.tagless` forbids `?>`, so a template has to be a tagged file. In a tagless project, a `.tyhp` file whose first six characters are `<?tyhp` is that tagged file: an empty first section is allowed, then HTML, `<?=`, and a later `<?tyhp`. Any other `.tyhp` file is code with no open tag. See [The `<?tyhp` and `<?tyhpdef` Open Tags](tyhp_0000_openTag.md#templates-in-a-tagless-project).

## Capturing the HTML

Call the template and capture its output the same way as PHP:

```tyhp
<?tyhp

function html(Person $user): string|false {
    \ob_start();
    userCard($user);
    return \ob_get_clean();
}
```
