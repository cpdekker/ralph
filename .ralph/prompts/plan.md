# 🔄 ITERATIVE PLAN MODE

You are operating in an iterative loop. Analyze the codebase, update the implementation plan, then STOP.
Another turn will be started automatically to continue refining the plan.

---

## Setup

1. Read `.ralph/specs/active.md` to understand what we're building
2. Read `.ralph/user-review.md` (if present) — **HIGHEST PRIORITY** — user's manual review notes
3. Read `.ralph/implementation_plan.md` (if present) to see current plan state
4. Read `.ralph/review.md` (if present) to see findings from code review
5. Read `.ralph/AGENTS.md` for project conventions
6. Read `.ralph/progress.txt` (if present) — cross-iteration memory with prior decisions, blockers, and learnings
7. Read `.ralph/guardrails.md` (if present) — accumulated anti-patterns and constraints. **Respect these before making decisions.**
8. **Sub-Spec Context**: If `active.md` references a master spec (look for "Master Spec:" header), also read the master spec file for broader context. This helps you understand how this sub-spec fits into the larger feature.

---

## Your Task

Use subagents to analyze the codebase and create/update `.ralph/implementation_plan.md`.

### ⚠️ User Review Notes (HIGHEST PRIORITY)

**If `.ralph/user-review.md` exists and has content:**
- Read it FIRST and treat it as the PRIMARY source of guidance
- The user has manually tested the code and provided specific feedback
- User-identified bugs, issues, and focus areas MUST be addressed before anything else
- Research each user note with subagents to understand the context and formalize it into the plan
- Add user notes to "Phase 0: User Review Fixes" in the implementation plan

### Research Phase
- Use up to 500 parallel Sonnet subagents to search existing source code
- Compare current implementation against `.ralph/specs/active.md`
- Look for: TODOs, placeholders, minimal implementations, skipped tests, missing features
- **Do NOT assume functionality is missing** - confirm with code search first
- **If `.ralph/review.md` exists**: Incorporate all critical and important issues into the plan
- **If `.ralph/user-review.md` exists**: Research and formalize ALL user notes into actionable plan items

### Planning Phase
- **Check guardrails**: Before finalizing the plan, verify no items conflict with known anti-patterns in `.ralph/guardrails.md`
- Use an Opus subagent to analyze findings and prioritize tasks
- Create/update `.ralph/implementation_plan.md` with actionable items
- **Prioritize user notes first**: If user-review.md has content, address those items FIRST
- **Then prioritize review findings**: Bugs and critical issues from automated review
- **Reference sources**: Link plan items back to user-review.md or review.md when applicable

---

## Implementation Plan Format

The plan must use this structure:

