# Deck Pattern

Use this recipe to generate consistent polished educational decks for any topic.

## Slide Spine

Default to 12 slides, then merge or expand detail slides to fit 10-16.

1. Title: promise, audience, and a 3-part visual anchor.
2. Baseline: three concepts, tools, or outcomes.
3. Why it matters: four reasons, pain points, or failure modes.
4. Concept A: explanation plus concrete example.
5. Concept A detail: config, mental model, or common mistake.
6. Concept B: explanation plus concrete example.
7. Concept B detail.
8. Concept C: explanation plus concrete example.
9. Workflow: exact commands, steps, checklist, or operating rhythm.
10. Objections, tradeoffs, or common mistakes.
11. Adoption checklist, exercise, or practice checkpoint.
12. Takeaway: memorable equation and next action.

## Teaching Rules

- One main idea per slide.
- Explain why before how.
- Prefer real commands, concrete examples, and useful mistakes.
- Avoid invented APIs, toy abstractions, tiny code, or dense paragraphs.
- Code snippets should be readable at presentation distance.

## Typst Component Set

Prefer Typst for deterministic PDFs. Start with:

- `#set page(width: 1600pt, height: 900pt, margin: 0pt)`
- Use available fonts: `BlexMono Nerd Font Propo` for sans-like text, `Libertinus Serif` for display serif, `BlexMono Nerd Font` for code, then local fallbacks.
- Shared colors for navy, ink, muted, mint, peach, lavender, sky, cream, panel, accent, coral, gold, blue, rule.
- `slide(n, bg, title, body)` with 64pt left margin, 1470pt content width, top accent rule, subtle background rings, and page number.
- Components: `card`, `note`, `pill`, `idea`, `step`, `metric`, `band`, `code-width`.

Use approximate sizes: 50pt titles, 21-34pt body, 25pt mono code, 64pt margins, 1470pt content width, rounded cards around 26-36pt radius.

## Visual Recipe

Use FFE light: cream/lavender/mint/sky backgrounds, navy text, muted gray secondary text, teal accent, coral/gold/blue highlights. Use soft white cards, thin rules, terminal-style code headers, large rounded corners, line-only icons or lettermarks, and subtle geometric rings.

Vary layouts across the deck:

- Title: large serif promise plus stacked pills.
- Baseline: three cards plus synthesis band.
- Why/objections: 2x2 idea grid plus bottom band.
- Code-heavy: code panel plus note or bullets.
- Workflow: code block plus metric strip.
- Checklist: numbered `step` blocks.
- Takeaway: compact metrics plus final equation.

## Quality Loop

1. Compile PDF.
2. Export PNG previews.
3. Inspect title, code-heavy, workflow/checklist, and takeaway slides.
4. Fix clipping, sparse areas, weak hierarchy, repetitive layouts, and unreadable code.
5. Validate exact dimensions and page count with `pdfinfo`.
6. Validate extractable text with `pdftotext`.
7. Run `waza check` before finishing skill changes.
