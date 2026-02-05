# DECOMPOSE MODE

You are decomposing a large feature spec into ordered sub-specs that can each be completed in a single full mode cycle.

---

## Setup

1. Read `.ralph/specs/active.md` — this is the master spec to decompose
2. Read `.ralph/AGENTS.md` for project conventions

---

## Your Task

Analyze the master spec and break it into **ordered sub-specs**, each small enough to be completed in one full mode cycle (~5-15 build iterations).

### Analysis Phase

- Identify the natural boundaries in the spec (data model, API, business logic, frontend, testing, etc.)
- Map dependencies between components
- Estimate the size of each boundary area
- Ensure every requirement from the master spec appears in exactly one sub-spec

### Decomposition Rules

1. **No gaps**: Every requirement in the master spec must appear in exactly one sub-spec
2. **No overlaps**: Requirements should not be duplicated across sub-specs
3. **Dependency order**: Sub-specs are numbered in the order they should be built (dependencies first)
4. **Right-sized**: Each sub-spec should be completable in ~5-15 build iterations (1 full mode cycle)
5. **Self-contained**: Each sub-spec should produce testable, working code on its own
6. **Incremental value**: Earlier sub-specs should lay foundations that later ones build on

### Sizing Guidelines

| Size | Build Iterations | Example |
|------|-----------------|---------|
| Small | 3-5 | Data model, simple API endpoint, config setup |
| Medium | 5-10 | Service layer with business logic, complex API |
| Large | 10-15 | Full frontend component with state management |

If a single area would need >15 iterations, split it into multiple sub-specs.

---

## Output

### Directory Structure

Create the following directory and files:

```
.ralph/specs/{SPEC_NAME}/
├── manifest.json
├── 01-{first-boundary}.md
├── 02-{second-boundary}.md
├── 03-{third-boundary}.md
└── ...
```

Where `{SPEC_NAME}` is derived from the active spec filename (read from the master spec's original name or the first heading).

### manifest.json Format

```json
{
  "version": 1,
  "master_spec": "{SPEC_NAME}",
  "master_spec_file": "../{SPEC_NAME}.md",
  "created_at": "{ISO_TIMESTAMP}",
  "updated_at": "{ISO_TIMESTAMP}",
  "sub_specs": [
    {
      "id": "01",
      "name": "01-data-model",
      "file": "01-data-model.md",
      "title": "Data Model & Database Schema",
      "status": "pending",
      "dependencies": [],
      "started_at": null,
      "completed_at": null,
      "cycle_count": 0,
      "notes": ""
    },
    {
      "id": "02",
      "name": "02-api-endpoints",
      "file": "02-api-endpoints.md",
      "title": "API Endpoints",
      "status": "pending",
      "dependencies": ["01"],
      "started_at": null,
      "completed_at": null,
      "cycle_count": 0,
      "notes": ""
    }
  ],
  "progress": {
    "total": 2,
    "pending": 2,
    "in_progress": 0,
    "complete": 0,
    "skipped": 0
  }
}
```

### Sub-Spec File Format

Each sub-spec file must follow this structure:

```markdown
# Sub-Spec: {Title}

**Master Spec**: {SPEC_NAME}
**Sub-Spec ID**: {ID}
**Dependencies**: {list of dependency IDs, or "None"}

## Scope

Brief description of what this sub-spec covers.

## Requirements

List the specific requirements from the master spec that this sub-spec addresses.
Copy relevant sections verbatim from the master spec where possible.

1. **[Requirement]**: [Description]
2. **[Requirement]**: [Description]

## Acceptance Criteria

- [ ] [Specific, testable criterion]
- [ ] [Specific, testable criterion]
- [ ] [Specific, testable criterion]

## Out of Scope

Explicitly list what is NOT part of this sub-spec (handled by other sub-specs):

- [Feature/requirement handled in sub-spec XX]
- [Feature/requirement handled in sub-spec YY]

## Dependencies on Previous Sub-Specs

What this sub-spec assumes is already built and working:

- [From sub-spec 01: data model X exists]
- [From sub-spec 02: API endpoint Y is available]

## Notes

Any additional context, constraints, or guidance for implementation.
```

---

## Process

1. Read and analyze the master spec thoroughly
2. Identify natural boundaries and dependencies
3. Create the `specs/{SPEC_NAME}/` directory
4. Write each sub-spec file with full detail
5. Write `manifest.json` with correct dependencies and metadata
6. Verify: every master requirement is covered, no gaps, no overlaps

---

## Commit and Push

After creating all files:
```bash
git add .ralph/specs/{SPEC_NAME}/
git commit -m "Decompose {SPEC_NAME} into sub-specs"
git push
```

---

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — The master spec is the source of truth
- **NEVER modify `.ralph/specs/*.md`** — All existing spec files are read-only
- **Create files ONLY in `.ralph/specs/{SPEC_NAME}/`** — Sub-specs go in the new directory
- **Every master requirement must be in exactly one sub-spec** — No gaps, no overlaps
- **Dependencies must be acyclic** — No circular dependencies between sub-specs

Then STOP. The user will review the decomposition and then run full mode.
