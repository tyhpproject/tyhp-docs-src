# Tyhp documentation

Source for the Tyhp documentation site at [tyhplang.com](https://tyhplang.com).

Pages are Markdown with YAML front matter. `php generate_docs.php` builds them into a static HTML site. Publishing copies that HTML to [tyhpproject/tyhp-docs](https://github.com/tyhpproject/tyhp-docs) (GitHub Pages, CNAME `tyhplang.com`).

The compiler, CLI, and language server live in [tyhp](https://github.com/tyhpproject/tyhp). This repository is only the documentation source.

Licensed under the [Apache License 2.0](LICENSE.txt).

The CoderDocs theme and Font Awesome files under `CoderDocs-BS5-v3.0/` are included so this site can be built. They are not a separate product. Keep the footer attribution. Their licenses stay with those files:

- `CoderDocs-BS5-v3.0/license.txt`
- `CoderDocs-BS5-v3.0/assets/fontawesome/LICENSE.txt`

## Clone and build

You need PHP 8.2+, [Composer](https://getcomposer.org/download/), the `sass` command, and `zip`.

```bash
git clone https://github.com/tyhpproject/tyhp-docs-src.git
cd tyhp-docs-src
composer install
php generate_docs.php
```

Output is written to `output/` and zipped as `output.zip`. `output/` is gitignored.

`composer.json` vendors `league/commonmark`, `symfony/yaml`, and `colinodell/json5`. The committed `vendor/` directory is part of this tree so a checkout can generate without a fresh install; run `composer install` after dependency changes.

## Compiler and the diagnostic index

Diagnostic codes are added in the compiler (`MessageCode.cs`) first. `content/diagnostics_reference.md` is generated from that registry. From a sibling `tyhp` checkout:

```bash
../tyhp/scripts/sync-diagnostics-reference.sh
```

Set `TYHP_DOCS_SRC` to this clone when it is not `../tyhp-docs-src`.

## Publish

`scripts/publish-docs.sh` runs the generator and rsyncs the HTML to `tyhpproject/tyhp-docs`. It pushes that public repository. Pull requests in this repo do not publish the site.

## Content layout

| Path | Role |
|------|------|
| `content/toc.json` | JSON5 table of contents (section metadata + item list) |
| `content/*.md` | Doc pages referenced by the TOC |
| `content/_template.md` | Dialect reference / examples (not listed in the published TOC) |
| `template/` | HTML templates and theme SCSS |
| `generator-src/` | PHP build pipeline (`Tyhp\Docs\`) |

TOC item entries must be `.md` files that exist under `content/`. Missing or non-Markdown items fail the build.

## Front matter

```yaml
---
title: Page title
status:
  tier: 0
  story: "08"
  state: planned
---
```

- `title` (required) — used for the page heading, `<title>`, and sidebar label
- `status` (optional) — implementation badge (`tier`, `story` or `stories`, `state`)

## Markdown dialect

CommonMark plus GFM pipe tables: headings, paragraphs, lists, emphasis, links, inline code, raw HTML (allowed), and `| … |` tables.

### Admonitions

Opening line is `:::type` (optional title after the type). Closing line is exactly `:::`.

| Form | Renders as |
|------|------------|
| `:::tip` / `:::note` / `:::warning` / `:::danger` | Callout boxes |
| `:::warning Custom title` | Callout with custom title |
| `:::alert{style=primary}` | Bootstrap alert (`style` = primary, secondary, …) |
| `:::member[identifier]` | Member/API card with `identifier` as the heading |

Inner content is Markdown (rendered once; nesting admonitions is not required).

### Fenced code

Normal fences use language tags and themed templates:

````markdown
```tyhp
<?tyhp
string $x = "hello";
```

```php
<?php
$x = "hello";
```

```json
{ "ok": true }
```
````

Unknown languages use the generic code-block template.

### Magic YAML fences

If the info string contains `status`, `classdef`, or `functiondef` (alone or after `yaml`), the fence body is YAML and rendered specially:

````markdown
```status
tier: 1
story: "16"
state: planned
```

```classdef
type: class
identifier: Example
members:
  - type: property
    def: { modifiers: public, type: string, identifier: $name }
```

```functiondef
modifiers: public static
identifier: example
parameters:
  - { type: string, identifier: $name }
returnType: void
```
````

## One-shot converter

`tools/convert_json_to_md.php` converted the historical JSON5 pages to Markdown. It is kept for reference; content is Markdown.
