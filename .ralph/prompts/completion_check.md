# COMPLETION CHECK

You are evaluating whether a feature implementation is complete and ready for deployment.

## Setup

1. Read `.ralph/specs/active.md` to understand what was requested
2. Read `.ralph/implementation_plan.md` to see the implementation plan
3. Read `.ralph/review.md` (if present) to see review findings

---

## Your Task

**Answer ONE question: Is the implementation complete?**

Analyze whether all requirements from the spec have been implemented and the review has passed.

### Criteria for COMPLETE

The implementation is complete if ALL of the following are true:

1. **All spec requirements are implemented** - Every feature and requirement in `active.md` has corresponding working code
2. **No unchecked plan items remain** - All items in `implementation_plan.md` are marked with `[x]`
3. **No critical/blocking review issues** - If `review.md` exists, no "BLOCKING" or critical issues remain unaddressed
4. **Tests pass** - The implementation has passing tests (verify by checking review findings or plan status)

### Criteria for INCOMPLETE

The implementation is incomplete if ANY of the following are true:

1. **Missing spec requirements** - Features from `active.md` are not yet implemented
2. **Unchecked plan items** - There are remaining `[ ]` items in `implementation_plan.md`
3. **Unresolved blocking issues** - Critical bugs or issues from review need fixing
4. **Tests failing** - There are test failures that need to be addressed
5. **Plan needs refinement** - The implementation plan is missing tasks needed to complete the spec

---

## Response Format

You MUST respond with ONLY a valid JSON object. No markdown, no explanation, no other text.

If complete:
```
{"complete": true, "reason": "Brief explanation of why implementation is complete"}
```

If incomplete:
```
{"complete": false, "reason": "Brief explanation of what remains", "remaining": ["item 1", "item 2"]}
```

---

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — The spec is the source of truth and must remain unchanged
- **NEVER modify `.ralph/specs/*.md`** — All spec files are read-only
- **NEVER modify any files** — This is a read-only check, do not write to any files

## Important

- Be thorough but decisive
- When in doubt, err on the side of "incomplete" - it's better to do one more cycle than ship broken code
- Focus on the spec requirements - the spec is the source of truth
- Ignore nice-to-haves that weren't in the original spec

**Respond with JSON only. No other output.**
