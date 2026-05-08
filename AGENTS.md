# Pastel Skills

## Purpose

This repository exists to **create, curate, and maintain skills for AI agents** used across **Pastel Sketchbook's projects**. A "skill" here is a reusable, self-contained guide that teaches an agent a proven technique, workflow, or tool — loaded on demand to inject task-specific instructions and resources into the agent's context.

## Scope

- **In scope**: Authoring skills (SKILL.md files), bundled scripts, templates, and references that agents can load to perform specialized tasks within Pastel Sketchbook projects.
- **Out of scope**: Application code, runtime services, end-user tooling. This repo produces *agent capabilities*, not products.

## What Belongs Here

- `SKILL.md` files following the agent skill format (frontmatter + instructions).
- Supporting assets bundled with a skill (scripts, templates, reference data, fixtures).
- Documentation about skill conventions, naming, and lifecycle within Pastel Sketchbook.

## Authoring Skills

When creating a new skill, **always load the `building-skills` skill first** — before researching prior art or writing any `SKILL.md`. It defines the required structure, naming conventions, and frontmatter format.

## Quality Validation with Waza

Use [waza](https://github.com/microsoft/waza) to validate skills before submission:

- `waza check <skill-name>` — compliance score, token budget, spec validation, link checks, schema validation.
- `waza suggest <skill-name>` — generate eval.yaml and task suggestions.
- `waza run eval.yaml` — run the evaluation suite.
- `waza tokens suggest` — get token reduction tips when over budget.
- `waza dev` — interactive compliance improvement.

Always run `waza check` before committing skill changes. Target: **ready for submission** status.

## Conventions

- One skill per directory; the directory name is the skill name.
- Skill names use `kebab-case`.
- Each skill has a clear, narrow trigger described in its frontmatter `description`.
- Prefer editing existing skills over creating duplicates.
- Keep skills focused: if a skill grows multi-purpose, split it.

## Commit Conventions

Use conventional commit prefixes:
- `feat`: New skill or capability
- `fix`: Correction to an existing skill
- `refactor`: Restructure a skill without changing behavior
- `docs`: Documentation changes
- `chore`: Tooling, configuration, dependencies

## Summary Mantra

Teach agents once. Reuse everywhere. Keep skills sharp and small.
