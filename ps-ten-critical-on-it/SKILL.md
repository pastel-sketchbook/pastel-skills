---
name: ps-ten-critical-on-it
description: |
  Find the 10 most critical codebase handoff facts from code and git history,
  then generate a polished FFE-light 1080p 11-slide PDF deck with highlighted snippets.
  USE FOR: codebase handoff, passover deck, onboarding briefing.
  DO NOT USE FOR: general code review, vulnerability audits, long-form docs.
---

# Ten Critical On It

**WORKFLOW SKILL** — ranked codebase handoff PDF deck.

## Contract

Produce exactly 11 slides: title slide, then ranked #1-#10 critical slides.
Each critical slide includes:

- `#N Critical` badge and specific title
- Rationale
- Evidence: path, line range, git history if useful
- Syntax-highlighted code snippet
- `Passover:` preserve/change/investigate guidance

If there are more than 10 candidates, include only the top 10.

## Workflow

1. Map languages, frameworks, entry points, config, tests, CI/deploy, scripts.
2. Search: auth, data, migrations, concurrency, jobs, queues, APIs, secrets, flags, errors, retries, caching, unsafe code, TODO/FIXME/HACK.
3. Inspect `git log --stat`, `git log --oneline --decorate`, `git blame`, and path logs.
4. Check tests/CI, rank, generate the deck.

## Criticality Rubric

Rank by combined:

- Impact: security, money, data, uptime, deploys, core flows
- Fragility: weak tests, churn, incidents, ordering constraints
- Obscurity: hidden config, generated code, middleware, hooks, scripts
- Handoff value and evidence strength

Do not invent criticality.

## Deck Requirements

- 1920x1080, 16:9
- Final output is PDF; HTML/CSS/JS may be used as an intermediate
- Keyboard nav and visible slide count in HTML intermediate
- Apply FFE light theme from [references/ffe-light.md](references/ffe-light.md)
- Prism.js, Highlight.js, or equivalent
- Snippets usually 12-28 lines

## Final Response

Report PDF path, ranked titles, validation, and notable omissions.

## Verify

Check exactly 11 slides and each critical slide has rationale, evidence, highlighted code, and passover note.
