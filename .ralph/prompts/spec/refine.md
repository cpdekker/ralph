# SPEC REFINE - Incorporate Feedback & Self-Improve

You are refining a feature specification based on user feedback, answered questions, and self-review.

## Setup

1. Read `.ralph/specs/active.md` — the current spec draft
2. Read `.ralph/spec_seed.md` — the user's original input
3. Read `.ralph/spec_research.md` — codebase analysis and best practices
4. Read `.ralph/spec_questions.md` — questions with any user answers
5. Read `.ralph/user-review.md` (if present) — freeform user feedback on the spec

---

## Your Task

**Refine the spec by incorporating feedback and improving quality, then STOP.**

Process feedback in this priority order:

### Priority 1: Incorporate Answered Questions

Check `.ralph/spec_questions.md` for questions with filled-in `A:` lines:

- For each answered question, update the relevant section(s) of the spec
- Move answered questions to a new "## Answered" section at the bottom of spec_questions.md
- If the answer contradicts a default assumption, update the spec accordingly
- If the answer reveals new requirements, add them to the spec

### Priority 2: Incorporate User Review Feedback

If `.ralph/user-review.md` exists and has content:

- Read all feedback and incorporate it into the spec
- User feedback overrides AI assumptions
- If feedback is unclear, add a clarifying question to spec_questions.md

### Priority 3: Self-Improvement

Review the spec for quality issues:

- **Specificity** — Replace vague requirements with concrete, measurable ones
- **Edge Cases** — Add missing error scenarios and boundary conditions
- **Consistency** — Ensure data model matches API schema, file structure matches architecture
- **Completeness** — Fill in any sections that are thin or generic
- **Testability** — Ensure every requirement can be verified with a test

### Priority 4: Generate New Questions

If the refinement process reveals new ambiguities:

- Add new questions to the "## Questions" section of spec_questions.md
- Keep the same format (context, default assumption, Q:/A: pattern)
- Only ask about genuine ambiguities — don't create busywork

---

## Refinement Complete Check

After processing all feedback, evaluate whether refinement is done.

**Set `REFINEMENT_COMPLETE=true` in spec_questions.md when ALL of these are true:**

1. All questions in spec_questions.md have been answered (no blank `A:` lines in the Questions section)
2. No user-review.md feedback remains unprocessed
3. All spec sections are filled with specific, concrete content
4. No new ambiguities were discovered

Add this at the top of spec_questions.md:

```markdown
<!-- REFINEMENT_COMPLETE=true -->
```

Or if refinement is NOT complete:

```markdown
<!-- REFINEMENT_COMPLETE=false -->
```

---

## Update Rules

When modifying the spec (`specs/active.md` and the named spec file):

- **Preserve existing good content** — Don't rewrite sections that are already solid
- **Track what changed** — Add a brief changelog note at the bottom of the spec
- **Stay grounded** — New content should follow patterns from spec_research.md
- **Don't bloat** — Adding specificity doesn't mean adding length unnecessarily

---

## Commit and Push

After refining:

```bash
git add .ralph/specs/active.md .ralph/specs/{FEATURE_NAME}.md .ralph/spec_questions.md
git commit -m "spec: refine iteration - [brief description of changes]"
git push
```

Then STOP. The loop will start another refinement iteration if needed.

---

## Critical Rules

- **NEVER modify `.ralph/spec_seed.md`** — The user's original input is sacred
- **NEVER modify `.ralph/spec_research.md`** — Research findings are read-only
- **NEVER modify `.ralph/specs/sample.md`** — The template is read-only
- **Keep both spec files in sync** — `specs/active.md` and `specs/{FEATURE_NAME}.md` must match
- **Don't remove content** — Refine and improve, don't delete. Exception: replacing placeholders with real content
- **Be decisive** — Where a default assumption is reasonable and no question was asked, commit to it
