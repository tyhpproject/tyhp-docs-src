---
title: 'CLI: Symbol Tree'
status:
  tier: 1
  story: '13'
  state: complete
---

The `symbol_tree` action parses and binds the project (no type-check or emit) and dumps the resolved symbol environment as JSON. That is the same tree `lint`, `build`, and emit use: builtins, package tyhpdefs, overlays, and project sources.

Use it to confirm overlay last-wins, `omit`, `partial function` keep / rename, and overlay `partial class X as Y` (same symbol, extra Tyhp name) — which Tyhp names are live, their signatures, and the PHP emit name.

## Usage

```
tyhp symbol_tree [file…] [options]
tyhp symbol-tree [file…] [options]
```

```
tyhp symbol_tree
tyhp symbol_tree --filter=strtoupper
tyhp symbol_tree --out=symbols.json
tyhp symbol_tree --help
```

With no source files, the command still binds builtins and loaded tyhpdefs.

## Options

- `--filter=<substring>` — Only include symbols whose Tyhp name, FQN, or PHP emit name contains this substring (case-insensitive). A matching type includes all of its members; a matching member includes its type with that member.
- `--out=<file.json>` — Write JSON to a file instead of stdout.
- `--quiet` / `-q` — Suppress status lines on stderr.
- `--help` — Show this help (same as `tyhp help --subject=symbol_tree`).

Status lines go to stderr. The JSON document goes to stdout (or `--out`). Bind errors still write the document (with `diagnostics`) and set a non-zero exit code.

## JSON shape

Top level:

| Field | Meaning |
|-------|---------|
| `command` | `"symbol_tree"` |
| `phpVersion` | Compile-target PHP version used for this bind |
| `sourceFileCount` | Project source files parsed (tyhpdefs are extra) |
| `counts` | `namespaces`, `symbols`, `types`, `functions` after `--filter` |
| `namespaces` | Groups of declarations, empty string = global namespace |
| `diagnostics` | Parse/bind diagnostics from this run |

Each symbol includes `kind`, `name`, `fqn`, `signature`, and usually `file` / `line`. Overlay aliases add `phpName` (the PHP emit name) and `aliased: true` when that differs from the Tyhp name. Functions may list `overloads`. Types nest `members`.

```json
{
  "command": "symbol_tree",
  "phpVersion": "8.4",
  "namespaces": [
    {
      "name": "",
      "symbols": [
        {
          "kind": "function",
          "name": "str2UC",
          "fqn": "str2UC",
          "signature": "function str2UC(string $string): string",
          "phpName": "strtoupper",
          "aliased": true
        }
      ]
    }
  ]
}
```

`tokenize` and `dump_ast` are per-file lexer/parser dumps (no bind). `symbol_tree` is the bound environment.

## Related

- [Tyhpdef Overlays](tyhpdef_overlays.md) — header `;`, `partial function` keep / rename, last wins, `omit`
- [CLI: Overlay](cli_overlay.md) — `create` / `stamp`
- [CLI: Introduction](cli_intro.md) — other actions
- [Diagnostic Code Reference](diagnostics_reference.md) — `TYHP8031`–`TYHP8035`
