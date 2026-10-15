---
title: 'The tyhp/compiler Package'
---

`tyhp/compiler` puts the Tyhp compiler into your project through Composer. It provides `vendor/bin/tyhp`, which is a small PHP script (a *shim*). The shim downloads the native Tyhp compiler that matches the package version, then forwards every command to that compiler.

The compiler only runs at development and build time. Your application runs the PHP that the compiler emits. For that reason the package belongs in `require-dev`, and production installs can leave it out.

Installing the compiler per project through Composer has three benefits:

- Every developer and every CI job uses the same compiler version, because `composer.lock` pins it.
- Projects on one machine can use different compiler versions.
- No global install is needed. `composer install` is enough.

For the commands the compiler supports, see [CLI: Introduction](cli_intro.md). This page covers how the package installs and runs the compiler.

## Installing

New projects get the package from [`tyhp init`](intro_installation.md). To add it to an existing Composer project, run:

```bash
composer require --dev tyhp/compiler
```

Requirements:

| Requirement | Notes |
|-------------|-------|
| PHP 8.2 or newer | Runs the shim and the download. |
| `ext-curl` | Composer requires it to install the package. Only `--install-binary` uses it, to download the compiler; running an installed compiler doesn't. |
| `proc_open()` | The shim starts the native compiler with `proc_open()`, so the function must not be listed in `disable_functions`. |
| `tyhp/core` | Composer installs it automatically. |
| A supported platform | macOS (x64 and arm64), Linux (x64 and arm64), or Windows (x64). |

### The install hook

Composer doesn't run scripts declared by dependencies, so the download is triggered by a script in **your** `composer.json`. `tyhp init` adds these entries:

```json
{
    "scripts": {
        "tyhp": "vendor/bin/tyhp",
        "post-autoload-dump": [
            "vendor/bin/tyhp --install-binary",
            "vendor/bin/tyhp generate_tyhpdef --vendor"
        ]
    },
    "scripts-descriptions": {
        "tyhp": "Forward extra args to the Tyhp CLI (e.g. composer tyhp build)"
    }
}
```

- `vendor/bin/tyhp --install-binary` downloads the compiler after every `composer install`, `composer update`, and `composer dump-autoload`. It does nothing when the right version is already installed.
- `vendor/bin/tyhp generate_tyhpdef --vendor` generates type definitions for your PHP dependencies. See [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md).
- The `tyhp` script lets you run `composer tyhp build`, `composer tyhp lint`, and so on.

If your project sets Composer's `config.bin-dir`, `tyhp init` writes that directory instead of `vendor/bin`.

If you add the package by hand, add at least the `--install-binary` entry to `post-autoload-dump`. Without it, the first run reports that the compiler binary isn't available. You can also run the install step yourself:

```bash
vendor/bin/tyhp --install-binary
```

## Running the compiler

Run `vendor/bin/tyhp` exactly as you would run `tyhp`:

```bash
vendor/bin/tyhp build
vendor/bin/tyhp lint src/
composer tyhp build --watch
```

The shim passes every argument through unchanged and adds none of its own. The native compiler runs with the same working directory, environment variables, standard input, standard output, and standard error. No shell is involved, so arguments are never re-split or expanded. The shim exits with the compiler's exit code (for example, `tyhp lint` exit codes are listed in [CLI: Lint](cli_lint.md)).

The shim handles one flag itself: `--install-binary`. When that flag appears anywhere in the arguments, the shim runs the installer and ignores every other argument. The flag is never passed to the compiler. It exits with `0` when the compiler is installed (or already was) and `1` with a message on standard error when installation fails.

Ordinary commands never download anything. If the compiler binary is missing, the shim prints this message and exits with `1`:

```text
The Tyhp native compiler binary is not available.
Run `vendor/bin/tyhp --install-binary` to download it.
This can happen if `composer install` was run with `--no-scripts`, or if that post-install step failed.
```

On Windows, Composer creates `vendor\bin\tyhp.bat`, so `vendor\bin\tyhp build` works from `cmd.exe` and PowerShell.

