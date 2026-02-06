# Ralph Wiggum - Project Setup

This directory was created by `ralph init`. It contains project-specific configuration for the Ralph AI agent.

## Quick Start

```bash
# Create a feature spec
ralph spec my-feature

# Or copy the sample spec
cp .ralph/specs/sample.md .ralph/specs/my-feature.md
# Edit it with your requirements

# Plan the implementation
ralph plan my-feature

# Build it
ralph build my-feature

# Review the code
ralph review my-feature

# Or run the full cycle (plan → build → review → check, repeats until done)
ralph full my-feature
```

## Commands

| Command | Description |
|---------|-------------|
| `ralph init` | Initialize Ralph in a repo (you already did this) |
| `ralph plan <spec>` | Analyze codebase, create implementation plan |
| `ralph build <spec>` | Implement tasks from the plan |
| `ralph review <spec>` | Review implementation for issues |
| `ralph review-fix <spec>` | Fix issues found during review |
| `ralph full <spec>` | Full autonomous cycle (plan→build→review→check) |
| `ralph debug <spec>` | Single iteration, verbose, no commits |
| `ralph decompose <spec>` | Break large spec into sub-specs |
| `ralph spec <name>` | Create a spec interactively |
| `ralph` | Interactive mode |
| `ralph update` | Update Ralph to the latest version |

### Common Options

```bash
ralph build my-feature -n 20       # Run 20 iterations
ralph build my-feature -v          # Verbose output
ralph build my-feature -b          # Run in background (Docker clones repo)
ralph full my-feature -f           # Force foreground mode
```

## Files in This Directory

| File | Purpose |
|------|---------|
| `AGENTS.md` | Tells Ralph how to build and test your project. **Customize this.** |
| `IMPLEMENTATION_PLAN.md` | Auto-generated task list. Ralph updates this during plan/build. |
| `user-review.md` | Your manual feedback for Ralph. Write notes here between iterations. |
| `.env` | API credentials (git-ignored). Created during `ralph init`. |
| `.env.example` | Template for `.env` |
| `specs/` | Feature specifications. One `.md` file per feature. |
| `specs/sample.md` | Template spec to copy for new features. |

### Generated During Execution

| File | Purpose |
|------|---------|
| `state.json` | Checkpoint state for resuming interrupted runs (git-ignored) |
| `review.md` | Auto-generated code review findings |
| `review_checklist.md` | Review items routed to specialist reviewers |
| `spec_seed.md` | Raw input from `ralph spec` wizard |
| `spec_questions.md` | Questions generated during spec refinement |
| `spec_review.md` | Spec review findings |
| `paused.md` | Created when circuit breaker trips (needs your attention) |

## Customizing Prompts

Ralph ships with built-in prompts for each mode (plan, build, review, etc.). You can **override any prompt** by placing a file with the same name in `.ralph/prompts/`.

### How It Works

When Ralph looks for a prompt file, it checks:
1. `.ralph/prompts/<name>.md` in your repo (local override)
2. The built-in prompt bundled with the CLI (default)

The local file wins if it exists.

### Example: Customize the Build Prompt

```bash
# Create the prompts directory
mkdir -p .ralph/prompts

# Copy the built-in prompt as a starting point
# (find it in the ralph package: lib/prompts/build.md)
cp $(npm root -g)/ralphai/lib/prompts/build.md .ralph/prompts/build.md

# Edit to your needs
$EDITOR .ralph/prompts/build.md
```

### Available Prompts

**Main Modes:**
- `plan.md` — How Ralph analyzes code and creates the implementation plan
- `build.md` — How Ralph picks tasks, implements code, and runs tests
- `decompose.md` — How Ralph breaks large specs into sub-specs
- `completion_check.md` — How Ralph decides if a spec is fully implemented
- `master_completion_check.md` — Completion check for decomposed specs
- `spec_select.md` — How Ralph picks the next sub-spec to work on

**Review Specialists:**
- `review/setup.md` — Creates the review checklist
- `review/general.md` — General review (fallback)
- `review/security.md` — Security-focused review
- `review/ux.md` — UX/accessibility review
- `review/db.md` — Database review
- `review/api.md` — API review
- `review/perf.md` — Performance review
- `review/qa.md` — QA review
- `review/fix.md` — Fixing review issues

**Spec Creation:**
- `spec/research.md` — Codebase research phase
- `spec/draft.md` — Initial spec draft
- `spec/refine.md` — Spec refinement with Q&A
- `spec/review.md` — Spec quality review
- `spec/review_fix.md` — Fix spec review issues
- `spec/signoff.md` — Final readiness check

### Tips for Customizing

- **AGENTS.md is the most impactful file to customize.** It's loaded into every iteration and tells Ralph about your project's build commands, test commands, conventions, and structure.
- **Start small.** Override one prompt, test it, then expand.
- **Keep overrides minimal.** Only change what you need — this makes upgrading easier.
- **Commit your overrides.** They're project-specific configuration, just like `.eslintrc`.

## How Ralph Works

Ralph uses the "Ralph Wiggum Loop" pattern — a repeating cycle where each iteration spawns a fresh Claude Code context. State persists in files and git, not in the LLM's memory.

```
┌─────────────────────────────────────┐
│         Ralph Loop (Docker)         │
│                                     │
│  ┌──→ Read spec + plan + AGENTS.md  │
│  │    Feed to Claude Code CLI       │
│  │    Claude implements / reviews   │
│  │    Run tests, commit, push       │
│  └──────────────────────────────────┘
│         Repeat N iterations
└─────────────────────────────────────┘
```

Each iteration gets a fresh context. This avoids "context pollution" where accumulated conversation history degrades output quality.

## Updating Ralph

```bash
ralph update
```

Or manually:
```bash
npm update -g ralphai
```

Your `.ralph/` directory won't be affected by updates. Only the CLI tool and its built-in prompts change. Any local prompt overrides you've created continue to take precedence.
