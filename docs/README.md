# Trix — Engineering Reference

This folder contains internal engineering documentation for `@jimdo/trix`, a fork
of [Basecamp Trix](https://github.com/basecamp/trix) maintained by Jimdo.

These docs were produced by reading the source. They are not auto-generated and
will drift as the code changes — update them with the code you touch.

## Reading order

| File | Purpose |
|---|---|
| [01-overview.md](01-overview.md) | What Trix is, what the fork adds, tech stack, output artifacts. Start here. |
| [02-build-and-test.md](02-build-and-test.md) | How to set up the Ruby toolchain, build `dist/`, run tests, publish to npm. |
| [03-architecture.md](03-architecture.md) | Layered architecture (elements, controllers, models, views, observers, operations, config). Public API and custom events. |
| [04-attribute-system.md](04-attribute-system.md) | End-to-end trace of how a text/block attribute is declared, activated, stored, rendered, serialized, and parsed. The mechanism any new attribute hooks into. |
| [05-color-feature-proposal.md](05-color-feature-proposal.md) | Concrete design proposal for a custom text-color attribute driven externally by a CMS. Minimal code change with full round-trip reasoning. |

## Conventions

- File paths are given relative to the repo root.
- Citations use `path/to/file.coffee:LINE` so you can jump straight to the code.
- CoffeeScript snippets preserve original indentation — 2 spaces, no semicolons.
- "Piece", "Block", "Text", "Document" (capitalised) refer to the Trix model
  classes in `src/trix/models/`, not to generic nouns.
