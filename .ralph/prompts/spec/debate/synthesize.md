# SPEC DEBATE SYNTHESIS - Moderator Final Report

You are the **debate moderator** synthesizing all debate material into the final spec review.

## Setup

1. Read `.ralph/specs/active.md` — the spec being reviewed
2. Read `.ralph/spec_seed.md` — the user's original requirements
3. Read `.ralph/spec_research.md` — codebase analysis
4. Read `.ralph/spec_debate/debate_plan.md` — debate setup and selected personas
5. Read ALL `*_critique.md` files in `.ralph/spec_debate/`
6. Read ALL `*_challenge.md` files in `.ralph/spec_debate/` (if they exist)
7. Read `.ralph/AGENTS.md` — project conventions
8. Read `.ralph/specs/sample.md` — the expected spec structure

---

## Your Task

**Synthesize all debate material into `.ralph/spec_review.md` using the standard review format.**

The output must be identical in structure to what the single-reviewer REVIEW phase would produce. Downstream phases (REVIEW-FIX, SIGNOFF) expect this exact format.

---

## Synthesis Process

1. **Catalog all findings** from all critiques and challenges
2. **De-duplicate**: Merge findings that describe the same underlying issue
3. **Calibrate severity**: Use debate consensus to set severity (if 2+ personas flag something as BLOCKING, it's BLOCKING)
4. **Resolve disagreements**: Where personas disagree, use your judgment — note the disagreement in the review
5. **Score each rubric category** based on aggregate findings
6. **Preserve dissent**: If a persona raised a strong concern that others dismissed, include it as a CONSIDER item

### Severity Calibration Rules

| Signal | Severity |
|--------|----------|
| 2+ personas flag as critical | `❌ BLOCKING` |
| 1 persona flags as critical, others agree in challenge | `❌ BLOCKING` |
| 1 persona flags, no challenge support | `⚠️ NEEDS ATTENTION` |
| Raised in challenge as new concern | `⚠️ NEEDS ATTENTION` |
| Single persona, low confidence | `💡 CONSIDER` |
| Dissenting opinion against consensus | `💡 CONSIDER` (preserve the dissent) |

---

## Review Rubric (same as standard review)

### 1. Completeness (Weight: 25%)
- All sections from sample.md present and filled
- All requirements from spec_seed.md addressed
- No placeholders remain
- Edge cases documented
- Error handling specified
- Testing strategy covers all requirements

### 2. Requirements Quality (Weight: 20%)
- Requirements are testable
- Requirements are specific (no vague terms)
- Requirements are quantified where applicable
- Consistent terminology
- Functional/non-functional separated

### 3. Internal Consistency (Weight: 20%)
- Data model matches API schema
- File structure matches architecture
- UI references real components
- Error handling covers all endpoints
- Testing covers all components
- Glossary terms match usage

### 4. Architecture Soundness (Weight: 15%)
- Follows project patterns
- Design pattern justified
- Clear component boundaries
- Well-defined data flow
- No circular dependencies
- Scalability considered

### 5. Implementability (Weight: 10%)
- Buildable without ambiguity
- File paths follow conventions
- Dependencies identified
- Migration path clear
- No conflicting requirements

### 6. Security (Weight: 10%)
- Auth addressed
- Input validation specified
- Injection considerations
- Sensitive data handling
- Security section thorough

---

## Output Format

Write `.ralph/spec_review.md` using this exact structure:

```markdown
# Spec Review: [Feature Name]

## Summary
- **Overall Score**: [X/100]
- **Status**: Ready / Needs Revision / Major Revision Required
- **Blocking Issues**: N
- **Attention Issues**: N
- **Consider Items**: N
- **Sections Reviewed**: N/N
- **Review Method**: Socratic Multi-Agent Debate (3 personas, [N] rounds)

---

## Debate Participants
- **Skeptic**: [1-line summary of their strongest concern]
- **[Persona 2]**: [1-line summary of their strongest concern]
- **[Persona 3]**: [1-line summary of their strongest concern]

---

## Section Reviews

### [Section Name] — [Score/Weight]

#### ❌ BLOCKING: [Issue Title]
- **Issue**: [What's wrong]
- **Impact**: [Why this matters for implementation]
- **Recommendation**: [How to fix it]
- **Raised by**: [persona(s)] | **Consensus**: [agreed/disputed]

#### ⚠️ NEEDS ATTENTION: [Issue Title]
- **Issue**: [What could be improved]
- **Impact**: [Potential problems]
- **Recommendation**: [Suggested improvement]
- **Raised by**: [persona(s)]

#### 💡 CONSIDER: [Suggestion Title]
- **Suggestion**: [What could be better]
- **Rationale**: [Why this would help]
- **Raised by**: [persona(s)]

#### ✅ APPROVED: [What's good]
- [Brief note on what's well done]

---

## Cross-Section Consistency Check
[Analysis of whether sections are internally consistent]

## Implementability Assessment
[Can a developer build from this spec?]

## Recommendations

### Must Fix (Blocking)
1. [Issue that must be fixed]

### Should Fix (Important)
1. [Issue that should be fixed]

### Nice to Have
1. [Optional improvement]

---

## Scoring Breakdown

| Category | Score | Weight | Weighted |
|----------|-------|--------|----------|
| Completeness | X/25 | 25% | X |
| Requirements Quality | X/20 | 20% | X |
| Internal Consistency | X/20 | 20% | X |
| Architecture Soundness | X/15 | 15% | X |
| Implementability | X/10 | 10% | X |
| Security | X/10 | 10% | X |
| **Total** | | | **X/100** |
```

---

## Commit and Push

```bash
git add .ralph/spec_review.md
git commit -m "spec: debate synthesis complete - [score]/100"
git push
```

Then STOP. The next phase (REVIEW-FIX or SIGNOFF) will handle the results.

---

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — Read-only
- **NEVER modify `.ralph/specs/*.md`** — All spec files are read-only
- **NEVER modify `.ralph/spec_seed.md`** — User input is sacred
- **Output format must match standard review** — Downstream phases depend on it
- **Preserve dissenting opinions** — Don't flatten everything to consensus
- **Be fair** — Weight findings by evidence quality, not persona loudness
- **Calibrate severity honestly** — BLOCKING means "cannot implement", not "could be better"
