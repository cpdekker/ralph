# SPEC RESEARCH - Codebase & Best Practices Analysis

You are researching a codebase and gathering best practices to inform the creation of a detailed feature specification.

## Setup

1. Read `.ralph/spec_seed.md` to understand what the user wants to build
2. Read `.ralph/AGENTS.md` for project conventions, tech stack, and build commands
3. Read `.ralph/specs/sample.md` to understand the target spec format
4. Check `.ralph/references/` for any reference materials the user provided (existing implementations, sample data, documentation, etc.)

---

## Your Task

**Conduct thorough research using subagents, then produce `.ralph/spec_research.md`.**

### Phase 0: Reference Materials Analysis

If `.ralph/references/` contains any files (beyond README.md):

1. **Analyze all reference materials** — existing implementations, sample data, documentation
2. **Extract patterns** — code structure, naming conventions, data formats
3. **Identify requirements** — what the reference materials imply about the feature
4. **Note discrepancies** — if references conflict with each other or the spec_seed, flag them

Include findings in the "Reference Materials" section of spec_research.md.

### Phase 1: Codebase Analysis

Use up to 500 parallel Sonnet subagents to analyze the codebase:

1. **Tech Stack Identification**
   - Languages, frameworks, and libraries in use
   - Package manager, build tools, test frameworks
   - Database and ORM/query layer
   - API framework and routing patterns

2. **Architecture Patterns**
   - How is the codebase organized? (monorepo, modular, layered, etc.)
   - Design patterns in use (repository, service, factory, etc.)
   - State management approach (if frontend)
   - How do existing features structure their code?

3. **Existing Patterns for Similar Features**
   - Search for code that does something similar to what the spec_seed describes
   - How are existing features structured? (files, folders, naming)
   - What testing patterns are used for similar features?
   - What shared utilities or helpers exist that could be reused?

4. **Data Model & Infrastructure**
   - Database tables/collections relevant to the feature
   - Existing API endpoints that relate to or could be extended
   - Authentication/authorization patterns
   - Caching, queuing, or other infrastructure patterns

5. **Reusable Components**
   - Shared UI components (if frontend)
   - Shared services, utilities, or helpers
   - Common validation patterns
   - Error handling patterns

### Phase 2: Best Practices Research

Based on the tech stack and feature requirements:

1. **Industry Standards** — What are the accepted patterns for this type of feature?
2. **Security Considerations** — What security concerns apply to this feature?
3. **Performance Considerations** — What performance patterns are relevant?
4. **Accessibility** — What accessibility requirements apply (if UI)?
5. **Testing Strategy** — What testing approaches work best for this type of feature?

### Phase 3: Gap Analysis

1. **What exists vs. what's needed** — Where does the codebase need new code vs. extension?
2. **Missing infrastructure** — Are any new packages, services, or integrations needed?
3. **Risk areas** — What existing code might need modification? What could break?
4. **Open questions** — What ambiguities need user input to resolve?

---

## Output Format

Write your findings to `.ralph/spec_research.md` using this structure:

```markdown
# Spec Research: [Feature Name]

## Reference Materials Summary
[If .ralph/references/ contained files, summarize what was found]
- **Files analyzed**: [list of files]
- **Key patterns extracted**: [patterns from existing implementations]
- **Data formats identified**: [from sample data files]
- **Requirements from docs**: [requirements from documentation]
- **Discrepancies noted**: [any conflicts between references]

## Tech Stack Summary
- **Language**: [e.g., TypeScript]
- **Framework**: [e.g., Next.js 14]
- **Database**: [e.g., PostgreSQL via Prisma]
- **Testing**: [e.g., Jest + React Testing Library]
- **Other**: [relevant tools]

## Codebase Architecture
[Brief description of how the codebase is organized]

### Relevant Patterns
[Design patterns found that apply to this feature]

### Existing Similar Features
[Features that follow a similar pattern to what we're building]
- [Feature A]: [how it's structured, what we can learn]
- [Feature B]: [how it's structured, what we can learn]

## Reusable Components & Utilities
[What already exists that we should use]
- [Component/utility]: [what it does, where it lives]

## Data Model Context
[Existing tables/models relevant to the feature]
- [Table/Model]: [relevant fields, relationships]

## API Context
[Existing endpoints relevant to the feature]
- [Endpoint]: [what it does, request/response shape]

## Best Practices & Standards
[Industry standards for this type of feature]

## Security Considerations
[Security concerns specific to this feature]

## Performance Considerations
[Performance patterns relevant to this feature]

## Gap Analysis
### What Exists
[Code/infrastructure already in place]

### What's Needed
[New code/infrastructure required]

### Risk Areas
[Existing code that might need modification]

## Open Questions for User
[Ambiguities that need user input — these will become questions in the draft phase]
1. [Question about requirement X]
2. [Question about approach Y]
3. [Question about constraint Z]

## Recommended Architecture
[High-level recommendation for how to structure this feature, based on codebase patterns]
```

---

## Commit and Push

After writing spec_research.md:

```bash
git add .ralph/spec_research.md
git commit -m "spec: research phase complete"
git push
```

Then STOP. The next phase will use your research to draft the spec.

---

## Critical Rules

- **NEVER modify `.ralph/specs/*.md`** — Spec files are read-only
- **NEVER modify `.ralph/spec_seed.md`** — The user's input is sacred
- **NEVER implement any code** — This is research only
- **Be thorough** — The draft phase depends entirely on the quality of your research
- **Be specific** — Include file paths, function names, and concrete examples
