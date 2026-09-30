---
title: 'CLI: Source Map Generation'
status:
  tier: 2
  story: '17'
  state: complete
---

Source maps provide a bidirectional mapping between positions in the compiled PHP output and their originating positions in the original Tyhp source files. They let `tyhp xdebug_proxy` translate breakpoints and stack frames so you can debug `.tyhp` files while PHP executes the compiled output.

## Source Map Format

When `build.generateSourcemap` is true, each `.php` output file gets a sibling `.php.map` file (Source Map v3 JSON):

```json
{
    "version": 3,
    "file": "User.php",
    "sourceRoot": "src/Models/",
    "sources": ["User.tyhp"],
    "names": [],
    "mappings": "AAAA;AACA,SAAS,..."
}
```

`sourceRoot` is the directory prefix of the registered Tyhp path (for example `src/Models/` for `src/Models/User.tyhp`), not a `../` path from the output directory. `sourcesContent` is omitted unless `build.sourcemapIncludeContent` is true. The `mappings` field is VLQ Base64-encoded position data.

## Enabling Source Map Generation

Enable source maps in `tyhp.json` and run `tyhp build`:

```json
{
    "build": {
        "generateSourcemap": true
    }
}
```

When enabled, the build writes a `.php.map` file alongside each compiled `.php` file:

```
build/
  App/
    Models/
      User.php
      User.php.map
    Services/
      Auth.php
      Auth.php.map
```

`--clean` deletes `.php` and `.php.map` files from the output directory before building. `--dry-run` does not write maps.

## Configuration Options

- `build.generateSourcemap` — Master switch (default: `false`). When true, the emitter records mappings, the writer emits `.php.map` files, and a `sourceMappingURL` comment is appended to each PHP file.
- `build.sourcemapIncludeContent` — When true, embeds the original `.tyhp` source in the map's `sourcesContent` array. This makes maps self-contained but larger (default: `false`).

## Source Mapping URL

When source maps are generated, the compiler appends a `sourceMappingURL` comment to the end of each compiled PHP file:

```php
<?php
declare(strict_types=1);

namespace App\Models;

class User {
    // ... compiled code ...
}

//# sourceMappingURL=User.php.map
```

## How Source Maps Are Used

`tyhp xdebug_proxy` loads `.php.map` files (from `output.path`, or `--sourcemap-dir`) to translate breakpoints and stack traces between `.tyhp` and `.php`. If no maps are found, the proxy still starts and warns you to rebuild with `build.generateSourcemap` enabled. See [CLI: XDebug Proxy](cli_xdebugProxy.md).

## Validation and diagnostics

When sourcemaps are on, the compiler validates each map against the generated PHP (VLQ integrity, mapping coverage, source index bounds, line counts). Failures are non-fatal warnings; the `.php` file is still written:

- `TYHP5020` — source map JSON could not be generated
- `TYHP5021` — `.php.map` could not be written
- `TYHP5022` — a mapping segment is invalid

:::note
Source map generation adds a small amount of overhead to the build. Leave `build.generateSourcemap` false when you do not need debugging support.
:::
