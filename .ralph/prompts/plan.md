# 🔄 ITERATIVE PLAN MODE

You are operating in an iterative loop. Analyze the codebase, update the implementation plan, then STOP.
Another turn will be started automatically to continue refining the plan.

---

## Setup

1. Read `.ralph/specs/active.md` to understand what we're building
2. Read `.ralph/implementation_plan.md` (if present) to see current plan state
3. Read `.ralph/AGENTS.md` for project conventions

---

## Your Task

Use subagents to analyze the codebase and create/update `.ralph/implementation_plan.md`.

### Research Phase
- Use up to 500 parallel Sonnet subagents to search existing source code
- Compare current implementation against `.ralph/specs/active.md`
- Look for: TODOs, placeholders, minimal implementations, skipped tests, missing features
- **Do NOT assume functionality is missing** - confirm with code search first

### Planning Phase
- Use an Opus subagent to analyze findings and prioritize tasks
- Create/update `.ralph/implementation_plan.md` with actionable items

---

## Implementation Plan Format

The plan must use this structure:

```markdown
# [Feature Name] - Implementation Plan

## Overview
Brief description of what we're building and current status.

---

## Phase 1: [Category Name]

### 1.1 [Task Group Name]
- [ ] Specific action item
- [ ] Another action item
  - [ ] Sub-item if needed

### 1.2 [Next Task Group]
- [ ] Action item
- [ ] Action item

---

## Phase 2: [Next Category]
...

---

## Discovered Issues
- Issue found during analysis
- Another issue

## Notes
- Important context
```

### Requirements
- **Use `- [ ]` checkboxes** for every actionable item (Ralph tracks progress by checking these)
- **Group into numbered sections** (1.1, 1.2, 2.1, etc.) - Ralph completes one section per turn
- **Be specific** - include file paths, function names, exact changes needed
- **Order by dependency** - items that unblock others should come first within their phase
- **Mark completed items** with `- [x]` if you find code that already implements them

---

## Scope Boundaries

- **Plan only** - Do NOT implement anything
- **Update plan only** - Commit and push changes to the plan, then stop
- **One iteration** - Refine the plan, don't try to make it perfect in one pass

---

## Commit and Push

After updating the plan:
```bash
git add .ralph/implementation_plan.md
git commit -m "Update implementation plan"
git push
```

Then STOP. The next turn will continue refining if needed.
