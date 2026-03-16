# FINAL SUMMARY

You are generating a completion summary for a Ralph implementation session.

## Setup

1. Read `.ralph/specs/active.md` to understand what was requested
2. Read `.ralph/implementation_plan.md` to see the plan and what was checked off vs remaining
3. Read `.ralph/review.md` (if present) to see review findings
4. Read `.ralph/progress.txt` (if present) to see the session history
5. Read `.ralph/guardrails.md` (if present) to see known issues
6. Read `.ralph/user-intervention.md` (if present) to see what's blocked on the user

---

## Your Task

**Produce a clear, actionable summary** of the implementation session. Write the summary to `.ralph/summary.md`.

The summary should help the user quickly understand what happened, what's left, and how to verify.

---

## Summary Structure

Write `.ralph/summary.md` with this structure:

```markdown
# Implementation Summary

## Session Stats
- **Iterations**: [completed count]
- **Mode**: [mode that was run]
- **Status**: [Complete | Incomplete — stopped at max iterations | Blocked on user intervention]

## What Was Implemented
[Bulleted list of features/changes that were completed. Reference specific files where helpful.]

## What Remains
[Bulleted list of unchecked plan items, unresolved review issues, or blocked items. Mark each with why it remains (e.g., "blocked on user", "ran out of iterations", "blocked by dependency").]

[If nothing remains, state: "All spec requirements have been implemented."]

## Known Issues
[Any guardrail entries, review warnings, or concerns discovered during implementation.]

[If none, state: "No known issues."]

## How to Test / Verify
[Step-by-step instructions for the user to verify the changes work. Include:]
1. How to run the test suite (specific commands)
2. Manual verification steps (what to click/check/try)
3. Edge cases to watch for
4. Any environment setup needed before testing

## Files Changed
[List the key files that were added or modified, grouped by purpose. Skip .ralph/ internal files.]
```

---

## Guidelines

- Be specific and concrete — reference actual file names, function names, and test commands
- For "What Remains", clearly distinguish between items the agent couldn't do (needs user input) vs items it didn't get to (ran out of iterations)
- For testing steps, prefer concrete commands over vague instructions (e.g., `npm test -- --grep "auth"` not "run the tests")
- Look at the actual test files to determine the correct test commands
- Keep the summary concise but complete — aim for quick scanning
- Do NOT modify any source code files — this is a read-only summary task
