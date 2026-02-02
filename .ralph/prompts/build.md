# BUILD MODE - Single Item Per Turn

## Your Task This Turn

**Work on exactly ONE item from the implementation plan, then STOP.**

## Setup (do this first)

1. Read `.ralph/specs/active.md` to understand the feature requirements
2. Read `.ralph/implementation_plan.md` to see the task list
3. Read `.ralph/AGENTS.md` for build commands and project conventions

## Execution (one item only)

1. **Pick ONE unchecked item** from `.ralph/implementation_plan.md` — choose the highest priority incomplete task
2. **Search before implementing** — use subagents to verify the code doesn't already exist
3. **Implement the item completely** — no placeholders, no stubs, no "TODO" comments
4. **Run tests** for the code you changed — fix any failures before proceeding
5. **Update `.ralph/implementation_plan.md`** — mark the item complete with `[x]`
6. **Commit and push**:
   ```bash
   git add -A
   git commit -m "descriptive message about what was implemented"
   git push
   ```

## STOP CONDITION

**After completing ONE item and pushing, your turn is DONE.**

Do NOT:
- Start working on the next item
- Pick up additional tasks
- Continue implementing other features

The loop will start a fresh turn for the next item.

---

## Guidelines

- **Subagents**: Use up to 500 parallel Sonnet subagents for searching/reading. Use 1 subagent for builds/tests. Use Opus subagents for complex debugging or architectural decisions.
- **Complete implementations**: Finish the item fully. Partial work wastes future iterations.
- **Fix broken tests**: If unrelated tests fail, fix them as part of this item.
- **Update docs**: If you learn new commands or patterns, update `.ralph/AGENTS.md` briefly.
- **Log discoveries**: Add bugs or issues you notice to `.ralph/implementation_plan.md` for future turns.
- **Clean up**: If the implementation plan is getting long, remove completed items.
- **Spec inconsistencies**: If you find issues in `.ralph/specs/active.md`, use an Opus subagent to fix them.
- **Tagging**: When there are no build/test errors, create a git tag (increment patch from last tag, or start at 0.0.1).

## Remember

This is an iterative loop. You handle ONE item per turn. The loop will call you again for the next item. **Stop after your commit and push.**