## How the binary is installed

`vendor/bin/tyhp --install-binary` takes these steps.

1. **Find the release tag.** The tag is `v` followed by the version of the installed `tyhp/compiler` package. For example, package version `805.1.0` downloads release `v805.1.0`. The installer reads the version from the package's own `composer.json`.
2. **Skip the download if it's already done.** If the binary exists, is not empty, is executable, and its version stamp matches the tag, the installer stops here.
3. **Detect the platform** from PHP's `PHP_OS_FAMILY` and `php_uname('m')`.
4. **Choose the build variant.** The installer runs `dotnet --list-runtimes`. If the output lists a `Microsoft.NETCore.App 9.x` runtime, it downloads the smaller framework-dependent build. Otherwise (no `dotnet` command, or no .NET 9 runtime) it downloads the self-contained build, which needs no .NET installation.
5. **Look up the release** at `https://api.github.com/repos/tyhpproject/tyhp/releases/tags/{tag}`.
6. **Download `checksums.txt` and the binary** from the release, following redirects. Each request has a 120-second timeout.
7. **Verify the SHA-256 checksum.** The binary is installed only if its hash matches the entry for its asset in `checksums.txt`. A missing entry or a mismatch stops the installation.
8. **Install the binary.** The installer moves the binary into the package's `native/` directory, marks it executable on macOS and Linux, and writes the tag to `native/version`.

The download goes to the system temporary directory first. A failed or rejected download never replaces a working binary.

### Release assets

| Platform | Self-contained asset | Framework-dependent asset (.NET 9 installed) |
|----------|----------------------|-----------------------------------------------|
| macOS, Apple silicon | `tyhp-osx-arm64` | `tyhp-osx-arm64-fxdependent` |
| macOS, Intel | `tyhp-osx-x64` | `tyhp-osx-x64-fxdependent` |
| Linux, x64 | `tyhp-linux-x64` | `tyhp-linux-x64-fxdependent` |
| Linux, arm64 | `tyhp-linux-arm64` | `tyhp-linux-arm64-fxdependent` |
| Windows, x64 | `tyhp-win-x64.exe` | `tyhp-win-x64-fxdependent.exe` |

The architecture names `x86_64` and `amd64` map to x64, and `arm64` and `aarch64` map to arm64. Windows on arm64 has no release asset.

### Files on disk

| Path | Contents |
|------|----------|
| `vendor/tyhp/compiler/native/tyhp` | The native compiler (`tyhp.exe` on Windows). |
| `vendor/tyhp/compiler/native/version` | The release tag that was installed, such as `v805.1.0`. |

Composer replaces the whole `vendor/tyhp/compiler/` directory when the package version changes, so the `native/` directory disappears with it. The `post-autoload-dump` hook downloads the new version right away.

:::note
`--install-binary` keeps an existing binary whenever the version stamp matches, no matter which variant it is. To switch between the framework-dependent and self-contained builds, or to replace a damaged binary, delete `vendor/tyhp/compiler/native/` and run `vendor/bin/tyhp --install-binary` again.
:::

## Versions

The `tyhp/compiler` version is the compiler version. It does not use the `80N.X.Y` PHP-target scheme of the runtime packages, so a single version serves every PHP target. See [Composer Runtime Packages](project_composerPackages.md) for how runtime package versions work.

To upgrade the compiler, update the package:

```bash
composer update tyhp/compiler
```

Composer installs the new package version, and the `post-autoload-dump` hook downloads the matching binary. To check which compiler is running, use `vendor/bin/tyhp version`.

Ordinary commands don't compare the installed binary with the package version. If the hook was skipped during an update, run `vendor/bin/tyhp --install-binary` before you build.

## Relationship with `tyhp/core`

`tyhp/compiler` depends on `tyhp/core`, and `tyhp/core` includes a Composer plugin that keeps the compiler pin in place:

