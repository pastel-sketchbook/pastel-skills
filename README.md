# Pastel Skills

Reusable AI agent skills for Pastel Sketchbook projects. Each skill teaches an agent a proven pattern, workflow, or tool — loaded on demand to inject task-specific instructions into context.

## Skills

| Skill | Description |
|---|---|
| **ps-axum-patterns** | Axum web service patterns — routing, shared state, error handling, health checks, OpenAPI, testing |
| **ps-flutter-patterns** | Flutter app patterns — Riverpod state, repository/service layering, Dio, local persistence, responsive layouts |
| **ps-ratatui-patterns** | Ratatui TUI patterns — terminal lifecycle, themes, popups, mouse-driven splits, CJK text |
| **ps-tonic-patterns** | Tonic gRPC patterns — server setup, interceptors, health service, streaming, error mapping |

## Structure

```
<skill-name>/
  SKILL.md              # Frontmatter + concise instructions (< 500 tokens)
  references/           # Full code examples and data (loaded on demand)
  eval.yaml             # Evaluation suite
  tasks/                # Test tasks for eval
```

## Usage

Skills are loaded by AI agents via the skill tool when a task matches the skill's trigger description. Each `SKILL.md` contains `USE FOR` and `DO NOT USE FOR` sections to guide routing.

## Quality

Skills are validated with [waza](https://github.com/microsoft/waza):

```sh
waza check <skill-name>    # Compliance, token budget, spec validation
waza run eval.yaml         # Run evaluation suite
```

## License

[MIT](LICENSE)
