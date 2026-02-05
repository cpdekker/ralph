# Ralph Wiggum Loop — Expert Reference

## Origin

Invented by **Geoffrey Huntley** in mid-2025. Named after the lovably persistent Simpsons character. The philosophy: "the loop is the hero, not the model." Went viral July 2025 via blog post; by December 2025 Anthropic released an official plugin. By 2026 it's a mainstream agentic coding technique.

---

## The Core Pattern

```bash
while :; do cat PROMPT.md | claude ; done
```

That's it. A bash loop that repeatedly feeds a prompt to an AI coding agent. Each iteration spawns a **fresh context window**. State persists in **files and git**, not in the LLM's memory.

### Why Fresh Context Matters

Long-running LLM conversations accumulate failed attempts, unrelated code, and mixed concerns — "context pollution." Huntley's analogy: "like a bowling ball in the gutter, there's no saving it." Ralph deliberately rotates to a clean context before pollution builds up.

---

## Architecture

### The Loop Process (per iteration)

1. Fresh AI instance spawns with clean context
2. Reads prompt, progress tracker, and guardrails
3. Selects highest-priority incomplete task
4. Implements within a single context window
5. Runs quality checks (typecheck, tests, lint)
6. Commits successful work
7. Updates progress/completion tracking
8. Repeats until all tasks pass or max iterations hit

### Completion Signal

The loop terminates when the agent outputs a **completion promise**: `<promise>COMPLETE</promise>`. A stop hook intercepts exit attempts and re-feeds the prompt if the promise isn't found.

### Two-Layer Loop (SDK implementations)

- **Inner loop:** Standard LLM tool calling (LLM ↔ tools ↔ LLM)
- **Outer loop:** Verification and iteration control until `verifyCompletion` returns true

---

## Key Concepts

### State Persistence

State lives in files, not in the LLM's memory:

| Mechanism | Purpose |
|-----------|---------|
| **Git history** | Preserves implemented code across iterations |
| **progress.txt** | Append-only learnings and context for future iterations |
| **prd.json** | Task list with pass/fail completion status per story |
| **AGENTS.md / CLAUDE.md** | Discovered patterns, conventions, gotchas — read automatically by agents |
| **.ralph/guardrails.md** | Reusable instructions preventing repeated mistakes across rotations |

### Token Budget Management

- **Green (< 60% context):** Agent operates freely
- **Yellow (60-80%):** Agent receives completion heads-up
- **Red (> 80%):** Forced rotation to fresh context

### Gutter Detection

Identifies when agents are stuck: repeated failures, file thrashing, circular edits. Triggers context rotation or escalation.

### Feedback Loops (Non-Negotiable)

Every iteration must run before committing:
- TypeScript/type checking catches mismatches
- Unit/integration tests verify behavior
- Linters enforce style
- Pre-commit hooks block bad commits

Rule: **"Do NOT commit if any feedback loop fails."**

### Guardrails

When something fails, agents document "Signs" in guardrails files — reusable instructions that prevent repeated mistakes across context rotations. Each failure makes future iterations smarter.

---

## Best Practices

### 1. HITL → AFK Progression

Start **human-in-the-loop** (single iteration, observing and intervening). Refine your prompt. Once confident, switch to **AFK mode** with capped iterations:
- 5-10 iterations for small tasks
- 30-50 for larger ones

### 2. Small, Focused Stories

Each PRD item must be completable within a single context window. Right-sized:
- Adding database columns with migrations
- Creating UI components on existing pages
- Updating server actions with new logic

Oversized (will fail):
- "Build entire dashboard"
- Anything requiring cross-cutting changes across many files

### 3. Machine-Verifiable Success Criteria

Ralph excels when "done" is objectively measurable:
- **Good:** "All tests pass," "endpoint returns 200," "migration runs without errors"
- **Bad:** "Make it prettier," "improve the UX," "clean up the code"

Use user story format: description → success criteria → pass/fail verification.

### 4. Track Progress Religiously

Maintain `progress.txt` committed after each iteration. Include:
- Completed tasks and decisions made
- Blockers encountered
- Files changed
- Lessons learned

This prevents re-exploration and gives future iterations full context without token waste.

### 5. Prioritize Risky Tasks First

Tackle architectural decisions, integration points, and unknowns first (in HITL mode). Save AFK mode for lower-risk implementation once core architecture is proven. Fail fast on risky work; save easy wins for later.

### 6. Define Quality Expectations Explicitly

