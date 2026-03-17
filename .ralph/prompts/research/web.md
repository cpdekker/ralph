# RESEARCH - Web Research & Best Practices

You are conducting web research to find patterns, best practices, and prior art relevant to a planned feature or change.

## Setup

1. Read `.ralph/research_seed.md` to understand what the user wants to research
2. Read `.ralph/AGENTS.md` for project conventions and tech stack
3. Read existing files in `.ralph/references/` to understand what codebase analysis has already found — build on it, don't repeat it
4. Check `.ralph/research_gaps.md` (if it exists) for specific knowledge gaps flagged by the review phase

---

## Your Task

**Use sub-agents to conduct web research, then produce reference documents in `.ralph/references/`.**

### Research Strategy

Based on the research seed and existing codebase findings, identify what external knowledge would be most valuable. Focus on filling gaps that the codebase analysis couldn't answer.

### Sub-Agent Topics

Launch **parallel sub-agents** (use the Agent tool) to research:

1. **Best Practices & Patterns** — What are the established best practices for this type of feature/change in the tech stack we're using? Look for official documentation, style guides, and recommended patterns.

2. **Prior Art & Examples** — Have others solved a similar problem? Find open-source implementations, blog posts, or tutorials that demonstrate the approach. Focus on production-quality examples, not toy demos.

3. **Library & Tooling Options** — Are there libraries, packages, or tools that would help? Compare options — what are the tradeoffs? What's actively maintained? What does the community recommend?

4. **Pitfalls & Anti-Patterns** — What common mistakes do people make with this type of change? What gotchas should we watch out for? Security implications? Performance traps?

5. **Migration & Upgrade Paths** — If we're modifying existing functionality, how have others handled similar migrations? Are there established patterns for backwards compatibility, data migration, or gradual rollout?

### Important: Targeted Research

- If `.ralph/research_gaps.md` exists, prioritize researching those specific gaps
- Skip topics that the codebase analysis already covered well
- Go deep on areas where the codebase has no existing patterns to follow
- Research should be specific to the tech stack in use (don't research React patterns for a Go backend)

---

## Output Format

Write **one .md file per research topic** to `.ralph/references/`. Use descriptive filenames with a `web-` prefix to distinguish from codebase research:

```
.ralph/references/web-best-practices.md         # Established patterns for this type of feature
.ralph/references/web-prior-art.md              # Similar implementations found online
.ralph/references/web-libraries.md              # Relevant packages/tools with comparison
.ralph/references/web-pitfalls.md               # Common mistakes and gotchas
.ralph/references/web-migration-patterns.md     # Migration approaches if applicable
```

Each file should follow this structure:

```markdown
# [Topic Title]

## Summary
[2-3 sentence overview of what was found]

## Sources

### [Source 1 Title]
- **URL**: [link]
- **Relevance**: [why this source matters]
- **Key Takeaways**:
  - [takeaway 1]
  - [takeaway 2]

### [Source 2 Title]
...

## Synthesis
[What do these sources collectively tell us? Where do they agree? Where do they disagree?]

## Recommendations
[Based on this research, what approach should we consider?]
```

### Source Quality Guidelines

- Prefer official documentation over blog posts
- Prefer recent sources (last 2 years) over old ones
- Prefer production examples over tutorials
- Note when sources conflict — don't hide disagreements
- If you can't find good sources for a topic, say so explicitly rather than padding with low-quality results

---

## Commit and Push

After writing reference documents:

```bash
git add .ralph/references/
git commit -m "research: web research complete"
git push
```

Then STOP. The next phase will review all research.

---

## Critical Rules

- **NEVER implement any code** — This is research only
- **NEVER modify codebase research files** — Files without the `web-` prefix are from codebase analysis; don't touch them
- **NEVER fabricate sources** — If you can't find good information, say so. Made-up references are worse than none
- **Be specific** — Include URLs, code snippets, and concrete examples
- **Use sub-agents** — Launch parallel research agents for different topics
- **Cite everything** — Every claim should trace back to a source
- **Distinguish fact from opinion** — Clearly separate what documentation says vs. what blog posts recommend
