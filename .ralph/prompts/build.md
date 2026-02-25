# BUILD MODE - Smart Batching Per Turn

## Your Task This Turn

**Work on items from the implementation plan based on complexity, then STOP.**

## Setup (do this first)

1. Read `.ralph/specs/active.md` to understand the feature requirements
2. Read `.ralph/implementation_plan.md` to see the task list
3. Read `.ralph/AGENTS.md` for build commands and project conventions
4. Read `.ralph/progress.txt` (if present) — context from prior iterations (decisions, blockers, learnings)
5. Read `.ralph/guardrails.md` (if present) — anti-patterns and constraints. **Check these before implementing.**

---

## Execution Strategy

### Assess Item Complexity

Look at the complexity tags in the implementation plan:

| Tag | Items per Turn | Guideline |
|-----|---------------|-----------|
| `[Simple]` | Up to 3 items | Single file, <50 lines, straightforward |
| `[Medium]` | 1 item | Multiple files, moderate complexity |
| `[Complex]` | 1 item | Architectural changes, many files |
| `[RISK]` | 1 item | Extra testing required |

### Dynamic Batching Rules

**You may complete MULTIPLE `[Simple]` items in a single turn if:**
- They are independent (no dependencies on each other)
- They are in the same file or closely related files
- Combined changes are < 100 lines
- All can be tested together

**For `[Medium]`, `[Complex]`, or `[RISK]` items:**
- ONE item per turn, as these require more focus and debugging

### Execution Steps

1. **Pick item(s)** from `.ralph/implementation_plan.md` — choose highest priority incomplete task(s)
2. **Check dependencies** — ensure prerequisite items are marked `[x]` complete
3. **Search before implementing** — use subagents to verify the code doesn't already exist
4. **Implement completely** — no placeholders, no stubs, no "TODO" comments
5. **Run tests** for the code you changed — fix any failures before proceeding
   - **Test optimization**: Before running tests, check what files you modified this turn (`git diff --name-only`). If ALL your changes are limited to `.md` or `.txt` files (documentation, plans, status updates), skip test execution entirely — tests validate code, not documentation. Only run tests when you've modified code files (`.ts`, `.js`, `.py`, `.go`, `.sh`, etc.).
6. **Update `.ralph/implementation_plan.md`** — mark item(s) complete with `[x]`
7. **Commit and push**:
   ```bash
   git add <specific-files-you-changed> .ralph/progress.txt .ralph/guardrails.md
   git commit -m "descriptive message about what was implemented"
   git push
   ```
   ⚠️ **Never use `git add -A` or `git add .`** — always stage specific files to avoid committing secrets, build artifacts, or unrelated changes.

---

## Rollback & Recovery

### If Tests Fail

1. **First attempt**: Analyze the failure and fix the issue within this turn
2. **Second attempt**: If the fix doesn't work, try a different approach
3. **Third attempt**: If still failing after 3 fix attempts:
   - **STOP trying** — do not continue with different approaches indefinitely
   - Revert your changes: `git checkout -- .`
   - Add a "Discovered Issue" to `.ralph/implementation_plan.md`:
     ```markdown
     ## Discovered Issues
     - [BLOCKED] Item X.Y failed due to: [brief explanation]
       - Attempted fixes: [what you tried]
       - Possible causes: [your analysis]
       - Recommendation: [suggested approach for next iteration]
     ```
   - Also add to `.ralph/guardrails.md` under "Anti-Patterns" if this is a pattern future iterations should avoid
   - Commit the note and STOP
   - The next iteration will have fresh context to approach differently

### If You Get Stuck

If you find yourself:
- Going in circles with the same error
- Making changes that keep breaking other things
- Unable to understand why something isn't working

**Do this:**
1. Stop implementing
2. Document what you've learned in "Discovered Issues"
3. Add `[BLOCKED]` tag to the item in the plan
4. Commit and push
5. The next iteration (or a human) will have the context to help

---

## STOP CONDITIONS

**Your turn is DONE when:**
- You've completed your item(s) and pushed, OR
- You've hit 3 failed fix attempts and documented the issue, OR
- You've added a `[BLOCKED]` note for an item you can't progress

Do NOT:
- Keep trying endlessly when stuck
- Start working on the next item after completing yours
- Pick up additional unrelated tasks

The loop will start a fresh turn for the next item.

---

## Guidelines

- **Subagents**: Use up to 500 parallel Sonnet subagents for searching/reading. Use 1 subagent for builds/tests. Use Opus subagents for complex debugging or architectural decisions.
- **Complete implementations**: Finish the item fully. Partial work wastes future iterations.
- **Fix broken tests**: If unrelated tests fail, fix them as part of this item.
- **Update docs**: If you learn new commands or patterns, update `.ralph/AGENTS.md` briefly.
- **Log discoveries**: Add bugs or issues you notice to `.ralph/implementation_plan.md` for future turns.
- **Clean up**: If the implementation plan is getting long, remove completed items.
- **Spec inconsistencies**: If you find issues in `.ralph/specs/active.md`, document them in "Discovered Issues" in the implementation plan. Do NOT modify the spec.
- **Tagging**: When there are no build/test errors, create a git tag (increment patch from last tag, or start at 0.0.1).
- **Respect dependencies**: Don't start an item if its dependencies aren't complete.
- **Update progress**: Before committing, append a brief entry to `.ralph/progress.txt` noting what you completed, any decisions made, and context for the next iteration.
- **Respect guardrails**: Check `.ralph/guardrails.md` before implementing. If you discover a new anti-pattern or constraint, add it.

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — The spec is the source of truth and must remain unchanged across all iterations
- **NEVER modify `.ralph/specs/*.md`** — All spec files are read-only during build
- **3 strikes rule** — After 3 failed fix attempts, revert and document

## Remember

This is an iterative loop. You handle items based on complexity per turn. The loop will call you again for the next item. **Stop after your commit and push.**
