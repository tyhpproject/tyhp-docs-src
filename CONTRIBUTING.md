# Contributing to Tyhp documentation

Issues and pull requests are welcome. Read this before opening either.

## Legal

You will need to complete a Contributor License Agreement (CLA). Briefly, this agreement testifies that you are granting us permission to use the submitted change according to the terms of the project's license, and that the work being submitted is under appropriate copyright. Upon submitting a pull request, you will automatically be given instructions on how to sign the CLA.

The Tyhp documentation is under the [Apache License 2.0](LICENSE.txt). The CoderDocs theme and Font Awesome files in `CoderDocs-BS5-v3.0/` have their own licenses and must stay in this repository with the site. Keep the footer attribution. Do not publish the theme as its own product.

## Generate the site

You need PHP 8.2+, Composer, the `sass` command, and `zip`.

```bash
git clone https://github.com/tyhpproject/tyhp-docs-src.git
cd tyhp-docs-src
composer install
php generate_docs.php
```

That writes `output/` and `output.zip`. Open `output/index.html` to review the pages.

## Diagnostic code index

Do not hand-edit message entries in `content/diagnostics_reference.md`. Add the code in `MessageCode.cs` in the [tyhp](https://github.com/tyhpproject/tyhp) compiler, then from that checkout run:

```bash
scripts/sync-diagnostics-reference.sh
```

The script writes this repo's `content/diagnostics_reference.md` when `tyhp-docs-src` is a sibling clone, or when `TYHP_DOCS_SRC` points here.

## Pull requests

- Target `main`.
- Keep changes focused. A page edit should not include an unrelated generator change.
- `content/toc.json` must list every published page. A missing or non-Markdown item fails `php generate_docs.php`.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
