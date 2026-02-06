# MASTER COMPLETION CHECK

You are performing a final verification that ALL requirements from the master spec have been fully implemented across all completed sub-specs.

---

## Setup

1. Find the manifest: Look in `.ralph/specs/` for a directory matching the current spec name, then read `manifest.json`
2. Read the master spec file (path from `manifest.master_spec_file`, relative to the manifest directory)
3. Read all sub-spec files to understand what each one covered
4. Examine the actual codebase to verify implementation

---

## Your Task

**Verify holistic completion**: Ensure the master spec is fully satisfied by the combined work of all sub-specs.

### Evaluation Criteria

1. **Requirement Coverage**: Every requirement in the master spec has been implemented
2. **Integration Completeness**: Sub-specs that depend on each other work together correctly
3. **No Gaps Between Sub-Specs**: Requirements that span boundaries haven't been missed
4. **Tests Pass**: The implementation has passing tests
5. **Consistency**: Shared interfaces, naming conventions, and data models are consistent across sub-specs

### What to Check

- Read the master spec and enumerate ALL requirements
- For each requirement, verify it was assigned to a sub-spec AND implemented in code
- Check integration points between sub-specs (e.g., API endpoints match frontend calls)
- Look for orphaned code, missing error handling at boundaries, or inconsistent naming
- Verify shared types/interfaces are consistent

---

## Response Format

You MUST respond with ONLY a valid JSON object. No markdown, no explanation, no other text.

### Complete:
```json
{
  "complete": true,
  "confidence": 0.95,
  "reason": "All 15 master requirements implemented across 4 sub-specs, integration points verified, tests pass",
  "metrics": {
    "master_requirements_total": 15,
    "master_requirements_met": 15,
    "sub_specs_total": 4,
    "sub_specs_complete": 4,
    "integration_points_checked": 8,
    "integration_issues": 0
  },
  "caveats": [
    "Minor: Consider adding integration tests for the full flow"
  ]
}
```

### Incomplete (gaps found):
```json
{
  "complete": false,
  "confidence": 0.70,
  "reason": "2 master requirements not fully covered, 1 integration gap found",
  "metrics": {
    "master_requirements_total": 15,
    "master_requirements_met": 13,
    "sub_specs_total": 4,
    "sub_specs_complete": 4,
    "integration_points_checked": 8,
    "integration_issues": 1
  },
  "gaps": [
    "Requirement 'email notifications' was in sub-spec 03 but not implemented",
    "API response format in sub-spec 02 doesn't match frontend expectations in sub-spec 04",
    "Error handling for edge case X not covered by any sub-spec"
  ],
  "recommendation": "Create a follow-up sub-spec to address the gaps, or re-open sub-spec 03"
}
```

---

## Decision Thresholds

| Confidence | Complete? | Action |
|------------|-----------|--------|
| >= 0.90 | true | Master spec fully implemented |
| 0.80 - 0.89 | false | Minor gaps, one more cycle may fix |
| 0.60 - 0.79 | false | Significant gaps remain |
| < 0.60 | false | Major work remaining |

---

## Critical Rules

- **NEVER modify any files** — This is a read-only check
- **NEVER modify `.ralph/specs/`** — All spec files are read-only
- **Check the MASTER spec, not sub-specs** — Sub-specs may have missed requirements
- **Verify actual code, not just plans** — Confirm implementation exists in the codebase
- **Be thorough at integration boundaries** — This is where gaps are most likely

**Respond with JSON only. No other output.**
