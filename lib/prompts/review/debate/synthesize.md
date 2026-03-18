# REVIEW DEBATE SYNTHESIS - Merge Debate Findings into Review

You are the **debate moderator** synthesizing cross-examination results back into the review document.

## Setup

1. Read `.ralph/review.md` — the current review findings
2. Read `.ralph/review_debate/debate_plan.md` — the debate plan
3. Read ALL `round*_*.md` files in `.ralph/review_debate/` — cross-examination results
4. Read `.ralph/specs/active.md` — the feature spec
5. Read `.ralph/AGENTS.md` — project conventions

---

## Your Task

**Update `.ralph/review.md` to incorporate cross-examination findings: add new issues, escalate/downgrade severities, and add a debate summary section.**

The updated review.md must preserve the existing format that downstream phases (REVIEW-FIX) expect.

---

## Synthesis Process

### 1. Catalog All Debate Findings

From each cross-examination round, extract:
- **Severity escalations** — findings that should be upgraded (e.g., CONSIDER → NEEDS ATTENTION)
- **Severity downgrades** — findings that cross-examination showed were less severe
- **New findings** — issues identified in "What X Missed" or "Cross-Cutting Concerns"
- **Agreed findings** — where cross-examination confirmed the original severity

### 2. Apply Changes to review.md

For **severity escalations**:
- Update the marker (e.g., change `💡 CONSIDER` to `⚠️ NEEDS ATTENTION`)
- Add a note: `*Escalated via debate: [reason]*`

For **severity downgrades**:
- Update the marker
- Add a note: `*Downgraded via debate: [reason]*`

For **new findings**:
- Add them under the most relevant specialist section
- Mark with: `*Surfaced via cross-examination: [Round N, Specialist A × Specialist B]*`

### 3. Add Debate Summary Section

Append a new section to review.md:

```markdown
---

## Debate Summary

**Method**: Socratic Cross-Examination ({N} rounds, {M} specialist pairings)

### Pairings Conducted
1. [Specialist A] × [Specialist B] — [1-line outcome]
2. [Specialist C] × [Specialist D] — [1-line outcome]
...

### Impact
- **Findings escalated**: N
- **Findings downgraded**: N
- **New findings surfaced**: N
- **Findings confirmed**: N

### Key Debate Insights
1. [Most important insight from cross-examination]
2. [Second insight]
3. [Third insight]
```

---

## Severity Calibration Rules

| Signal | Action |
|--------|--------|
| Both specialists agree finding is critical | Escalate to `❌ BLOCKING` if not already |
| One specialist challenges, other concedes | Keep original or downgrade |
| Cross-cutting concern identified | Add as `⚠️ NEEDS ATTENTION` (novel finding deserves attention) |
| New gap found by cross-examination | Add as `⚠️ NEEDS ATTENTION` |
| Finding shown to be non-issue | Downgrade to `💡 CONSIDER` or remove |
| Severity disagreement with no resolution | Keep higher severity (err on caution) |

---

## Commit and Push

```bash
git add .ralph/review.md
git commit -m "review: debate synthesis complete - N escalations, M new findings"
git push
```

Then STOP. The review-fix phase will address any blocking/attention issues.

---

## Critical Rules

- **Preserve existing review.md format** — REVIEW-FIX depends on `❌ BLOCKING` and `⚠️ NEEDS ATTENTION` markers
- **Preserve all existing findings** — Even if not discussed in debate, keep them
- **NEVER modify source code** — Only update the review document
- **NEVER modify `.ralph/review_checklist.md`** — Checklist is already complete
- **Be conservative with escalations** — Only escalate when cross-examination provides clear evidence
- **Be honest about downgrades** — If debate showed a concern was overblown, downgrade it
- **Credit sources** — Every new or changed finding should note which debate round surfaced it
