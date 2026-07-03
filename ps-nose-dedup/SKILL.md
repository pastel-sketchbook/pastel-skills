---
name: ps-nose-dedup
description: |
  Scan and deduplicate code using the nose CLI across any language.
  USE FOR: detect duplicated code, dedup code, find copy-paste, nose query,
  extract helpers, duplication audit, code clone detection.
  DO NOT USE FOR: general linting (use code-quality-audit), writing new
  features, scaffolding projects, CI/CD pipeline setup.
allowed-tools:
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Bash
  - Task
  - AskUserQuestion
  - TodoWrite
---

# Nose Deduplication

**WORKFLOW SKILL** -- detect, triage, and eliminate duplicated code using `nose`.

## Workflow

1. **Prerequisite** -- Run `nose --version`. If not installed, stop and inform the user.
2. **Scan** -- `nose query .` at the project root. Record family count.
3. **Triage** -- Prioritize per [references/workflow.md](references/workflow.md): prod shared-core first, then copy-paste (removable > 4), then test helpers.
4. **Drill-down** -- `nose query . id=<id> full` for each family. Read the diff and extraction proposal.
5. **Extract** -- Apply refactoring: helper function, test helper (`t.Helper()` in Go), or shared module.
6. **Verify** -- Run tests after each extraction.
7. **Re-scan** -- `nose query .` again. Confirm family count decreased.
8. **Report** -- Output before/after summary.

## Error Handling

- `nose` not installed -- stop, tell the user to install from https://github.com/corca-ai/nose.
- Zero families found -- report clean, skip remaining steps.
- Tests fail after extraction -- revert, re-read the nose proposal, adjust the refactoring.

## Examples

- "Dedup this codebase" -- scan, triage prod shared-core families, extract helpers, verify, report.
- "Find copy-paste code" -- scan, output family list with file:line locations, prioritize by witness level.
- "Clean up test duplication" -- scan with `scope=test`, extract test helpers, verify.
