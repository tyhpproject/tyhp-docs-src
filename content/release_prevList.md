---
title: 'Previous Releases'
---

## 805.1.2-beta.3 (current public beta)

Patch on the public beta. GitHub Release tag `v805.1.2-beta.3`. MAJOR `805` means the emit ceiling is PHP 8.5 (the compiler still targets 8.2–8.4 via `output.phpVersion`). Compiled `tyhp/*` runtime helpers version independently as `80N.X.Y` (source `0.2` → `802.0.2`–`805.0.2` for `tyhp/core`). `tyhpdef/*` packages use the version in that package’s `composer.json`.

This is a **prerelease**. Semver compatibility guarantees apply from the first stable `805.N.N`, not from beta. See [Roadmap](release_roadmap.md) and [Release Planning](release_planning.md).

## 805.1.1-beta.3

An untyped local initialized with a literal now keeps the widened scalar as its declared type, so a later assignment of another value of that scalar type-checks. A tyhpdef backed enum is treated as backed when the declaration has a backing type, so case values type-check.

## Release History

| Version | Notes |
|---------|--------|
| 805.1.2-beta.3 | Public beta. |
| 805.1.1-beta.3 | Public beta. Checker fixes for literal-initialized locals and tyhpdef backed enums. |
| 805.1.0-beta.3 | Public beta. Bug fixes and updates. |
| 805.1.0-beta.2 | Public beta. Bug fixes and updates. |
| 805.1.0-beta.1 | Public beta. Tier 2 (stories 17-22). |
| 805.0.0-alpha.1 | Public alpha. Tier 1 (stories 01–16.5) plus generic type-parameter defaults, sourcemaps, Xdebug proxy, `tyhp language_server`, `generate_tyhpdef`, and `tyhpdef/php` / `tyhpdef/php-ext-*`. |

:::note
Compiler MAJOR encodes the highest supported PHP version (`805` = PHP 8.5 and below). Tyhp syntax removal happens on MINOR. Runtime Composer packages do **not** use the compiler version string. See Release Planning.
:::
