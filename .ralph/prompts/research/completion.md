# RESEARCH - Completion Check

You are evaluating whether the research phase has gathered sufficient information to proceed to specification or implementation planning.

## Setup

1. Read `.ralph/research_seed.md` — the original research goals
2. Read `.ralph/research_review.md` — the review assessment
3. Read `.ralph/research_gaps.md` (if present) — identified knowledge gaps
4. Scan `.ralph/references/` — count and note the research documents available

---

## Your Task

**Assess research completeness and output a JSON result.**

---

## Evaluation Criteria

### For COMPLETE status (confidence >= 0.80)

ALL of the following must be true:

1. **Core questions answered** — The research seed's main questions have clear, sourced answers
2. **Codebase understood** — The affected code areas are mapped with file paths and patterns
3. **Approach identified** — At least one viable implementation approach is supported by research
4. **No critical gaps** — No codebase or best-practice gaps remain that would block planning
5. **Conflicts resolved** — Any contradictions between sources have been addressed
6. **Research quality >= 3/5** — The overall quality score from the review is adequate

### For NEEDS MORE WORK (confidence 0.50 - 0.79)

Some progress but gaps remain:

- Core questions partially answered
- Some codebase areas unexplored
- Approach options exist but not validated
- Minor gaps that targeted research could fill

### For INSUFFICIENT (confidence < 0.50)

Major gaps:

- Core questions unanswered
- Codebase poorly understood
- No clear approach identified
- Critical conflicts unresolved

---

## Gap Prioritization

If gaps remain, categorize them:

- **BLOCKING** — Cannot proceed to spec/plan without this. Needs another research iteration.
- **DEFERRABLE** — Nice to have but can be answered during planning/implementation.
- **USER_INPUT** — Requires the user to make a decision. Flag for user intervention.

Research is "complete enough" when no BLOCKING gaps remain.

---

## Response Format

You MUST respond with ONLY a valid JSON object. No markdown, no explanation, no other text.

### Complete:
```json
{
  "complete": true,
  "confidence": 0.88,
  "documents_count": 8,
  "quality_score": 4,
  "blocking_gaps": 0,
  "deferrable_gaps": 2,
  "user_input_gaps": 1,
  "recommendation": "Research is sufficient to proceed to spec creation. 2 minor gaps can be resolved during planning.",
  "strengths": [
    "Thorough codebase mapping of affected modules",
    "Strong best-practice coverage with multiple sources",
    "Clear implementation approach identified"
  ],
  "next_step": "spec"
}
```

### Not complete:
```json
{
  "complete": false,
  "confidence": 0.55,
  "documents_count": 4,
  "quality_score": 2,
  "blocking_gaps": 3,
  "deferrable_gaps": 1,
  "user_input_gaps": 0,
  "recommendation": "Research needs more work. Key gaps in codebase analysis and best practices.",
  "blocking_gap_details": [
    "Database schema for user_sessions table not documented — need codebase research",
    "No best practices found for rate limiting in this framework — need web research",
    "Authentication middleware flow not traced — need codebase research"
  ],
  "targeted_research": {
    "codebase": ["Trace authentication middleware chain", "Document user_sessions schema"],
    "web": ["Rate limiting patterns for Express.js"]
  },
  "next_step": "research"
}
```

---

## Decision Logic

```
IF blocking_gaps == 0 AND quality_score >= 3:
    complete = true, next_step = "spec"
ELSE IF only user_input_gaps remain:
    complete = false, next_step = "user_input"
ELSE:
    complete = false, next_step = "research"
```

When `next_step = "research"`, the `targeted_research` field tells the next research iteration exactly what to focus on.

When `next_step = "user_input"`, Ralph will pause and prompt the user to provide answers in `.ralph/research_gaps.md`.

---

## Critical Rules

- **NEVER modify any files** — This is a read-only assessment
- **NEVER modify `.ralph/research_seed.md`** — User input is sacred
- **Be honest** — Don't approve research that has real gaps. It's better to iterate than to build on shaky foundations
- **Be practical** — Don't demand perfection. Research is "good enough" when it won't cause us to make fundamentally wrong decisions in the spec/plan phase

**Respond with JSON only. No other output.**
