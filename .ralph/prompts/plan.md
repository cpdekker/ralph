# 🔄 ITERATIVE PLAN MODE

You are operating in an iterative loop. Analyze the codebase, update the implementation plan, then STOP.
Another turn will be started automatically to continue refining the plan.

---

## Setup

1. Read `.ralph/specs/active.md` to understand what we're building
2. Read `.ralph/implementation_plan.md` (if present) to see current plan state
3. Read `.ralph/review.md` (if present) to see findings from code review
4. Read `.ralph/AGENTS.md` for project conventions

---

## Your Task

Use subagents to analyze the codebase and create/update `.ralph/implementation_plan.md`.

### Research Phase
- Use up to 500 parallel Sonnet subagents to search existing source code
- Compare current implementation against `.ralph/specs/active.md`
- Look for: TODOs, placeholders, minimal implementations, skipped tests, missing features
- **Do NOT assume functionality is missing** - confirm with code search first
- **If `.ralph/review.md` exists**: Incorporate all critical and important issues into the plan

### Planning Phase
- Use an Opus subagent to analyze findings and prioritize tasks
- Create/update `.ralph/implementation_plan.md` with actionable items
- **Prioritize review findings**: Bugs and critical issues from review should be addressed first
- **Reference review**: Link plan items back to specific review findings when applicable

---

## Implementation Plan Format

The plan must use this structure:

```markdown
# [Feature Name] - Implementation Plan

## Overview
Brief description of what we're building and current status.

---

## Phase 0: Review Fixes (only if review.md exists)
Priority fixes from code review findings. Address these FIRST.

### 0.1 Critical Issues
- [ ] [Bug/issue from review] - `path/to/file.ts:123`
- [ ] [Another critical issue]

### 0.2 Important Issues  
- [ ] [Issue from review]
- [ ] [Another issue]

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
- **Review fixes first** - if `.ralph/review.md` exists, include "Phase 0: Review Fixes" with critical/important issues to address first
- **No code samples** - describe *what* to implement, not *how*. The build loop handles implementation. Code blocks bloat the plan and waste context.

---

## Scope Boundaries

- **Plan only** - Do NOT implement anything
- **Update plan only** - Commit and push changes to the plan, then stop
- **One iteration** - Refine the plan, don't try to make it perfect in one pass

---

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — The spec is the source of truth and must remain unchanged across all iterations
- **NEVER modify `.ralph/specs/*.md`** — All spec files are read-only during planning

## Commit and Push

After updating the plan:
```bash
git add .ralph/implementation_plan.md
git commit -m "Update implementation plan"
git push
```

Then STOP. The next turn will continue refining if needed.