- When `tyhp/core` is anywhere in the dependency graph and your root `composer.json` doesn't already require `tyhp/compiler`, the plugin adds `"tyhp/compiler": "@dev"` to root `require-dev` while Composer resolves dependencies.
- The plugin does nothing when Composer runs without dev dependencies (`--no-dev`, `COMPOSER_NO_DEV`, or `COMPOSER_DEV_MODE=0`).
- The plugin runs only if Composer is allowed to run it. `tyhp init` sets `config.allow-plugins.tyhp/core` to `true`.

`tyhp build` and `tyhp lint` also check for the pin. When it is missing, they report warning [`TYHP7702`](diagnostics_reference.md) (`` `tyhp/compiler` is missing from root require-dev while `{0}` is in the graph ``). With `--strict` the warning fails the run. `tyhp composer sync` and `tyhp build --fix` write the missing pin. See [CLI: Composer](cli_composer.md).

`tyhp init`, `tyhp composer sync`, and `tyhp build --fix` write an exact compiler version (the version of the `tyhp/compiler` package that matches the CLI). The plugin writes `@dev`, which accepts the newest available version. Replace either with a specific constraint if you want to control upgrades.

## Environment variables

| Variable | Effect |
|----------|--------|
| `GITHUB_TOKEN` | Sent as a GitHub API token when `--install-binary` downloads from GitHub. It raises the API rate limit, which matters on shared CI runners. |
| `GH_TOKEN` | Used instead when `GITHUB_TOKEN` is unset or empty. |

The token needs no scopes, because the releases are public. The shim reads no other environment variables. The native compiler sees your environment unchanged.

## CI pipelines

A normal `composer install` installs the compiler through the hook, so CI needs no extra step. Provide a GitHub token so that many jobs sharing an IP address don't hit the anonymous API rate limit:

```yaml
- name: Install dependencies
  run: composer install --no-interaction --no-progress
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

- name: Lint
  run: vendor/bin/tyhp lint

- name: Build
  run: vendor/bin/tyhp build
```

The binary lives inside `vendor/`. If you cache `vendor/` keyed on `composer.lock`, the binary is cached with it, and the hook skips the download on later runs.

If your pipeline runs `composer install --no-scripts`, run the install step yourself before using the compiler:

```bash
composer install --no-interaction --no-scripts
vendor/bin/tyhp --install-binary
vendor/bin/tyhp build
```

:::warning
The variant is chosen on the machine that runs `--install-binary`. If an image with .NET 9 installs the compiler and you then copy `vendor/` into an image without .NET, the copied binary is the framework-dependent build and won't start. Install the compiler in the image that runs it, or make sure .NET 9 is not present where it is installed.
:::

## Production deployments

Production servers run the emitted PHP and don't need the compiler. Build the PHP in CI, then deploy it with dev dependencies left out:

```bash
composer install --no-dev --no-scripts --optimize-autoloader
```

Use `--no-scripts` together with `--no-dev`. Without it, Composer still runs the root `post-autoload-dump` hook. The hook calls `vendor/bin/tyhp`, which doesn't exist in a `--no-dev` install, and the install fails with an error such as `sh: vendor/bin/tyhp: No such file or directory`. `--no-scripts` also skips any other root scripts, so run the ones your deployment needs explicitly.

## Restricted networks

`--install-binary` needs HTTPS access to `api.github.com` and to the hosts that GitHub release downloads redirect to. Behind a proxy, configure it for PHP's cURL extension, for example with the `https_proxy` environment variable.

If the build machine can't reach GitHub, use one of these approaches:

- **Install the compiler globally** from the GitHub release with the standalone installer (see [Installing Tyhp](intro_installation.md)), and run `tyhp` instead of `vendor/bin/tyhp`.
- **Place the binary yourself.** Download the asset for your platform and `checksums.txt` from the release that matches your package version, and check the SHA-256 hash. Then copy the binary to `vendor/tyhp/compiler/native/tyhp` (`tyhp.exe` on Windows), make it executable, and write the tag, such as `v805.1.0`, to `vendor/tyhp/compiler/native/version`. `--install-binary` then finds a matching binary and makes no network request.

