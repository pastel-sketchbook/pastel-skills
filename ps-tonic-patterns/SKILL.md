---
name: ps-tonic-patterns
description: |
  Build tonic gRPC services following Pastel Sketchbook patterns — server
  setup, proto code generation, interceptors, context logging with UUID v7,
  gRPC health service for Kubernetes, graceful shutdown with CancellationToken,
  error mapping to tonic::Status, streaming with channels, and integration
  testing with real transport on random ports.
  USE FOR: scaffold gRPC service, add interceptors, wire health checks for k8s,
  set up error handling in tonic, server streaming, proto code generation,
  UUID v7 request tracing, graceful shutdown, integration tests.
  DO NOT USE FOR: HTTP/REST services (use ps-axum-patterns), TUI applications
  (use ps-ratatui-patterns), general code quality audits (use code-quality-audit).
---

# Tonic gRPC Service Patterns

**UTILITY SKILL** — proven patterns for Pastel Sketchbook tonic gRPC services.

## Workflow

1. Identify the task area from [references/patterns.md](references/patterns.md)
2. Read the matching section for full code examples
3. Copy and adapt — do not reinvent

## Key Principles

- Separate lib from binary; server main.rs is thin wiring
- Arc with AppState for shared state; atomics for health flags
- Always register tonic-health service for Kubernetes probes
- Use `serve_with_incoming_shutdown` for graceful shutdown
- CancellationToken coordinates server + background task shutdown
- Map domain errors to tonic::Status via From impl; never leak internals
- Compose multiple interceptors in a single function
- UUID v7 request IDs injected via interceptor for log correlation
- `#[tracing::instrument(skip(self, request), err)]` on every RPC
- Bounded mpsc channels for server-streaming; check send result
- Unit tests call trait methods directly; integration tests bind port 0
- Bind to `[::]:port` (IPv6 any) for container compatibility
