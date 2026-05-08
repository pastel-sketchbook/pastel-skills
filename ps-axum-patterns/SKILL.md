---
name: ps-axum-patterns
description: |
  Build Axum web services following Pastel Sketchbook patterns — router
  composition, shared state with Arc and AppState, tower-http tracing,
  health/ready endpoints, thiserror+anyhow error handling, env config,
  graceful shutdown, OpenAPI with utoipa, and testing via tower::oneshot.
  USE FOR: scaffold Axum service, add routes, wire shared state, implement
  health checks, set up error handling, add OpenAPI docs, write handler tests,
  configure tracing middleware, graceful shutdown with CancellationToken.
  DO NOT USE FOR: non-Axum Rust services (use ps-tonic-patterns for gRPC),
  TUI applications (use ps-ratatui-patterns), general code quality audits
  (use code-quality-audit).
---

# Axum Web Service Patterns

**UTILITY SKILL** — proven patterns for Pastel Sketchbook Axum services.

## Workflow

1. Identify the task area from [references/patterns.md](references/patterns.md)
2. Read the matching section for full code examples
3. Copy and adapt — do not reinvent

## Key Principles

- Separate lib from binary; main.rs is thin wiring
- Arc with AppState for shared state; atomics for counters/flags
- `.with_state()` last; `.layer()` applies to routes above it
- Two-level errors: thiserror for domain, anyhow for binary
- Extractor order: State, Path, Query, HeaderMap, Json (body last)
- `#[tracing::instrument(skip(state))]` on public handlers
- No unwrap in non-test code; no println — use tracing
- Health at /health, readiness at /ready, always present
- Unit tests via tower::oneshot; integration tests bind port 0
- UUID v7 request IDs for time-ordered log correlation
