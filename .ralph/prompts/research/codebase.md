# RESEARCH - Codebase Analysis

You are researching a codebase to understand its structure, patterns, and current state in preparation for a new feature or change.

## Setup

1. Read `.ralph/research_seed.md` to understand what the user wants to research
2. Read `.ralph/AGENTS.md` for project conventions, tech stack, and build commands
3. Check `.ralph/references/` for any existing research documents — avoid duplicating work already done

---

## Your Task

**Use sub-agents to thoroughly analyze the codebase, then produce research documents in `.ralph/references/`.**

### Research Strategy

Based on what the user wants to build/change (from research_seed.md), investigate the codebase from multiple angles using parallel sub-agents. Each sub-agent should focus on a specific research question.

### Sub-Agent Topics

Launch **parallel sub-agents** (use the Agent tool with subagent_type=Explore) to investigate:

1. **Impact Analysis** — What files, modules, and systems would be affected by this change? Map the blast radius. Trace dependencies and call chains. Identify every file that touches the relevant functionality.

2. **Pattern Discovery** — How does the codebase handle similar features? Find 2-3 analogous implementations and document their structure (files, layers, naming, tests). These are the patterns we should follow.

3. **Data Model & API Surface** — What database tables, models, API endpoints, types, and interfaces are relevant? Document their current state — schemas, relationships, request/response shapes.

4. **Infrastructure & Configuration** — What build tools, CI/CD pipelines, environment variables, feature flags, or infrastructure components are relevant? What would need to change?

5. **Test Landscape** — What testing patterns exist for similar features? What test utilities, fixtures, mocks, or helpers are available? What's the testing strategy (unit, integration, e2e)?

6. **Gap Analysis** — What doesn't exist yet that would be needed? New packages, new database tables, new API routes, new UI components? What existing code would need modification vs. what's greenfield?

### Important: Scope Your Research

Not all topics are relevant to every research task. Based on research_seed.md:
- Skip topics that clearly don't apply (e.g., skip "Data Model" if the change is purely UI)
- Go deeper on topics that are central to the change
- Add custom research angles if the seed suggests them

---

## Output Format

Write **one .md file per major finding** to `.ralph/references/`. Use descriptive filenames:

```
.ralph/references/codebase-architecture.md      # Overall structure relevant to this change
.ralph/references/similar-features.md           # Analogous implementations found
.ralph/references/data-model.md                 # Relevant database/API schemas
.ralph/references/affected-files.md             # Files that will need changes
.ralph/references/test-patterns.md              # Testing approach for this type of change
.ralph/references/gaps-and-unknowns.md          # What's missing, what needs to be created
```

Each file should follow this structure:

```markdown
# [Topic Title]

## Summary
[2-3 sentence overview of findings]

## Findings

### [Finding 1]
- **Location**: [file paths]
- **Details**: [what was found]
- **Relevance**: [why this matters for our change]

### [Finding 2]
...

## Implications for Our Change
[How these findings affect our approach]
```

**Be specific** — include file paths, function names, line numbers, and concrete code examples. Vague findings are useless.

---

## Commit and Push

After writing reference documents:

```bash
git add .ralph/references/
git commit -m "research: codebase analysis complete"
git push
```

Then STOP. The next phase will handle web research.

---

## Critical Rules

- **NEVER implement any code** — This is research only, do not create or modify source code
- **NEVER modify existing `.ralph/references/*.md`** if they already exist from a previous iteration — create new files or append, don't overwrite prior research
- **Be thorough** — Later phases depend entirely on the quality of your research
- **Be specific** — Include file paths, function names, and concrete examples
- **Use sub-agents** — Do not try to research everything sequentially. Launch parallel agents for speed
- **Focus on facts** — Report what IS in the codebase, not what should be. Recommendations come later
