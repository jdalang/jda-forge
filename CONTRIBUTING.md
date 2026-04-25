# Contributing to JDA Forge

First off — thank you. Every bug report, documentation fix, and pull request makes Forge better for everyone building with JDA. This guide explains how to get involved.

---

## Table of Contents

1. [Ways to contribute](#ways-to-contribute)
2. [Development setup](#development-setup)
3. [Project structure](#project-structure)
4. [Making changes](#making-changes)
5. [Submitting a pull request](#submitting-a-pull-request)
6. [Reporting bugs](#reporting-bugs)
7. [Suggesting features](#suggesting-features)
8. [Code style](#code-style)
9. [Community](#community)

---

## Ways to contribute

You do not need to write code to contribute. Some of the most valuable contributions are:

- **Fix a typo or clarify a doc** — open a PR directly, no issue needed
- **Add a missing example** — the `examples/` directory welcomes real-world patterns
- **Report a bug** — a clear reproduction case is worth a lot
- **Answer a question** in a GitHub issue or discussion
- **Write a library** — Forge libraries are plain `.jda` files; publish one and add it to the registry

If you want to add a new feature or make a significant change, open an issue first so we can discuss the approach before you invest time writing code.

---

## Development setup

### Prerequisites

- **JDA compiler** — `jda` on your `PATH`. Install from [github.com/jdalang/jda](https://github.com/jdalang/jda/releases).
- **Git**
- **GNU Make**
- **PostgreSQL** (for running the blog example)

### Clone and run

```bash
git clone https://github.com/jdalang/jda-forge.git
cd jda-forge
```

The repository is self-contained. `forge.jda` is the entire framework library. `bin/forge` is the CLI. No separate install step is needed to work on them — edits take effect immediately.

### Running the blog example

The `examples/blog/` app is the main integration test bed. It exercises every framework feature.

```bash
cd examples/blog

# Set up your environment
cp .env.example .env.development
# Edit .env.development: set DATABASE_URL and APP_SECRET

# Point the Makefile at your local forge.jda instead of a released version
echo 'FORGE = ../../forge.jda' > .env.make   # overridden in Makefile via ?=

# Run
../../bin/forge server
```

Visit `http://localhost:8080`.

### Running the test suite

```bash
cd examples/blog
../../bin/forge test
```

Tests live in `examples/blog/test/`. They run in-process against a real database — no mocks.

---

## Project structure

```
jda-forge/
  forge.jda           # The entire framework — one file, ~9 000 lines
  bin/forge           # CLI: new, server, build, test, generate, release, …
  install.sh          # Installer (also driven by jda install)
  Jdapkg              # Package manifest read by jda install
  registry/
    packages.json     # Short-name registry (forge → github.com/jdalang/jda-forge)
  examples/
    blog/             # Full blog app — the canonical reference
  docs/               # One markdown file per topic
  scaffold/           # Templates used by forge generate
  CHANGELOG.md
```

### forge.jda sections

`forge.jda` is divided into clearly labelled sections. Use your editor's search to jump between them:

| Section header | What lives there |
|---|---|
| `// HTTP core` | `ForgeApp`, routing, middleware, `app_new_config` |
| `// Context` | `ctx_*` functions — params, headers, response |
| `// Sessions / Flash / CSRF` | Session store, flash, CSRF token |
| `// Database` | Connection pool, query builder, `ForgeQuery` |
| `// Models` | CRUD helpers, validations, callbacks, associations |
| `// Mailer` | SMTP, `forge_mail_*` |
| `// Background Jobs` | Job queue, workers, `forge_job_*` |
| `// Views / Templates` | `ForgeBuf`, template helpers |
| `// Assets` | Fingerprinting, `forge_stylesheet_tag` |
| `// WebSocket / Channels` | WS upgrade, pub/sub channels |
| `// Instrumentation` | `forge_instrument`, `forge_subscribe` |
| `// Welcome page` | `forge_welcome_handler`, `forge_welcome_mount` |

---

## Making changes

### forge.jda

All framework code lives in one file. When adding a function:

- Place it in the correct section (see table above)
- Follow the existing naming convention: `forge_<noun>_<verb>` for library functions
- Add a one-line comment only if the *why* is non-obvious — skip the what
- Test your change by running the blog example end-to-end

### bin/forge

The CLI is a Bash script. Functions are named `cmd_<name>` and registered at the bottom of the file in the `case` statement. Keep new commands consistent with the existing structure.

### Documentation

Docs live in `docs/`. One file per topic. When you add a new function to `forge.jda`, update the relevant doc page with:

- A short description
- A working code example
- Any edge cases worth noting

---

## Submitting a pull request

1. **Fork** the repository and create a branch from `main`.
2. **Make your change** with a focused commit. One logical change per PR.
3. **Test** — run `../../bin/forge test` from `examples/blog/` and confirm it passes.
4. **Open the PR** against `main`. Describe *what* changed and *why*. Link to the issue if one exists.
5. A maintainer will review and may request changes. Small, focused PRs merge fastest.

### Commit style

```
type: short description in present tense

Longer explanation if needed — the why, not the what.
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`.

---

## Reporting bugs

Open a GitHub issue and include:

- **JDA version** — `jda --version`
- **Forge version** — `forge version`
- **OS / platform**
- **Minimal reproduction** — the smallest `.jda` snippet or set of steps that triggers the bug
- **Expected vs actual behaviour**

The more specific, the faster it gets fixed.

---

## Suggesting features

Open a GitHub issue with the `enhancement` label. Describe:

- The problem you are trying to solve
- What you'd expect the API to look like (a rough sketch is fine)
- Any alternative approaches you considered

We discuss before implementing so nobody wastes effort on something that won't land.

---

## Code style

- **JDA functions**: `lower_snake_case`, prefixed with the subsystem (`forge_`, `ctx_`, `forge_q_`, etc.)
- **Comments**: only when the *why* is non-obvious; never describe what the code does
- **Bash**: `lower_snake_case` for variables and functions; quote all variable expansions
- **Markdown**: ATX headings (`##`), fenced code blocks with language tags, one blank line between sections

---

## Community

- **Issues** — [github.com/jdalang/jda-forge/issues](https://github.com/jdalang/jda-forge/issues) — bugs, features, questions
- **Discussions** — [github.com/jdalang/jda-forge/discussions](https://github.com/jdalang/jda-forge/discussions) — open-ended conversation

We are a small, welcoming community. Be kind, be direct, and help each other ship.
