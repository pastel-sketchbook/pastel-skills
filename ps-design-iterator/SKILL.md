---
name: ps-design-iterator
description: |
  Iteratively refine UI components through screenshot-driven design passes.
  USE FOR: iterative UI refinement, design iterations, polish landing pages,
  hero sections, feature sections, competitor-inspired redesign.
  DO NOT USE FOR: new components from scratch, backend logic, code review.
---

# Design Iterator

**WORKFLOW SKILL** — progressive refinement of web UI components.

## Iteration Cycle

For each of N iterations (default 10):

1. **Screenshot** current state via `puppeteer_screenshot`
2. **Analyze** — identify 3–5 improvements
3. **Implement** targeted code changes
4. **Document** what changed and why

Output per iteration: `## Iteration N/Total` with analysis, changes list, and new screenshot.

## What to Improve

- **Hierarchy**: headline sizing, contrast, whitespace, section separation
- **Patterns**: gradients, hover states, badges, icon treatments, border radius
- **Typography**: font pairing, line height, letter spacing, color variations
- **Layout**: hero cards, asymmetric grids, alternating rhythm, responsive breakpoints
- **Polish**: shadow depth, animations, trust indicators

## Competitor Research

When requested, visit 2–3 competitor sites (Stripe, Linear, Vercel, Notion), screenshot relevant sections, extract techniques, apply in subsequent iterations.

## Rules

- 3–5 changes per iteration; don't undo prior improvements
- Early iterations: structure. Later: polish
- Preserve functionality; maintain accessibility
- Read files before editing; avoid generic "AI slop" aesthetics
- Use distinctive fonts (not Inter/Arial/Roboto), cohesive color with sharp accents, CSS-only motion, layered backgrounds
- Vary themes and fonts across iterations
