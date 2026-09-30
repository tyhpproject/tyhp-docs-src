---
title: 'CLI: Language Server (LSP)'
status:
  tier: 2
  story: '19'
  state: complete
---

The `language_server` action starts the Tyhp Language Server Protocol (LSP) server. It uses the same parse, bind, and check pipeline as `tyhp lint`, then keeps that analysis live as you edit.

## Usage

```
tyhp language_server [options]
```

## How It Works

The language server is a long-running process that communicates with your editor over stdin/stdout. When it starts, it loads the `tyhp.json` given by `--tyhp-project` (or `./tyhp.json`), discovers source and tyhpdef files, and builds an initial representation of the project. As you edit files, it incrementally re-processes changed documents (debounced) and publishes diagnostics.

`--stdio` is accepted and is the default transport. `--tcp` and `--pipe` are listed by `tyhp help` but are not implemented: passing either flag prints an error and exits.

## Features

- Diagnostics — The same errors and warnings as `tyhp lint`, updated as you type.
- Completions — Context-aware completion for variables, functions, classes, methods, properties, types, keywords, and import suggestions (with `completionItem/resolve`).
- Hover — Resolved type, signature, and tyhpdef documentation.
- Go to Definition — Navigate to the declaration of a symbol.
- Find References — Find usages of a symbol across the project.
- Rename — Rename a symbol and update references (`textDocument/prepareRename` and `textDocument/rename`).
- Document Highlights — Read/write highlights for occurrences in the current file.
- Document Symbols — Outline of declarations in the current file.
- Signature Help — Parameter hints while typing calls (triggered by `(` and `,`).
- Folding Ranges — Foldable regions for classes, functions, blocks, multi-line comments, and import groups.
- Code Actions — Quick fixes for auto-importing missing types and removing unused `use` statements, plus organize-imports.
- Formatting — Document formatting sorts `use` statements and normalizes indentation. Range formatting normalizes indentation only (it does not sort `use` statements).
- Selection Range — Smart selection expansion from token to expression, statement, block, function, class, and file.
- Semantic Tokens — Semantic highlighting from binder results (full document plus delta; range tokens are not advertised).
- Workspace Symbols — Search for a symbol across the project by name.

## IDE Integration

The Tyhp Language extension for VS Code / Cursor and the Tyhp Language plugin for PhpStorm start one `tyhp language_server` process per owned `tyhp.json`:

```
tyhp language_server --quiet --stdio --tyhp-project=<path-to-tyhp.json>
```

Point `tyhp.path` at your `tyhp` CLI if it is not on `PATH`. Extra tokens go in `tyhp.languageServer.args`.

Any other LSP client can launch the same command. Editors with LSP support include Sublime Text (LSP package), Neovim (nvim-lspconfig), Emacs (lsp-mode or eglot), and Helix.

## Options

- `--tyhp-project=<path>` — Path to the `tyhp.json` project file. The language server uses this to discover source files and configuration.
- `--stdio` — Communicate via stdin/stdout (default; the only transport implemented).
- `--quiet` — Suppress the startup banner (useful when the editor captures stderr).
- `--pid-file=<path>` — Write the process id to this file while the server is running. Opt-in; nothing is written by default.
- `--help` — Display help (`tyhp help --subject=language_server`).

:::note
The language server is a long-running process. Editors start it automatically. Use Ctrl+C to stop it if you run it from the command line.
:::
