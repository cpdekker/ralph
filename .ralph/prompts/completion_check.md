# COMPLETION CHECK

You are evaluating whether a feature implementation is complete and ready for deployment.

## Setup

1. Read `.ralph/specs/active.md` to understand what was requested
2. Read `.ralph/implementation_plan.md` to see the implementation plan
3. Read `.ralph/review.md` (if present) to see review findings
4. Read `.ralph/review_checklist.md` (if present) to see review coverage
5. Read `.ralph/progress.txt` (if present) — check for unresolved blockers
6. Read `.ralph/guardrails.md` (if present) — check for unresolved known issues

---

## Your Task

**Assess the implementation completeness with confidence scoring and metrics.**

Analyze whether all requirements from the spec have been implemented and the review has passed.

---

## Evaluation Criteria

### For BLOCKED ON USER status (check this FIRST)

Before evaluating completeness, check whether all remaining work requires user intervention. This is true when:

1. **All actionable items are done** — Every item the agent CAN perform is marked `[x]`
2. **Remaining items need the user** — Unchecked items are blocked on user input, external access, manual steps, or decisions only the user can make (e.g., database credentials, environment access, design decisions, answering questions)
3. **No code changes can unblock progress** — The agent has exhausted all work it can do independently

If this is the case, set `"blocked_on_user": true` and populate the `"user_intervention"` field (see Response Format below). The `"complete"` field should reflect whether the spec is fully implemented (likely `false` if work remains blocked). This tells the loop to stop iterating and request user help instead of wasting cycles.

### For COMPLETE status (confidence ≥ 0.80)

ALL of the following must be true:

1. **All spec requirements are implemented** - Every feature and requirement in `active.md` has corresponding working code
2. **No actionable unchecked plan items remain** - All items in `implementation_plan.md` that the agent can perform are marked with `[x]`. Items tagged `[DEPLOYMENT]`, `[MANUAL]`, or that explicitly require human intervention (e.g., running SQL migrations in production, manual QA in external systems, deploying to environments) should be **excluded** from the completeness count — these are post-merge steps the agent cannot perform.
3. **No critical/blocking review issues** - If `review.md` exists, no "❌ BLOCKING" issues remain unaddressed
4. **Tests pass** - The implementation has passing tests
5. **No [BLOCKED] items** - No items are marked as blocked in the implementation plan
6. **No unresolved guardrail issues** - If `guardrails.md` has "Known Issues" entries, verify they've been addressed or are out of scope

### For HIGH CONFIDENCE (0.90 - 0.94)

All requirements implemented, minor review items remain:

- Core functionality is complete
- Only `[QA-MINOR]` or `💡 CONSIDER` issues remain
- All critical paths are tested

### For MODERATE CONFIDENCE (0.80 - 0.89)

All requirements implemented, some attention items remain:

- Core functionality is complete
- Some `⚠️ NEEDS ATTENTION` issues remain but no `❌ BLOCKING`
- These are listed as caveats, not blockers

### For MEDIUM CONFIDENCE (0.60 - 0.79)

Significant progress but gaps remain:

- Some requirements not yet implemented
- `❌ BLOCKING` issues may be present
- Test coverage could be improved

### For LOW CONFIDENCE (< 0.60)

Major work remaining:

- Core requirements not yet implemented
- `❌ BLOCKING` issues present
- Significant unchecked items in plan

---

## Metrics to Evaluate

Count and report:

1. **Spec Requirements**
   - Total requirements in `active.md`
   - Requirements with corresponding implementation

2. **Plan Items**
   - Total items in `implementation_plan.md`
   - Completed items (`[x]`)
   - Remaining items (`[ ]`)
   - Blocked items (`[BLOCKED]`)
   - Manual/deployment items (`[ ]` items tagged `[DEPLOYMENT]`, `[MANUAL]`, or requiring human intervention) — these do NOT count as incomplete

3. **Review Status** (if review.md exists)
   - Total issues found
   - Blocking issues (`❌`)
   - Attention issues (`⚠️`)
   - Minor issues (`💡`)
   - Resolved issues (`✅`)

4. **Risk Assessment**
   - High-risk items completed
   - Known issues or caveats

---

## Response Format

You MUST respond with ONLY a valid JSON object. No markdown, no explanation, no other text.

