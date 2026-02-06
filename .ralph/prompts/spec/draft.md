# SPEC DRAFT - Generate Full Specification

You are generating a comprehensive feature specification from research findings and user input.

## Setup

1. Read `.ralph/spec_seed.md` — the user's initial input (requirements, preferences, constraints)
2. Read `.ralph/spec_research.md` — codebase analysis and best practices findings
3. Read `.ralph/specs/sample.md` — the **template** to follow (every section must be filled)
4. Read `.ralph/AGENTS.md` for project conventions
5. Check `.ralph/references/` for any reference materials (existing implementations, sample data, docs) — use these as primary sources for data formats, API patterns, and implementation details

---

## Your Task

**Generate two files:**

1. **`specs/{FEATURE_NAME}.md`** — A complete, detailed specification following the sample.md template
2. **`.ralph/spec_questions.md`** — Structured questions for the user about ambiguities

The `{FEATURE_NAME}` comes from the spec_seed.md file (look for the feature name at the top).

---

## Spec Generation Rules

### Content Quality

- **No placeholders** — Every section from sample.md must be filled with concrete, specific content
- **No "[TBD]" or "[TODO]"** — If you're unsure, make a reasonable assumption and flag it as a question
- **Use codebase patterns** — Architecture, file structure, naming, and testing should follow patterns found in spec_research.md
- **Be specific** — Include file paths, function signatures, data types, and concrete examples
- **Quantify requirements** — "fast" → "< 200ms response time", "secure" → specific security measures
- **Include edge cases** — Think about what happens when things go wrong

### Structure

Follow the sample.md template exactly. Every section must be present and filled:

1. **Overview** — What this feature does and its value
2. **Problem Statement** — Current limitations and impact
3. **Requirements** — Functional and non-functional, specific and testable
4. **Architecture** — High-level design with ASCII diagram, design pattern rationale
5. **Data Model** — Tables, schemas, API response types (use TypeScript interfaces)
6. **Data Transformations** — If applicable
7. **Caching Strategy** — If applicable (or explain why not needed)
8. **File Structure** — Exact files to create/modify, following project conventions
9. **UI Design** — If applicable, with ASCII wireframe and state variations
10. **Error Handling** — Graceful degradation, edge cases table
11. **Testing Strategy** — Unit, integration, manual test checklist
12. **Security Considerations** — Authentication, validation, injection prevention
13. **Future Enhancements** — What's out of scope but worth noting
14. **Dependencies** — Existing and new
15. **Glossary** — Domain terms

### Grounding

- **Reference Materials**: If `.ralph/references/` contains files, treat them as the primary source of truth for data formats, API shapes, and implementation patterns
- **Architecture**: Base on patterns found in spec_research.md, not generic patterns
- **File Structure**: Follow the project's actual directory structure and naming conventions
- **Data Model**: Build on existing tables/models identified in research
- **API Design**: Follow existing API patterns (REST/GraphQL, naming, error formats)
- **Testing**: Use the project's actual test framework and patterns

---

## Questions File Format

Write `.ralph/spec_questions.md` with this structure:

```markdown
# Spec Questions: [Feature Name]

> Answer questions by filling in the `A:` lines below. Leave blank to accept the default assumption.
> After answering, run another spec iteration to incorporate your answers.

## Status
- Total questions: N
- Answered: 0
- Unanswered: N

---

## Questions

### 1. [Short question title]
**Context**: [Why this matters and what part of the spec it affects]
**Default assumption**: [What the spec currently assumes]

Q: [The actual question]
A:

---

### 2. [Short question title]
**Context**: [Why this matters]
**Default assumption**: [Current assumption]

Q: [The question]
A:

---
```

### Question Quality

- **Ask about ambiguities**, not obvious things
- **Provide context** so the user understands why you're asking
- **Include default assumptions** so the user can just accept them if they agree
- **Prioritize** — most impactful questions first
- **Limit to 5-10 questions** — don't overwhelm the user
- **Draw from research** — spec_research.md's "Open Questions" section should inform your questions

---

## Commit and Push

After creating both files:

```bash
git add .ralph/specs/{FEATURE_NAME}.md .ralph/spec_questions.md
git commit -m "spec: initial draft generated"
git push
```

Then STOP. The next phase will refine based on user answers.

---

## Critical Rules

- **NEVER modify `.ralph/spec_seed.md`** — The user's input is sacred
- **NEVER modify `.ralph/spec_research.md`** — Research findings are read-only
- **NEVER modify `.ralph/specs/sample.md`** — The template is read-only
- **Follow sample.md structure exactly** — Every section must be present
- **No implementation** — This creates the spec, not the code
- **Be opinionated** — Make decisions where possible, ask questions only for genuine ambiguities
