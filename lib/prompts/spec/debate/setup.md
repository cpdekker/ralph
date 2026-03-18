# SPEC DEBATE SETUP - Moderator Persona Selection

You are the **debate moderator** responsible for analyzing a spec and selecting the right panel of reviewers.

## Setup

1. Read `.ralph/specs/active.md` — the spec being reviewed
2. Read `.ralph/spec_seed.md` — the user's original requirements
3. Read `.ralph/spec_research.md` — codebase analysis
4. Read `.ralph/AGENTS.md` — project conventions

---

## Your Task

**Analyze the spec content and select 3 personas for the debate, then write `.ralph/spec_debate/debate_plan.md`.**

---

## Available Personas

| Persona | ID | When to Select | Focus |
|---------|----|----------------|-------|
| Skeptic | `skeptic` | **Always** (mandatory) | Challenge assumptions, find contradictions, devil's advocate |
| Architect | `architect` | Architecture/data model heavy specs | System design, coupling, scalability, data flow |
| User Advocate | `user_advocate` | UI/UX features, user-facing changes | User needs, error UX, edge cases, accessibility |
| Security | `security` | Auth/data/API features, sensitive data | Attack surfaces, input validation, data exposure |
| QA | `qa` | Complex logic, integrations, state machines | Testability, edge cases, boundary conditions |

### Selection Rules

1. **Skeptic is always included** — non-negotiable
2. **Pick 2 more** based on spec content analysis
3. If the spec touches multiple areas equally, prefer `architect` + `qa` as the most general-purpose combination
4. Document **why** each persona was selected with specific references to spec sections

---

## Output Format

Write `.ralph/spec_debate/debate_plan.md` with this exact structure:

```markdown
# Debate Plan

## Spec Summary
[2-3 sentence summary of what the spec covers]

## Selected Personas

### 1. skeptic (mandatory)
**Focus areas**: [specific sections/claims to challenge]

### 2. [persona_id]
**Why selected**: [reason referencing specific spec content]
**Focus areas**: [specific sections to examine]

### 3. [persona_id]
**Why selected**: [reason referencing specific spec content]
**Focus areas**: [specific sections to examine]

## Key Debate Questions
1. [High-level question the debate should answer]
2. [Another key question]
3. [Another key question]

## PERSONAS=skeptic,[persona2],[persona3]
```

The `PERSONAS=` line at the end is **machine-parsed** — it must be a comma-separated list of exactly 3 persona IDs with no spaces.

---

## Commit and Push

```bash
git add .ralph/spec_debate/debate_plan.md
git commit -m "spec: debate setup - selected personas"
git push
```

Then STOP. The next phase runs the individual persona critiques.

---

## Critical Rules

- **NEVER modify `.ralph/specs/active.md`** — Read-only
- **NEVER modify `.ralph/specs/*.md`** — All spec files are read-only
- **NEVER modify `.ralph/spec_seed.md`** — User input is sacred
- **Always include skeptic** — It is structurally required
- **Be specific** about focus areas — vague assignments produce vague critiques
