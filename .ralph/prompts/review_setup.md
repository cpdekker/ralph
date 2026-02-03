# REVIEW SETUP - Initialize Review Checklist

This is a single-shot prompt that runs BEFORE the review loop begins.

---

## Your Task

Create a `review_checklist.md` file that transforms the implementation plan into a reviewable checklist.

## Setup

1. Read `.ralph/specs/active.md` to understand the feature requirements
2. Read `.ralph/implementation_plan.md` to see what was planned
3. Read `.ralph/AGENTS.md` for project conventions

---

## Create Review Checklist

Generate `.ralph/review_checklist.md` with this structure:

```markdown
# [Feature Name] - Review Checklist

## Overview
Brief description of the review scope and what has been implemented.

---

## Review Items

### Category 1: [From Implementation Plan Phase]
- [ ] **[Item 1.1]** - [Brief description of what to review]
  - Files: `path/to/file`
  - Spec reference: [Section in spec]
- [ ] **[Item 1.2]** - [Brief description]
  - Files: `path/to/file`, `path/to/other`
  - Spec reference: [Section in spec]

### Category 2: [Next Phase]
- [ ] **[Item 2.1]** - [Brief description]
  - Files: `path/to/file`
  - Spec reference: [Section in spec]

---

## Cross-Cutting Concerns
- [ ] **Error Handling** - Review error handling patterns across all implementations
- [ ] **Code Quality** - Check for consistent patterns, clear naming, maintainability
- [ ] **Performance** - Identify potential performance issues
- [ ] **Security** - Check for security vulnerabilities and data handling
- [ ] **Testing** - Verify test coverage and quality

---

## Review Progress
- Total items: [count]
- Reviewed: 0
- Issues found: 0

## Issues Log
_Issues will be added here during review_
```

### Guidelines for Creating the Checklist

1. **Group by implementation phase** - Mirror the structure of the implementation plan
2. **Include file paths** - List the specific files that need to be reviewed for each item
3. **Reference the spec** - Link each item back to the relevant spec section
4. **Add cross-cutting concerns** - Include general code quality checks that apply to everything
5. **Only include completed items** - Only add items from the implementation plan that are marked `[x]` (completed)
6. **Skip unimplemented items** - Don't review things that weren't built yet

---

## Commit and Push

After creating the checklist:

```bash
git add .ralph/review_checklist.md
git commit -m "Initialize review checklist for [feature]"
git push
```

Then STOP. The review loop will begin next.
