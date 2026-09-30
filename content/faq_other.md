---
title: 'FAQ: Other'
---

## How can I contribute to Tyhp?

Tyhp is an open-source project and welcomes contributions. See [CONTRIBUTING.md](https://github.com/tyhpproject/tyhp/blob/main/CONTRIBUTING.md) in the [tyhpproject/tyhp](https://github.com/tyhpproject/tyhp) repository.

## Where do I report bugs?

Report bugs on the [GitHub issue tracker](https://github.com/tyhpproject/tyhp/issues). Include the Tyhp source code that triggers the issue, the expected behavior, the actual behavior (error message or incorrect output), your Tyhp compiler version (run `tyhp version`), and the target PHP version from your `tyhp.json`. Providing a minimal reproduction case helps resolve issues faster.

## Is there a Tyhp community?

Yes. The Tyhp community is centered around the project's repository and issue tracker. This is where discussions about language design, new features, and implementation details take place. Feature requests and design proposals are welcome as issues.

## What is on the roadmap?

The Tyhp roadmap includes ongoing work across several areas:

- Language features — continued expansion of the type system, pattern matching, and language ergonomics.
- Tooling — language server (`tyhp language_server`), sourcemaps, Xdebug proxy, and further IDE integrations.
- Performance — incremental compilation improvements, dependency-aware rebuilds, and build caching.
- Ecosystem — tyhpdef packages for popular PHP libraries and frameworks, and deeper Composer integration.
- Documentation — expanded guides, tutorials, and reference documentation.

## How do I request a feature?

Open an issue in the project's issue tracker with a clear description of the feature, the problem it solves, and ideally example Tyhp code showing how the feature would be used. Design proposals that consider both the Tyhp syntax and the compiled PHP output are especially helpful.

## How does Tyhp compare to TypeScript?

The usual comparison is TypeScript’s relationship to JavaScript: both are typed supersets that compile to the original runtime’s language. Similarities include type erasure, gradual adoption, and using the existing ecosystem. Differences are the target runtime (PHP vs JavaScript) and the extra constructs Tyhp adds — structs, operator overloads, extension methods, and decimal types among them.

## Can I gradually adopt Tyhp in an existing PHP project?

Yes. You can add `.tyhp` files alongside existing PHP files in the same project. Start by writing tyhpdef files to describe your existing PHP code, then write new code in Tyhp. The emitted PHP is ordinary PHP, so it can sit next to code you already have. You do not need to convert an entire project at once.

## What does 'Tyhp' stand for?

It is a name, not an acronym. The letters nod to PHP; that is etymology, not a claim that Tyhp is PHP. Tyhp is a typed superset of the PHP language.
