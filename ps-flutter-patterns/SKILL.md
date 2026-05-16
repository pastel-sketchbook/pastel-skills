---
name: ps-flutter-patterns
description: |
  Build Flutter apps following Pastel Sketchbook patterns — Riverpod state
  management with code generation, repository/service layering, immutable
  models with copyWith, Dio-based API clients, local persistence, responsive
  layouts, and Dart 3 idioms.
  USE FOR: scaffold Flutter app, add Riverpod provider, wire repository layer,
  set up Dio client, implement local persistence, create responsive layout,
  write widget tests, configure analysis options, add service with code gen.
  DO NOT USE FOR: Rust services (use ps-axum-patterns or ps-tonic-patterns),
  TUI applications (use ps-ratatui-patterns), general code quality audits
  (use code-quality-audit), non-Flutter Dart packages.
---

# Flutter App Patterns

**UTILITY SKILL** — proven patterns for Pastel Sketchbook Flutter apps.

## Workflow

1. Identify the task area from [references/patterns.md](references/patterns.md)
2. Read the matching section for full code examples
3. Copy and adapt — do not reinvent

## Key Principles

- Separate concerns: models, services, repositories, state, UI
- Riverpod annotation codegen (`@Riverpod`) for all providers; `keepAlive: true` for singletons
- Repository pattern: UI reads state providers; providers delegate to repositories; repositories coordinate services
- Immutable models with hand-written `copyWith`; use `freezed` only when it pays for itself
- `Dio` for HTTP; one shared instance via provider with `ErrorHandlingInterceptor` before logging
- `final` by default; avoid `dynamic`; isolate platform casts narrowly
- Async work off the UI thread: `Isolate.run` / `compute` for heavy PDF, image, audio ops
- Responsive layouts: `LayoutBuilder` or `MediaQuery.sizeOf` with width breakpoints (800px)
- `dart format` (two-space indent, trailing commas); `flutter analyze` with `very_good_analysis`
- Dart 3 features (records, patterns, sealed classes) where they improve clarity
- Never commit API keys; supply via `--dart-define` or env loader at runtime
- Dispose controllers, players, and streams; use `ref.onDispose` in providers
