# REVIEW DEBATE - Cross-Examination Round

You are facilitating a **Socratic cross-examination** between two code review specialists. Each specialist challenges the other's findings from their independent review, probing for missed issues, calibration errors, and cross-cutting concerns.

## Setup

1. Read `.ralph/review_debate/debate_plan.md` — the pairing plan with ordered rounds
2. Read `.ralph/review.md` — the full review findings from all specialists
3. Read `.ralph/specs/active.md` — the feature spec
4. Read `.ralph/AGENTS.md` — project conventions

---

## Phase Detection

Determine which round to execute:

1. Read the `PAIRINGS=` line from `debate_plan.md` to get the ordered pairing list
2. Check which `round{N}_*.md` files already exist in `.ralph/review_debate/`
3. The next unfinished round is your assignment

For example, if `PAIRINGS=security:api,db:perf,qa:antagonist` and `round1_security_api.md` exists but `round2_db_perf.md` does not, you execute Round 2: db vs perf.

---

## Your Task

**Read both specialists' sections from review.md, then write a cross-examination where each specialist challenges the other's findings using Socratic questioning.**

For each specialist in the pair, think from their perspective:
- What would a security expert ask about the DB specialist's findings?
- What would the DB specialist ask about the security expert's concerns?
- Where do their findings interact or conflict?
- What did one specialist miss that the other's perspective reveals?

---

## Cross-Examination Rules

1. **Ask questions, don't make statements** — "What happens to query performance if we add the input validation you recommended?" not "Your recommendation will hurt performance"
2. **Challenge severity ratings** — "You rated this as CONSIDER, but given [X], shouldn't this be NEEDS ATTENTION?"
3. **Find cross-cutting concerns** — Issues that span both specialists' domains
4. **Required: strongest argument against the other's top finding** — Each specialist MUST articulate the strongest counter-argument to the other's most critical finding, even if they ultimately agree
5. **Identify gaps** — What did both specialists miss when reviewing independently?
6. **Propose severity changes** — If cross-examination reveals a finding is more or less severe than originally rated

---

## Output Format

Write `.ralph/review_debate/round{N}_{specialist_a}_{specialist_b}.md`:

```markdown
# Cross-Examination: Round N — [Specialist A] vs [Specialist B]

## [Specialist A] Challenges [Specialist B]

### Re: [Specialist B's finding title]
- **Q**: [Socratic question from A's perspective]
- **Q**: [Follow-up probing deeper]
- **Severity assessment**: [Agree / Escalate to X / Downgrade to X] — [why]

### Re: [Another finding]
- **Q**: [Question]
- **Severity assessment**: [assessment]

### What [Specialist B] Missed (from [Specialist A]'s perspective)
1. [Gap identified] — **Suggested severity**: [BLOCKING/ATTENTION/CONSIDER]

---

## [Specialist B] Challenges [Specialist A]

### Re: [Specialist A's finding title]
- **Q**: [Socratic question from B's perspective]
- **Q**: [Follow-up]
- **Severity assessment**: [Agree / Escalate / Downgrade] — [why]

### What [Specialist A] Missed (from [Specialist B]'s perspective)
1. [Gap identified] — **Suggested severity**: [level]

---

## Cross-Cutting Concerns
[Issues that span both domains, only visible when combining both perspectives]

1. **[Concern title]** — [description]
   - **From [A]'s angle**: [how it manifests]
   - **From [B]'s angle**: [how it manifests]
   - **Suggested severity**: [level]

## Severity Changes Proposed

| Original Finding | Original Severity | Proposed Severity | Reason |
|-----------------|-------------------|-------------------|--------|
| [finding] | [original] | [proposed] | [why] |
```

---

## Reading Both Specialists' Findings

In `.ralph/review.md`, each specialist's findings are under their own section heading:
- Security findings under "Security Review"
- UX findings under "UX Review" or "Frontend Review"
- DB findings under "Database Review"
- Performance findings under "Performance Review"
- API findings under "API Review"
- QA findings under "QA Review"
- Antagonist findings under "Antagonist Review"

Read the relevant sections for both specialists in your assigned pairing.

---

## Commit and Push

```bash
git add .ralph/review_debate/round{N}_*.md
git commit -m "review: cross-examination round N complete"
git push
```

Then STOP.

---

## Critical Rules

- **NEVER modify `.ralph/review.md`** — Read-only during cross-examination
- **NEVER modify source code** — This is analysis, not fixing
- **Be specific** — Reference actual file paths, line numbers, and code from the review findings
- **Be constructive** — The goal is better review quality, not winning an argument
- **One round per invocation** — Only execute the next unfinished round, then stop
