---
name: ps-topcoat-patterns
description: |
  Build full-stack Rust web apps with Topcoat (tokio-rs/topcoat 0.9) using
  Pastel Sketchbook patterns: module router, views, Cx helpers, streaming,
  signals, shards, server push, and tests.
  USE FOR: scaffold Topcoat app, add Topcoat page or component, signals or
  shard, live region, server push, upgrade Topcoat 0.5-0.9.
  DO NOT USE FOR: Axum-only (use ps-axum-patterns), gRPC (use
  ps-tonic-patterns), Adobe Topcoat CSS, audits.
---

# Topcoat Full-Stack Patterns

**UTILITY SKILL** — Topcoat 0.9, Rust 1.98+.

## Workflow

1. Match versions: `cargo tree -i topcoat` vs `cargo install --list | grep topcoat-cli`. Below 0.9, apply [references/releases.md](references/releases.md) first.
2. Copy the matching section of [references/patterns.md](references/patterns.md).
3. Verify: `topcoat fmt`, `cargo clippy`, `topcoat asset bundle`, `cargo test`.

## Key Principles

- Handlers return `Result<impl View>`; views are lazy, move-capture
- `cx: &Cx` helper functions plus `#[memoize]`, not middleware
- `.runtime()` goes last on the router
- Authorize and validate inside shards, procedures, signal reads
- `#[key(id)]` on component loops
- Cookies before streaming; waits behind `connected(cx)`
- `tracing` with UUID v7 request IDs

## Error Handling

- Runtime/asset panic: add `.runtime()` and `.assets(..)`
- Route conflict: root `/{id}` vs `not_found!()`
- "unit struct" error: local named like a handler

## Examples

- "Live search": tracked `signal` read, then `#[shard]`
- "Chat": `live!` + `connected(cx)` + broadcast
