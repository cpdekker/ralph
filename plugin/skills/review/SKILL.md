---
name: review
description: Launch Ralph's specialist code review — security, database, API, performance, UX, and QA reviewers analyze your code in a background Docker container.
---

# Ralph Review

Launch Ralph in review mode for multi-specialist code review.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Pick spec**: Ask the user which spec or branch to review. Verify the spec exists.

3. **Confirm options**: Default 10 iterations. Mention that review mode uses specialist reviewers: security, database, API, performance, UX, QA.

4. **Launch**: Call `ralph_start` with:
   - `spec`: chosen spec
   - `mode`: `"review"`
   - `workdir`: current repo root
   - `options`: as confirmed

5. **Report**: Container ID, branch, how to check in.

## On Completion

1. Call `ralph_result` with `artifact: "review"` to pull `.ralph/review.md`
2. Present findings organized by severity (BLOCKING, WARNING, INFO)
3. List which specialists contributed findings
4. If BLOCKING issues found, suggest: "Run `/ralph:full` with review-fix mode to address blocking issues"