## Troubleshooting

All of these messages are printed to standard error, and the shim exits with `1`.

| Message | Cause and fix |
|---------|---------------|
| ``The Tyhp native compiler binary is not available.`` | The binary was never downloaded, or the hook failed or was skipped with `--no-scripts`. Run `vendor/bin/tyhp --install-binary` and read its error if it fails. |
| ``tyhp: Composer autoloader not found. Run `composer install` in the project that requires tyhp/compiler.`` | The shim was started outside a Composer install, or `vendor/autoload.php` is missing. Run `composer install`. |
| ``The curl PHP extension is required to download the Tyhp compiler binary.`` | Enable `ext-curl` for the PHP that runs Composer, then run `vendor/bin/tyhp --install-binary`. |
| ``Download failed for {url}: {error}`` | The request didn't complete because of DNS, TLS, proxy, or timeout problems. Check network access to GitHub. See [Restricted networks](#restricted-networks). |
| ``HTTP 403 from https://api.github.com/repos/tyhpproject/tyhp/releases/tags/{tag}: …`` | Usually the anonymous GitHub API rate limit. Set `GITHUB_TOKEN` or `GH_TOKEN` and retry. |
| ``GitHub release tag `{tag}` was not found on tyhpproject/tyhp.`` (GitHub's own message may follow the repository name in parentheses) | No release exists for the package version. This happens with development checkouts of the package. Require a released version of `tyhp/compiler`. |
| ``GitHub release {tag} has no asset named `{asset}`.`` | That release has no build for your platform or variant. If .NET 9 is installed, try a machine without it (the self-contained asset), or use another release. |
| ``Tyhp CLI has no GitHub Release asset for {os}/{machine}. …`` | Your OS or CPU isn't supported, for example Windows on arm64. The shim reports this for every command, not only `--install-binary`. |
| ``checksums.txt has no SHA-256 for `{asset}`. Refusing to install an unverified binary.`` | The release is missing a checksum for your asset. Nothing was installed. Use another release. |
| ``SHA-256 mismatch for `{asset}`: expected {hash}, got {hash}. The download may be corrupt or tampered with.`` | The download was damaged or altered, often by a proxy that rewrites responses. Nothing was installed. Retry, or download from another network. |
| ``Downloaded artifact `{asset}` is empty.`` | The server returned an empty body. Retry. |
| ``Failed to create {dir}.`` / ``Failed to place native binary at {path}.`` / ``Failed to open {path} for writing.`` | The user running Composer can't write to `vendor/tyhp/compiler/native/` or to the system temporary directory. Fix the permissions. |
| ``composer.json not found at {path}; cannot pin the compiler release tag.`` (or ``… has no version …``, ``… could not be parsed …``) | The installed package is incomplete. Reinstall it with `composer reinstall tyhp/compiler`. |
| ``Failed to launch the Tyhp native compiler at {path}.`` | PHP couldn't start the binary. Delete `vendor/tyhp/compiler/native/` and run `vendor/bin/tyhp --install-binary` again. |

If the compiler starts but immediately reports that a .NET runtime is missing, the framework-dependent build was installed on a machine without .NET 9. Delete `vendor/tyhp/compiler/native/` and run `vendor/bin/tyhp --install-binary` on the machine that runs the compiler.

## Related pages

- [Installing Tyhp](intro_installation.md): setting up a new project and the global installer.
- [CLI: Introduction](cli_intro.md): every compiler command.
- [CLI: Build](cli_build.md): `tyhp build`, `--strict`, and `--fix`.
- [CLI: Composer](cli_composer.md): `tyhp composer sync` and how the compiler keeps `composer.json` in step.
- [Composer Runtime Packages](project_composerPackages.md): runtime package versions and `extra.tyhp.require`.
- [CLI: Tyhpdef Generation](cli_tyhpdefGeneration.md): what the `generate_tyhpdef --vendor` hook does.
- [The tyhp/core Package](package_core.md): the runtime library and its Composer plugin.
