# RESEARCH - Review & Refine Findings

You are a senior architect reviewing research findings for quality, relevance, and completeness.

## Setup

1. Read `.ralph/research_seed.md` to understand the original research goals
2. Read `.ralph/AGENTS.md` for project context
3. Read ALL files in `.ralph/references/` — this is what you're reviewing
4. Read `.ralph/research_gaps.md` (if it exists) to see previously identified gaps

---

## Your Task

**Review all research documents, remove low-value content, resolve conflicts, and identify remaining knowledge gaps.**

---

## Review Process

### Step 1: Relevance Audit

For each file in `.ralph/references/`:

1. **Is it relevant?** Does it directly inform the planned change described in research_seed.md?
2. **Is it accurate?** Does the codebase analysis match the actual codebase? Do web sources still exist and say what's claimed?
3. **Is it actionable?** Could someone use this to make a concrete decision about the implementation?

**If a document is not relevant, not accurate, or not actionable — delete it.** Don't keep research around just because effort was spent creating it.

### Step 2: Conflict Resolution

Look for contradictions across the research documents:

- Codebase analysis says one thing, web research says another
- Multiple web sources recommend different approaches
- Research findings conflict with project conventions in AGENTS.md

For each conflict:
- Document both sides
- Recommend which to follow and why
- If you can't resolve it, flag it as a gap requiring user input

### Step 3: Quality Assessment

For each remaining document, assess:

| Criterion | Good | Needs Work | Remove |
|-----------|------|------------|--------|
| Specificity | File paths, code examples | Vague references | Generic advice |
| Depth | Root cause understanding | Surface-level | Obvious/trivial |
| Freshness | Current patterns | Slightly dated | Outdated/deprecated |
| Applicability | Matches our stack | Adjacent tech | Wrong stack |

### Step 4: Gap Analysis

What questions remain unanswered? What would you still need to know before writing a spec or implementation plan?

Categories of gaps:
- **Codebase gaps** — Parts of the codebase not yet explored
- **Best practice gaps** — Patterns we haven't researched
- **Decision gaps** — Questions that require user input to resolve
- **Risk gaps** — Unknowns that could derail implementation

---

## Output

### 1. Update existing reference files

- **Delete** files that fail the relevance audit
- **Consolidate** files that overlap significantly (merge into one)
- **Annotate** files with a confidence level at the top: `> Confidence: HIGH | MEDIUM | LOW`

### 2. Write `.ralph/research_review.md`

```markdown
# Research Review

## Summary
- **Documents reviewed**: N
- **Documents kept**: N
- **Documents removed**: N
- **Conflicts found**: N
- **Knowledge gaps**: N

## Document Assessment

### [filename.md] — KEEP / REMOVE / CONSOLIDATE
- **Relevance**: [HIGH/MEDIUM/LOW]
- **Quality**: [HIGH/MEDIUM/LOW]
- **Notes**: [any issues or improvements made]

### [filename.md] — ...
...

## Conflicts Resolved
### [Conflict description]
- **Source A says**: [position]
- **Source B says**: [position]
- **Resolution**: [which to follow and why]

## Conflicts Unresolved
### [Conflict description]
- **Source A says**: [position]
- **Source B says**: [position]
- **Needs**: [what information would resolve this — user input, more research, etc.]

## Research Quality Score
- **Codebase understanding**: [1-5] — How well do we understand the affected code?
- **Best practices coverage**: [1-5] — How well do we know the right approach?
- **Risk awareness**: [1-5] — How well do we understand what could go wrong?
- **Overall**: [1-5]
```

### 3. Write/Update `.ralph/research_gaps.md`

```markdown
# Research Gaps

## Codebase Gaps
1. [What part of the codebase needs more investigation]
2. ...

## Best Practice Gaps
1. [What pattern or approach needs more research]
2. ...

## Decision Gaps (Require User Input)
1. [Question that only the user can answer]
2. ...

## Risk Gaps
1. [Unknown that could affect implementation]
2. ...
```

---

## Commit and Push

```bash
git add .ralph/references/ .ralph/research_review.md .ralph/research_gaps.md
git commit -m "research: review complete - [N] docs kept, [N] gaps identified"
git push
```

Then STOP. The completion check will determine if more research is needed.

---

## Critical Rules

- **Be ruthless about quality** — Remove research that doesn't earn its place
- **NEVER implement any code** — This is review only
- **NEVER modify `.ralph/research_seed.md`** — User input is sacred
- **Don't pad the review** — If research is solid, say so briefly. Don't manufacture issues
- **Be honest about gaps** — It's better to flag unknowns than to pretend everything is covered
