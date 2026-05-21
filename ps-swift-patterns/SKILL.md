---
name: ps-swift-patterns
description: |
  Build Swift/SwiftUI apps following Pastel Sketchbook patterns — @Observable
  view models with @MainActor, protocol-based adapter layer, repository
  pattern for service coordination, immutable models with copyWith, SwiftPM
  executable targets, Environment-based DI, custom transitions, and
  structured concurrency with Task cancellation.
  USE FOR: scaffold Swift app, add @Observable view model, wire repository
  layer, set up adapter protocols, implement local persistence, create
  animated transitions, write SwiftUI views, configure SwiftPM package,
  add API service with URLSession.
  DO NOT USE FOR: Flutter/Dart apps (use ps-flutter-patterns), Rust services
  (use ps-axum-patterns or ps-tonic-patterns), TUI applications
  (use ps-ratatui-patterns), general code quality audits (use code-quality-audit).
---

# Swift/SwiftUI App Patterns

**UTILITY SKILL** — proven patterns for Pastel Sketchbook Swift apps.

## Workflow

1. Identify the task area from [references/patterns.md](references/patterns.md)
2. Read the matching section for full code examples
3. Copy and adapt — do not reinvent

## Key Principles

- Separate concerns: Models, Adapters (protocols), Services (concrete), Repositories, State (view models), UI
- `@Observable` + `@MainActor` for view models; no Combine, no ObservableObject
- Repository pattern: UI reads view model state; view models delegate to repositories; repositories coordinate services via adapter protocols
- Immutable value-type models with hand-written `copyWith` using double-optional (`T??`) for nullable fields
- Protocol-based adapters decouple repository from concrete implementations (enables mocking)
- `Codable` + `FileManager` for local JSON persistence; SwiftData only when schema complexity warrants it
- `URLSession` for HTTP; one service per external API with typed error enums
- `let` by default; value types by default; `class`/`actor` only for identity or shared mutable state
- Structured concurrency: `Task` for fire-and-forget, `async/await` for sequential, `Task.checkCancellation()` for interruptible work
- SwiftUI Environment for DI: `.environment(viewModel)` at root, `@Environment(Type.self)` in children
- `.overlay(alignment:)` for badges/indicators (not ZStack children — avoids clipping issues)
- `withAnimation` at the call site for transitions; `.transition()` + `.id()` on views for swap animations
- `swift-format` / `swiftformat`; two-space indent; trailing commas
- Never commit API keys; supply via environment, Keychain, or xcconfig at runtime
- Dispose Task handles, AVAudioPlayer, and temporary files; cancel in-flight work on user abort
