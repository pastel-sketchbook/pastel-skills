---
name: ps-topcoat-patterns
description: |
  Build full-stack Rust web apps with Topcoat (tokio-rs/topcoat 0.10) using
  Pastel Sketchbook patterns: module router, views, Cx helpers, streaming,
  signals, shards, links, server push, and tests.
  USE FOR: scaffold Topcoat app, add Topcoat page or component, signals or
  shard, live region, server push, upgrade Topcoat 0.5-0.10.
  DO NOT USE FOR: Axum-only (use ps-axum-patterns), gRPC (use
  ps-tonic-patterns), Adobe Topcoat CSS, audits.
---

# Topcoat Full-Stack Patterns

**UTILITY SKILL** — Topcoat 0.10, Rust 1.98+.

## Workflow

1. Match versions: `cargo tree -i topcoat` vs `topcoat --version`. Below 0.10, apply [references/releases.md](references/releases.md) first.
2. Copy the matching section of [references/patterns.md](references/patterns.md).
3. Verify: `topcoat fmt --check --rustfmt`, `cargo clippy`, `topcoat asset bundle`, `cargo test`.

## Key Principles

- Handlers return `Result<impl View>`; views are lazy, move-capture
- `cx: &Cx` helpers plus `#[memoize]`, not middleware
- `.runtime()` goes last on the router
- `module_param!` makes a module dynamic
- `runtime::link` for nav; pages never mutate (prefetch)
- Authorize and validate inside shards, procedures, signals, records
- `#[key(id)]` on component loops
- Cookies before streaming; waits behind `connected(cx)`
- `tracing` with UUID v7 request IDs

## Error Handling

- Runtime/asset panic: add `.runtime()` and `.assets(..)`
- Path param panic: `path_param!` → `module_param!`
- Route conflict: root `/{id}` vs `not_found!()`
- "unit struct" error: local named like a handler

## Examples

- "Live search": tracked `signal` read, then `#[shard]`
- "Chat": `live!` + `connected(cx)` + broadcast
