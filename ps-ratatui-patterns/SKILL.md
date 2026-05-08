---
name: ps-ratatui-patterns
description: |
  Build ratatui + crossterm TUI applications following Pastel Sketchbook
  patterns — terminal lifecycle, app layout, theme system, mouse-driven
  draggable split resizing, centered popup overlays, and UTF-8/CJK aware
  string helpers.
  USE FOR: scaffold ratatui app, add popup overlay, build multi-theme TUI,
  mouse-resizable panels, render CJK/emoji text, terminal lifecycle setup,
  help overlay, size guard, event loop, draggable split.
  DO NOT USE FOR: web services (use ps-axum-patterns), gRPC services
  (use ps-tonic-patterns), general code quality audits (use code-quality-audit).
---

# Ratatui TUI Patterns

**UTILITY SKILL** — proven patterns for Pastel Sketchbook ratatui apps.

## Workflow

1. Identify the task area from [references/patterns.md](references/patterns.md)
2. For theme palettes, see [references/themes.md](references/themes.md)
3. Copy and adapt the pattern — do not reinvent

## Key Principles

- Always enter alternate screen, enable raw mode and mouse capture
- Restore terminal unconditionally on exit, even on error
- Drain async results before drawing; 250ms tick rate default
- Vertical skeleton: header (3) / body (Min 5) / status (1) / footer (1)
- Paint theme background first so light themes don't leak defaults
- Render overlays after main layout; Clear popup area first
- Theme is a Copy struct of semantic Color slots; pass by reference
- Use unicode-width for display widths, never `.len()` or byte slicing
- Clamp all user-controlled sizes; saturating arithmetic for u16 math
- app.rs owns state; ui/ modules receive read-only references
- Filter KeyEventKind::Press only; no print!/println! in raw mode
- Unit test with TestBackend; test state transitions separately
