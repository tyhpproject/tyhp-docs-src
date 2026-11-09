---
title: 'tyhp/compiler for PHP'
---

`tyhp/compiler` puts `vendor/bin/tyhp` in a project. That script downloads the native compiler that matches the package version and forwards arguments to it. Application code does not construct the shim. `Tyhp\Compiler\Shim`, `Tyhp\Compiler\Installer`, `Tyhp\Compiler\Platform`, and `Tyhp\Compiler\HttpClient` implement the bin script.

The compiler runs at development and build time. Production runs the PHP the compiler emits, so the package belongs in `require-dev`.

## Install

PHP 8.2 or newer, and `ext-curl`. The version is the compiler version, `805.1.2-beta.4` in this package's `composer.json`. It does not use the `80N.X.Y` scheme of the other runtime packages. One version serves every PHP target. Composer also installs `tyhp/core`.

```bash
composer require --dev tyhp/compiler:805.1.2-beta.4
```

`proc_open()` must not be listed in `disable_functions`. The shim starts the native compiler with it.

The native builds are macOS (x64 and arm64), Linux (x64 and arm64), and Windows (x64).

When `tyhp/core` is in the dependency graph and the root `composer.json` does not already require `tyhp/compiler`, the `tyhp/core` Composer plugin can add `tyhp/compiler` to `require-dev`. It does nothing for a `--no-dev` install.

Composer does not run scripts declared by dependencies. Add the download to your own `composer.json`:

```json
{
    "scripts": {
        "post-autoload-dump": [
            "vendor/bin/tyhp --install-binary"
        ]
    }
}
```

`--install-binary` downloads the compiler after `composer install`, `composer update`, and `composer dump-autoload`. It does nothing when that version is already installed. You can run it yourself:

```bash
vendor/bin/tyhp --install-binary
```

## Running it

```bash
vendor/bin/tyhp build
vendor/bin/tyhp lint src/
```

The shim forwards every argument and adds none. It keeps the working directory, the environment, and standard input, output, and error. It exits with the compiler's status.

`--install-binary` is handled by the shim wherever it appears. The shim runs the installer and ignores every other argument. The flag is never passed to the compiler. It exits `0` when the compiler is installed, and `1` with a message on standard error when installation fails.

If the binary is missing, an ordinary command prints this and exits `1`:

```text
The Tyhp native compiler binary is not available.
Run `vendor/bin/tyhp --install-binary` to download it.
This can happen if `composer install` was run with `--no-scripts`, or if that post-install step failed.
```

## GitHub tokens

`--install-binary` reads `GITHUB_TOKEN` when it downloads from GitHub. When that variable is unset or empty, it reads `GH_TOKEN`. The token raises the API rate limit on shared CI runners. Public releases need no scopes.

## Production

Production servers do not need the compiler. Build in CI, then install without dev dependencies and without the download hook:

```bash
composer install --no-dev --no-scripts
```

## Related

- [Packages for PHP](php_packages.md)
- [tyhp/core for PHP](php_package_core.md)
- [The tyhp/compiler Package](package_compiler.md) — the same package, including the install layout