```markdown
# [Feature Name] - Implementation Plan

## Overview
Brief description of what we're building and current status.

## Pre-flight Validation
- [ ] All dependencies are available (libraries, APIs, etc.)
- [ ] No breaking changes to existing interfaces
- [ ] Test infrastructure can validate the changes
- [ ] Estimated total iterations: X-Y

---

## Phase 0: User Review Fixes (only if user-review.md has content)
Priority items from the user's manual review. Address these FIRST.

### 0.1 Bugs (from user testing)
- [ ] [Simple] [Bug found by user] - `path/to/file.ts:123`
- [ ] [Medium] [Another bug]

### 0.2 Implementation Issues (user feedback)
- [ ] [Complex] [Thing that wasn't implemented correctly]
- [ ] [Simple] [Another issue]

### 0.3 User Focus Areas
- [ ] [Medium] [What user wants prioritized]
- [ ] [Simple] [Another focus area]

---

## Phase 0.5: Review Fixes (only if review.md exists)
Priority fixes from automated code review findings.

### 0.5.1 Critical Issues
- [ ] [Medium] [Bug/issue from review] - `path/to/file.ts:123`
- [ ] [Complex] [Another critical issue]

### 0.5.2 Important Issues  
- [ ] [Simple] [Issue from review]
- [ ] [Simple] [Another issue]

---

## Phase 0.6: High-Risk Items
Items that could affect existing functionality or require careful testing.

- [ ] [RISK] [Item that modifies shared code] - needs extra testing
- [ ] [RISK] [Item that changes database schema]
- [ ] [RISK] [Item that affects authentication/authorization]

---

## Phase 1: [Category Name]

### 1.1 [Task Group Name]
- [ ] [Simple] Specific action item (~1 iteration)
- [ ] [Medium] Another action item (~2-3 iterations)
  - [ ] Sub-item if needed
  - Dependencies: [1.0 Setup task]
  - Enables: [1.2 Next task, 2.1 Other task]

### 1.2 [Next Task Group]
- [ ] [Complex] Action item (~5+ iterations, consider decomposition)
  - Dependencies: [1.1 Previous task]
- [ ] [Simple] Action item

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

### Complexity Indicators

Use these tags to estimate iteration count:

| Tag | Estimated Iterations | When to Use |
|-----|---------------------|-------------|
| `[Simple]` | ~1 iteration | Single file, <50 lines, straightforward logic |
| `[Medium]` | ~2-3 iterations | Multiple files, moderate complexity, may need debugging |
| `[Complex]` | ~5+ iterations | Architectural changes, many files, needs decomposition |
| `[RISK]` | +1-2 extra iterations | Modifies shared code, needs extra testing |

### Dependency Tracking

For complex features, track dependencies between items:

```markdown
- [ ] [Medium] Create UserRepository
  - Dependencies: [1.1 User model must exist]
  - Enables: [2.2 UserService, 3.1 Auth controller]
```

### Requirements
- **Use `- [ ]` checkboxes** for every actionable item (Ralph tracks progress by checking these)
- **Add complexity tags** `[Simple]`, `[Medium]`, `[Complex]`, `[RISK]` to every item
- **Group into numbered sections** (1.1, 1.2, 2.1, etc.) - Ralph completes one section per turn
- **Be specific** - include file paths, function names, exact changes needed
- **Order by dependency** - items that unblock others should come first within their phase
- **Track dependencies** - for complex items, note what they depend on and what they enable
- **Mark completed items** with `- [x]` if you find code that already implements them
- **User review fixes FIRST** - if `.ralph/user-review.md` has content, include "Phase 0: User Review Fixes" as the highest priority
- **Then automated review fixes** - if `.ralph/review.md` exists, include "Phase 0.5: Review Fixes" next
- **Flag high-risk items** - include "Phase 0.6: High-Risk Items" for changes that need extra care
- **No code samples** - describe *what* to implement, not *how*. The build loop handles implementation. Code blocks bloat the plan and waste context.

---

## Sub-Spec Scope Awareness

**If `active.md` is a sub-spec** (contains "Master Spec:" and "Sub-Spec ID:" headers):

- **Plan ONLY for the active sub-spec's requirements** — do not plan work for other sub-specs
- **Respect the "Out of Scope" section** — items listed there are handled by other sub-specs
- **Assume previous sub-spec work is complete** — if dependencies are listed, treat that code as existing and working
- **Reference the master spec for context only** — understand the bigger picture, but scope your plan to THIS sub-spec
- **Do not duplicate work** — if a dependency sub-spec already built something, use it, don't rebuild it

---

## Scope Boundaries

- **Plan only** - Do NOT implement anything
- **Update plan only** - Commit and push changes to the plan, then stop
- **One iteration** - Refine the plan, don't try to make it perfect in one pass

---

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — The spec is the source of truth and must remain unchanged across all iterations
- **NEVER modify `.ralph/specs/*.md`** — All spec files are read-only during planning

## Update Cross-Iteration Memory

Before committing:
1. **Append to `.ralph/progress.txt`** — Log what you analyzed, key decisions made, and any blockers found. Keep entries concise (1-3 lines).
2. **Update `.ralph/guardrails.md`** — If you discovered anti-patterns or architectural constraints during analysis, add them to the appropriate section.

## Commit and Push

After updating the plan:
```bash
git add .ralph/implementation_plan.md .ralph/progress.txt .ralph/guardrails.md
git commit -m "Update implementation plan"
git push
```

Then STOP. The next turn will continue refining if needed.
