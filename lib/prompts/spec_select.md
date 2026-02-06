# SUB-SPEC SELECTION

You are selecting the next sub-spec to work on from a decomposed feature spec.

---

## Setup

1. Find the manifest file: Look in `.ralph/specs/` for a directory matching the current spec name, then read `manifest.json` inside it
2. Read the manifest to understand the current progress

---

## Your Task

Select the next sub-spec that should be worked on, based on the following priority rules:

### Selection Priority

1. **In-progress first**: If any sub-spec has `status: "in_progress"`, select it (resume interrupted work)
2. **Lowest-numbered eligible pending**: Select the lowest-numbered sub-spec where:
   - `status` is `"pending"`
   - All sub-specs listed in its `dependencies` array have `status: "complete"`
3. **All complete**: If all sub-specs have `status: "complete"` or `"skipped"`, signal completion
4. **Blocked**: If no sub-spec can be selected (all pending ones have incomplete dependencies), signal blocked

---

## Actions

### When selecting a sub-spec:

1. **Update manifest.json**:
   - Set the selected sub-spec's `status` to `"in_progress"`
   - Set `started_at` to current ISO timestamp (only if null — preserve existing start time for retries)
   - Increment `cycle_count` by 1
   - Update the `progress` counts
   - Update `updated_at` timestamp

2. **Copy sub-spec to active.md**:
   - Read the sub-spec file from `specs/{SPEC_NAME}/{sub_spec_file}`
   - Write it to `.ralph/specs/active.md` (overwriting previous content)

3. **Clear previous cycle artifacts**:
   - Delete `.ralph/implementation_plan.md` if it exists
   - Delete `.ralph/review.md` if it exists
   - Delete `.ralph/review_checklist.md` if it exists
   - Do NOT delete `.ralph/AGENTS.md` (project-level, not cycle-level)
   - Do NOT delete `.ralph/user-review.md` (user feedback persists)

4. **Commit changes**:
   ```bash
   git add .ralph/specs/ .ralph/implementation_plan.md .ralph/review.md .ralph/review_checklist.md
   git commit -m "Select sub-spec: {sub_spec_name}"
   git push
   ```

---

## Response Format

You MUST respond with ONLY a valid JSON object. No markdown, no explanation, no other text.

### Sub-spec selected:
```json
{
  "action": "select",
  "sub_spec_id": "02",
  "sub_spec_name": "02-api-endpoints",
  "sub_spec_title": "API Endpoints",
  "cycle_count": 1,
  "progress": {
    "total": 5,
    "pending": 3,
    "in_progress": 1,
    "complete": 1,
    "skipped": 0
  }
}
```

### All sub-specs complete:
```json
{
  "action": "all_complete",
  "progress": {
    "total": 5,
    "pending": 0,
    "in_progress": 0,
    "complete": 5,
    "skipped": 0
  }
}
```

### Blocked (no eligible sub-specs):
```json
{
  "action": "blocked",
  "reason": "Sub-spec 03 depends on 02, which is not complete. No other eligible sub-specs.",
  "blocked_specs": ["03-business-logic", "04-frontend"],
  "waiting_on": ["02-api-endpoints"]
}
```

---

## Critical Rules

- **NEVER modify sub-spec files** — They are read-only after decomposition
- **NEVER modify the master spec** — `.ralph/specs/{SPEC_NAME}.md` is read-only
- **Always update manifest.json** — It is the source of truth for progress tracking
- **Clear artifacts on sub-spec switch** — Each sub-spec starts with a fresh plan and review
- **Preserve AGENTS.md** — It contains project-level guidance that persists across sub-specs

**Respond with JSON only. No other output.**
