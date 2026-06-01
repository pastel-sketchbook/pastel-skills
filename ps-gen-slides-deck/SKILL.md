---
name: ps-gen-slides-deck
description: |
  Generate polished 1600x900 educational PDF decks from topics using
  repeatable Typst components, FFE light code styling, available Blex Nerd fonts,
  strong hierarchy, and line-only geometry.
  USE FOR: create slide deck, course material, tutorial deck, training deck,
  lecture slides, PDF slides.
  DO NOT USE FOR: codebase handoff decks, iterative UI-only refinement
  (use ps-design-iterator), long-form prose docs.
---

# Gen Slides Deck

**WORKFLOW SKILL** — polished educational PDF slide decks.

## Workflow

1. Read [references/deck-pattern.md](references/deck-pattern.md) for the repeatable deck spine, Typst component set, visual recipe, and quality loop.
2. Infer audience unless essential context is missing.
3. Build a 10-16 slide outline with one main idea per slide.
4. Generate Typst source and PDF at exactly 1600x900.
5. Export PNG previews and inspect title, code-heavy, checklist/workflow, and takeaway slides.
6. Fix clipping, sparse layouts, weak hierarchy, repetition, and unreadable code.
7. Validate with `pdfinfo`, `pdftotext`, and `waza check` when editing this skill.

## Requirements

- Use FFE light colors, available Blex Nerd fonts with local fallbacks, and line-only icons or geometry.
- Prefer concrete examples, real commands, useful mistakes, and concise teaching copy.
- Return PDF path, source path, slide count, validation results, and assumptions.
