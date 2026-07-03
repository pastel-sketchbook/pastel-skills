# Nose Deduplication Workflow

Complete reference for detecting and eliminating duplicated code with `nose`.

## Prerequisite

```bash
nose --version
```

If not installed, stop and report: "duplication detection requires nose (https://github.com/corca-ai/nose)".

## Step 1: Discovery

Run at the project root:

```bash
nose query .
```

This analyzes all source files and reports duplicated-code families ranked by extractability.

### Understanding the output

| Field | Meaning |
|---|---|
| `copies` | Number of duplicated instances |
| `shared` | Lines shared across copies / total lines, plus parameter count (`p`) |
| `removable` | Approximate lines removable by extraction |
| `witness` | Confidence: `exact` > `shared-core` > `copy-paste` > `similar` |
| `scope` | `prod` or `test` |
| `id` | Unique family identifier for drill-down |

### Witness levels explained

- **exact** -- proven identical behavior across all copies. Machine-verified.
- **shared-core** -- copies share a proven core computation, but may differ in surrounding context.
- **copy-paste** -- structural match. Same AST shape with parameter slots where code diverges.
- **similar** -- near-duplicate. Structurally close but differences may be intentional.

## Step 2: Triage

Prioritize families in this order:

1. **Production shared-core / exact** -- proven behavioral duplication in production code. Always fix.
2. **Production copy-paste** (removable > 4) -- high-confidence structural duplication in production code.
3. **Test copy-paste** (removable > 4) -- duplicated test scaffolding. Fix by extracting test helpers.
4. **Similar** -- near-duplicates. Review but may be intentional variation.

Skip families nose holds below the default surface (shallow-extraction, hidden) unless `nose query . all` reveals significant duplication.

### Useful filters for triage

```bash
# Only proven families
nose query . witness=shared-core
nose query . witness=exact

# Only production code
nose query . scope=prod

# Only test code
nose query . scope=test

# Sort by volume of duplicated code
nose query . sort=value

# Group totals by directory
nose query . group=dir

# Group by confidence level
nose query . group=witness

# Include everything (below default surface too)
nose query . all
```

## Step 3: Drill-down

For each family worth fixing:

```bash
nose query . id=<id> full
```

This shows:
- Every copy with `file:line` locations
- The diff showing what varies between copies (the parameters)
- The extraction proposal: shared lines with `<param N>` slots

Read the proposal carefully. The parameters tell you what arguments the extracted helper needs.

## Step 4: Deduplication Patterns

Apply the appropriate refactoring based on the nose proposal:

### Production code: extract helper function/method

When nose shows N copies of a block with M parameters varying:

```
proposal  extract a method from the repeated block . K shared lines . M parameter(s)
```

Create a helper function that takes the M varying parts as arguments and contains the K shared lines. Replace each copy with a call to the helper.

**Go example** (from a real nose finding):

Before -- two identical loops in an if/else:
```go
if cfg.IsAPIProject {
    deps := []string{"echo/v4", "otelecho", "otel", "otel/trace"}
    for _, dep := range deps {
        fmt.Fprintf(g.output, "  go get %s\n", dep)
        if err := g.runner.Run(ctx, dir, "go", "get", dep); err != nil {
            fmt.Fprintf(g.output, "Warning: 'go get %s' failed: %v\n", dep, err)
        }
    }
} else {
    deps := []string{"cobra"}
    for _, dep := range deps {
        fmt.Fprintf(g.output, "  go get %s\n", dep)
        if err := g.runner.Run(ctx, dir, "go", "get", dep); err != nil {
            fmt.Fprintf(g.output, "Warning: 'go get %s' failed: %v\n", dep, err)
        }
    }
}
```

After -- extracted helper, loop appears once:
```go
var deps []string
if cfg.IsAPIProject {
    deps = []string{"echo/v4", "otelecho", "otel", "otel/trace"}
} else {
    deps = []string{"cobra"}
}
g.getDependencies(ctx, dir, deps)

func (g *Generator) getDependencies(ctx context.Context, dir string, deps []string) {
    for _, dep := range deps {
        fmt.Fprintf(g.output, "  go get %s\n", dep)
        if err := g.runner.Run(ctx, dir, "go", "get", dep); err != nil {
            fmt.Fprintf(g.output, "Warning: 'go get %s' failed: %v\n", dep, err)
        }
    }
}
```

### Test code: extract test helper

When nose finds duplicated test setup or assertions:

```
proposal  extract a method from the repeated block . K shared lines . M parameter(s) . test
```

Extract a test helper function. In Go, mark it with `t.Helper()` so test failure messages point to the caller, not the helper.

**Go example:**

Before -- repeated assertion block in two subtests:
```go
assert.Len(t, layout.Files, len(expectedFileKeys), "File count mismatch")
for _, f := range expectedFileKeys {
    _, ok := layout.Files[f]
    assert.True(t, ok, "Missing expected file key: %s", f)
}
```

After -- extracted helper:
```go
func assertLayoutContainsFiles(t *testing.T, layout *ProjectLayout, expectedFileKeys []string) {
    t.Helper()
    assert.Len(t, layout.Files, len(expectedFileKeys), "File count mismatch")
    for _, f := range expectedFileKeys {
        _, ok := layout.Files[f]
        assert.True(t, ok, "Missing expected file key: %s", f)
    }
}
```

### Cross-file duplication

When copies span multiple files, extract into a shared internal package or utility module. Ensure the extracted code has proper visibility (exported in Go, `pub` in Rust, `export` in TypeScript).

### Template / boilerplate duplication

When the duplication is inherent to a code generation pattern, consider generics, macros, or actual code generation rather than runtime helpers.

## Step 5: Verification

After each extraction:

1. **Run tests** -- confirm no regressions.
2. **Re-run nose** -- `nose query .` and confirm the family count decreased.
3. **Acceptable remainder** -- families at or below the shallow-extraction threshold are fine.

## Nose Command Reference

| Command | Purpose |
|---|---|
| `nose query .` | Default surface scan |
| `nose query . all` | Include shallow-extraction and hidden families |
| `nose query . id=<id> full` | Drill into one family with diff and proposal |
| `nose query . sort=value` | Sort by duplicated volume |
| `nose query . sort=extractability` | Sort by ease of extraction (default) |
| `nose query . group=dir` | Totals by directory |
| `nose query . group=witness` | Totals by confidence level |
| `nose query . witness=shared-core` | Filter to proven shared computation |
| `nose query . witness=exact` | Filter to proven identical behavior |
| `nose query . scope=prod` | Filter to production code only |
| `nose query . scope=test` | Filter to test code only |
| `nose query . members>3` | Families with more than 3 copies |
| `nose query . path~internal` | Families in paths containing "internal" |
| `nose query . --format markdown` | Markdown output for PR descriptions |
| `nose query . --format sarif` | SARIF output for CI annotations |
| `nose query . --format json` | JSON output for tooling integration |
| `nose query . --fail-on any` | CI gate: exit non-zero if any families found |
| `nose query . --fail-on new --baseline nose.baseline.json` | CI gate: fail only on new duplication |