State whether code is prototype, production, or library quality. If Ralph sees shortcuts in existing code, it will copy them. Clean the codebase before Ralph begins.

### 7. Use Docker Sandboxes for Unattended Runs

```bash
docker sandbox run claude
```

Isolated container: can edit project files and commit, cannot access SSH keys, home directories, or system files. Essential for overnight loops.

### 8. Declarative Over Imperative

Ralph excels with declarative specifications ("the system should do X") over imperative instructions ("first do A, then B, then C").

### 9. Code Is Cheap

Re-running the loop on fresh code beats merge conflicts. Don't be precious about individual iterations.

---

## Ideal Use Cases

| Good Fit | Bad Fit |
|----------|---------|
| Test-driven refactoring | Subjective design judgment |
| Code migrations | Production debugging |
| API implementations with integration tests | Ambiguous success criteria |
| Greenfield projects with clear specs | Time-sensitive operations |
| Batch processing and triage | High-security systems without supervision |
| Overnight/cron-based refactors | Creative/aesthetic work |

---

## Advanced Patterns

### Parallel Execution

Combine with **git worktrees** to run multiple Ralph loops simultaneously on different feature branches.

### Multi-Phase Chaining

Sequential Ralph loops where each phase's completion promise triggers the next phase's initialization.

### Nightly Cron

Running Ralph once nightly produces manageable daily refactors rather than overwhelming changes.

### Overbaking

When the loop runs too long, it produces unexpected emergent behaviors (Huntley's example: post-quantum cryptography support appearing unprompted). Cap iterations to prevent this.

---

## Implementation Variants

### Bare Bash Loop (Original)

```bash
while :; do cat PROMPT.md | claude ; done
```

### snarktank/ralph (Full Framework)

- `ralph.sh` — bash loop spawning fresh AI instances
- `prd.json` — task list with completion status
- `progress.txt` — cumulative learnings
- Skills for PRD generation and conversion
- Automatic archiving of completed runs

### Vercel Labs ralph-loop-agent (AI SDK)

- Wraps AI SDK `generateText` in outer verification loop
- Stop conditions: iteration count, token budget, cost ceiling
- `verifyCompletion` callback with feedback injection
- Streaming support for final iteration

### Anthropic Official Plugin (Claude Code)

- Stop hook inside Claude session
- Completion promise mechanism
- `--max-iterations` safety cap
- `/ralph-loop:ralph-loop "<prompt>"` command interface

---

## Economics

- Huntley delivered a $50K contract scope for $297 in API costs
- Y Combinator hackathon: 6 repositories generated overnight by a single developer
- Requires significant token spend (Cursor Ultra/Max tier or equivalent API budget)
- The calculation: autonomous development hours vs. human coordination days

---

## Key Quotes

- "Ralph is a Bash loop." — Geoffrey Huntley
- "The loop is the hero, not the model."
- "Dumb things can work surprisingly well."
- "Code is cheap; re-running the loop on fresh code beats merge conflicts."
- "Like a bowling ball in the gutter, there's no saving it." (on context pollution)
- "Every shortcut becomes someone else's burden."

---

## Sources

- [Geoffrey Huntley — ghuntley.com/ralph](https://ghuntley.com/ralph/)
- [DEV Community — 2026: Year of the Ralph Loop Agent](https://dev.to/alexandergekov/2026-the-year-of-the-ralph-loop-agent-1gkj)
- [DevInterrupted — Inventing the Ralph Wiggum Loop](https://devinterrupted.substack.com/p/inventing-the-ralph-wiggum-loop-creator)
- [HumanLayer — A Brief History of Ralph](https://www.humanlayer.dev/blog/brief-history-of-ralph)
- [AI Hero — 11 Tips For AI Coding With Ralph Wiggum](https://www.aihero.dev/tips-for-ai-coding-with-ralph-wiggum)
- [Awesome Claude — Ralph Wiggum for Claude Code](https://awesomeclaude.ai/ralph-wiggum)
- [GitHub — snarktank/ralph](https://github.com/snarktank/ralph)
- [GitHub — vercel-labs/ralph-loop-agent](https://github.com/vercel-labs/ralph-loop-agent)
- [ISHIR — Ralph Wiggum AI Coding Loops](https://www.ishir.com/blog/312751/ralph-wiggum-and-ai-coding-loops-from-springfield-to-real-world-software-automation.htm)
- [VentureBeat — How Ralph Wiggum became the biggest name in AI](https://venturebeat.com/technology/how-ralph-wiggum-went-from-the-simpsons-to-the-biggest-name-in-ai-right-now)
