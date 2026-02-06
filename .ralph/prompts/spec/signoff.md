# SPEC SIGN-OFF CHECK

You are evaluating whether a feature specification is ready for implementation.

## Setup

1. Read `.ralph/specs/active.md` — the spec being evaluated
2. Read `.ralph/spec_seed.md` — the user's original requirements
3. Read `.ralph/spec_review.md` (if present) — review findings
4. Read `.ralph/spec_questions.md` (if present) — question status
5. Read `.ralph/specs/sample.md` — the expected spec structure

---

## Your Task

**Assess the spec readiness and output a JSON result. If ready, create an approval marker file.**

---

## Evaluation Criteria

### For READY status (confidence >= 0.85)

ALL of the following must be true:

1. **All sample.md sections present and filled** — No empty sections, no placeholders
2. **All user requirements covered** — Every requirement from spec_seed.md is addressed
3. **No BLOCKING review issues** — If spec_review.md exists, no `❌ BLOCKING` issues remain
4. **All questions answered** — If spec_questions.md exists, no unanswered questions remain
5. **Internal consistency** — Data model matches API schema, file structure matches architecture
6. **Implementable** — A developer could build from this spec without asking questions

### For HIGH confidence (0.70 - 0.84)

Most requirements met with minor gaps:

- Core feature is well-specified
- Only `💡 CONSIDER` items remain
- Minor sections could be more specific but are adequate
- All critical paths are documented

### For MEDIUM confidence (0.50 - 0.69)

Significant gaps remain:

- Some sections are thin or partially filled
- `⚠️ NEEDS ATTENTION` issues remain
- Some questions are unanswered
- Architecture or data model needs work

### For LOW confidence (< 0.50)

Major work remaining:

- Multiple sections are empty or have placeholders
- `❌ BLOCKING` issues present
- Core requirements not fully addressed
- Fundamental ambiguities remain

---

## Metrics to Evaluate

Count and report:

1. **Sections** — Total sections in sample.md vs. filled sections in the spec
2. **Requirements** — Requirements from spec_seed.md vs. addressed in spec
3. **Review Issues** — Blocking / Attention / Consider / Resolved counts
4. **Questions** — Total / Answered / Unanswered
5. **Quality Indicators** — Placeholders remaining, vague requirements, missing edge cases

---

## Response Format

You MUST respond with ONLY a valid JSON object. No markdown, no explanation, no other text.

### Ready:
```json
{
  "ready": true,
  "confidence": 0.92,
  "sections_complete": 15,
  "sections_total": 15,
  "blocking_issues": 0,
  "attention_issues": 1,
  "unanswered_questions": 0,
  "requirements_covered": 8,
  "requirements_total": 8,
  "recommendation": "Spec is ready for implementation. 1 minor suggestion remains but does not block.",
  "strengths": [
    "Comprehensive data model with clear TypeScript interfaces",
    "Thorough error handling and edge cases",
    "Well-defined testing strategy"
  ]
}
```

### Not ready:
```json
{
  "ready": false,
  "confidence": 0.55,
  "sections_complete": 11,
  "sections_total": 15,
  "blocking_issues": 2,
  "attention_issues": 3,
  "unanswered_questions": 4,
  "requirements_covered": 5,
  "requirements_total": 8,
  "recommendation": "Spec needs more work. Address blocking issues and answer remaining questions before proceeding.",
  "gaps": [
    "Data model section is incomplete - missing entity relationships",
    "Security considerations section is empty",
    "2 blocking review issues unresolved",
    "4 questions still unanswered"
  ]
}
```

---

## Approval Marker

**If the spec is ready (confidence >= 0.85)**, also create `.ralph/spec_approved.md`:

```markdown
# Spec Approved: [Feature Name]

- **Approved**: [ISO timestamp]
- **Confidence**: [score]
- **Sections Complete**: [N/N]
- **Blocking Issues**: 0
- **Unanswered Questions**: 0

## Next Steps

This spec is ready for implementation. Run:

\`\`\`bash
node .ralph/run.js [feature-name] plan
\`\`\`

To create an implementation plan, then:

\`\`\`bash
node .ralph/run.js [feature-name] full
\`\`\`

To build the feature.
```

Commit the approval marker:

```bash
git add .ralph/spec_approved.md
git commit -m "spec: approved - ready for implementation"
git push
```

---

## Decision Thresholds

| Confidence | Ready? | Action |
|------------|--------|--------|
| >= 0.90 | true | Ready for implementation |
| 0.85 - 0.89 | true | Ready with minor caveats |
| 0.70 - 0.84 | false | One more refinement cycle recommended |
| 0.50 - 0.69 | false | Address gaps and re-review |
| < 0.50 | false | Major revision needed |

---

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — Read-only check
- **NEVER modify `.ralph/specs/*.md`** — All spec files are read-only
- **NEVER modify `.ralph/spec_seed.md`** — User input is sacred
- **Only create `.ralph/spec_approved.md`** if the spec is ready
- **Be honest** — Don't approve a spec that isn't ready. It's better to iterate than to ship a bad spec.

**Respond with JSON only (plus approval marker file if ready). No other output.**