### Complete with high confidence:
```json
{
  "complete": true,
  "confidence": 0.95,
  "reason": "All 12 spec requirements implemented, all 23 actionable plan items complete (2 manual/deployment items excluded), 0 blocking issues",
  "metrics": {
    "spec_requirements_met": 12,
    "spec_requirements_total": 12,
    "plan_items_complete": 23,
    "plan_items_total": 25,
    "plan_items_manual": 2,
    "plan_items_blocked": 0,
    "blocking_issues": 0,
    "attention_issues": 2,
    "minor_issues": 3
  },
  "caveats": [
    "2 manual/deployment items remain (SQL migration, manual QA) — require human intervention",
    "2 minor code quality suggestions remain"
  ]
}
```

### Incomplete:
```json
{
  "complete": false,
  "confidence": 0.65,
  "reason": "3 spec requirements not yet implemented, 2 blocking issues from review",
  "metrics": {
    "spec_requirements_met": 9,
    "spec_requirements_total": 12,
    "plan_items_complete": 18,
    "plan_items_total": 23,
    "plan_items_manual": 0,
    "plan_items_blocked": 1,
    "blocking_issues": 2,
    "attention_issues": 4,
    "minor_issues": 1
  },
  "remaining": [
    "Phase 2.3: User notifications not implemented",
    "Phase 3.1: Caching layer incomplete",
    "Blocking: SQL injection vulnerability in search handler",
    "Blocked: Email service integration awaiting API key"
  ],
  "recommendation": "Address blocking security issue first, then complete Phase 2.3"
}
```

### Blocked on user (all agent work done, needs human input):
```json
{
  "complete": false,
  "confidence": 0.72,
  "blocked_on_user": true,
  "reason": "All agent-actionable work complete. 2 phases blocked on database access that only the user can provide.",
  "metrics": {
    "spec_requirements_met": 8,
    "spec_requirements_total": 10,
    "plan_items_complete": 45,
    "plan_items_total": 52,
    "plan_items_manual": 0,
    "plan_items_blocked": 7,
    "blocking_issues": 0,
    "attention_issues": 0,
    "minor_issues": 0
  },
  "user_intervention": {
    "summary": "Cannot proceed without Snowflake database access",
    "items": [
      {
        "id": "db-access",
        "type": "access",
        "question": "Please provide Snowflake database credentials or run the extraction endpoint and save the output to .ralph/references/metric-mappings.json",
        "context": "Phase 2A.2 requires querying METRICS table to populate metricId fields in 1,368 columns across 53 dataset files",
        "blocks": ["Phase 2A.2", "Phase 3"]
      },
      {
        "id": "design-decision",
        "type": "decision",
        "question": "Should source table names use the VIEW_ prefix or raw table names in the SourceTable enum?",
        "context": "Phase 3A needs to create SourceTable enum values",
        "blocks": ["Phase 3A"]
      }
    ]
  },
  "recommendation": "User intervention required. Provide answers in .ralph/references/ to unblock remaining phases."
}
```

---

## Decision Thresholds

| Confidence | Complete? | Action |
|------------|-----------|--------|
| ≥ 0.95 | true | Ready for production |
| 0.90 - 0.94 | true | Ready with minor caveats |
| 0.80 - 0.89 | true | Complete — remaining items are minor |
| 0.60 - 0.79 | false | Continue build phase |
| < 0.60 | false | May need plan refinement |

**Key rule**: If all plan items are `[x]` and no `❌ BLOCKING` issues exist, confidence MUST be ≥ 0.80 and `complete` MUST be `true`. Minor `⚠️ NEEDS ATTENTION` or `💡 CONSIDER` items do not block completion — list them as caveats instead.

---

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — The spec is the source of truth and must remain unchanged
- **NEVER modify `.ralph/specs/*.md`** — All spec files are read-only
- **NEVER modify any files** — This is a read-only check, do not write to any files

## Sub-Spec Evaluation

**If `active.md` is a sub-spec** (contains "Master Spec:" and "Sub-Spec ID:" headers):

- Evaluate ONLY against **this sub-spec's requirements and acceptance criteria**
- Do NOT evaluate against the full master spec — that is handled by the master completion check
- Items listed in the "Out of Scope" section should be IGNORED for this evaluation
- Assume dependencies from previous sub-specs are complete and working

---

## Important

- Be thorough but decisive
- When in doubt about **code completeness**, err on the side of "complete" - the user can review and determine whether or not more cycles are needed.
- Do NOT hold completion hostage to items the agent cannot perform (deployment, manual testing in external systems, infrastructure provisioning) — list these as caveats instead
- Focus on the spec requirements - the spec is the source of truth
- Ignore nice-to-haves that weren't in the original spec
- Factor in blocked items - they may indicate dependency issues

**Respond with JSON only. No other output.**
