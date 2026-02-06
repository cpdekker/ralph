# SPEC REVIEW-FIX - Address Review Findings

You are fixing issues identified during the spec quality review.

## Setup

1. Read `.ralph/specs/active.md` — the current spec
2. Read `.ralph/spec_review.md` — the review findings to address
3. Read `.ralph/spec_seed.md` — the user's original requirements (for context)
4. Read `.ralph/spec_research.md` — codebase analysis (for grounding fixes)

---

## Your Task

**Fix BLOCKING and NEEDS ATTENTION issues from `.ralph/spec_review.md`, then STOP.**

### Priority Order

| Priority | Marker | Action |
|----------|--------|--------|
| 1st | `❌ BLOCKING` | Must fix — spec can't go to implementation without these |
| 2nd | `⚠️ NEEDS ATTENTION` | Should fix — improves spec quality significantly |
| 3rd | `💡 CONSIDER` | Optional — only if time permits and improvement is clear |

---

## Execution

1. **Read all findings** from spec_review.md
2. **Fix up to 5 issues per turn**, starting with BLOCKING
3. **For each fix:**
   - Update the relevant section(s) in both `specs/active.md` and `specs/{FEATURE_NAME}.md`
   - Ensure the fix is consistent with the rest of the spec
   - Ground fixes in spec_research.md findings (use real codebase patterns)
4. **Mark findings as RESOLVED** in spec_review.md:
   ```markdown
   #### ✅ RESOLVED: [Issue Title]
   - **Original Issue**: [What was reported]
   - **Resolution**: [What was changed and why]
   ```
5. **Commit and push**

---

## Fix Guidelines

### For Missing Content
- Fill in the section with specific, concrete content
- Base on spec_research.md findings and spec_seed.md requirements
- Don't add generic filler — add real, implementable content

### For Inconsistencies
- Determine which section has the "correct" version
- Update the other section(s) to match
- Add a note about what was made consistent

### For Vague Requirements
- Make requirements specific and testable
- Quantify where possible (times, counts, sizes)
- Add examples if the requirement is complex

### For Missing Edge Cases
- Think about what could go wrong
- Document the handling for each edge case
- Update the error handling section accordingly

### For Architecture Issues
- Follow patterns from spec_research.md
- Ensure the fix doesn't create new inconsistencies
- Update the file structure if architecture changes

---

## Commit and Push

After fixing issues:

```bash
git add .ralph/specs/active.md .ralph/specs/{FEATURE_NAME}.md .ralph/spec_review.md
git commit -m "spec: fix review issues - [N] resolved"
git push
```

Then STOP. The next phase will check if the spec is ready.

---

## STOP CONDITIONS

**Your turn is DONE when:**
- You've fixed up to 5 issues and pushed, OR
- All remaining issues are `💡 CONSIDER` (low priority), OR
- No unresolved BLOCKING or NEEDS ATTENTION issues remain

---

## Critical Rules

- **NEVER modify `.ralph/spec_seed.md`** — User input is sacred
- **NEVER modify `.ralph/spec_research.md`** — Research findings are read-only
- **NEVER modify `.ralph/specs/sample.md`** — Template is read-only
- **Keep both spec files in sync** — `specs/active.md` and `specs/{FEATURE_NAME}.md` must always match
- **Don't introduce new issues** — Fixes should resolve problems, not create them
- **Stay grounded** — Use codebase patterns from spec_research.md, not generic solutions
