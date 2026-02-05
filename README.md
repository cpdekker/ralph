# Ralph Wiggum 🍩

An AI agent framework that uses Claude Code to iteratively implement features from specifications. Ralph runs in a loop, picking up tasks from your implementation plan and building them out—one iteration at a time.

**Why use Ralph?** Instead of manually prompting an AI for each change, Ralph autonomously works through a prioritized task list, running tests, committing code, and pushing changes. You define *what* to build; Ralph figures out *how* and executes it.

## Table of Contents

- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Interactive Mode](#interactive-mode)
  - [Command Line](#command-line)
  - [NPM Scripts](#npm-scripts)
- [Modes](#modes)
  - [Plan Mode](#plan-mode)
  - [Build Mode](#build-mode)
  - [Review Mode](#review-mode)
  - [Review-Fix Mode](#review-fix-mode)
  - [Debug Mode](#debug-mode)
  - [Full Mode](#full-mode)
  - [Decompose Mode](#decompose-mode)
- [Advanced Features](#advanced-features)
  - [Circuit Breaker](#circuit-breaker)
  - [Checkpointing](#checkpointing)
  - [Complexity Estimation](#complexity-estimation)
  - [Dynamic Batching](#dynamic-batching)
  - [Specialist Reviewers](#specialist-reviewers)
- [File Structure](#file-structure)
- [Branch Strategy](#branch-strategy)
- [Active Spec Pattern](#active-spec-pattern)
- [Customization](#customization)
- [Requirements](#requirements)
- [Tips](#tips)
- [Docker Image Updates](#docker-image-updates)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Codebase                            │
├─────────────────────────────────────────────────────────────────┤
│  .ralph/                                                        │
│  ├── specs/           ← Feature specifications (what to build) │
│  │   ├── my-feature.md   ← Your spec files                     │
│  │   └── active.md       ← Auto-copied from selected spec      │
│  ├── implementation_plan.md  ← Task checklist (what's left)    │
│  ├── AGENTS.md        ← Operational guide (how to build/test)  │
│  └── prompts/         ← Mode-specific instructions             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────┴──────────────────────────────────┐
│                     Ralph (Docker Container)                    │
│  1. Copies spec → active.md                                     │
│  2. Reads active.md & implementation plan                       │
│  3. Picks highest-priority incomplete task                      │
│  4. Implements using Claude Code + subagents                    │
│  5. Runs tests, updates plan, commits & pushes                  │
│  6. Loops until done (with circuit breaker protection)          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Copy `.ralph` into your project

Copy the `.ralph` directory to the root of your repository.

### 2. Run the setup wizard (recommended)

```bash
node .ralph/setup.js
```

The interactive setup wizard will guide you through:
- ✅ Checking prerequisites (Docker, Node.js, Git)
- ✅ Creating and configuring `.ralph/.env` with your API credentials
- ✅ Adding `.ralph/.env` to `.gitignore`
- ✅ Adding npm scripts to `package.json` (if present)
- ✅ Generating `AGENTS.md` using Claude (analyzes your codebase)
- ✅ Building the Docker image

### 2b. Manual setup (alternative)

<details>
<summary>Click to expand manual setup instructions</summary>

Add to .gitignore:

```.gitignore
# Ralph
.ralph/.env
```

```bash
cp .ralph/.env.example .ralph/.env
```

Edit `.ralph/.env` and add:

```env
AWS_BEARER_TOKEN_BEDROCK=...

GIT_USER=your-github-username
GIT_TOKEN=ghp_your_personal_access_token
```

| Variable | Where to get it |
|----------|-----------------|
| `AWS_BEARER_TOKEN_BEDROCK` | [AWS Bedrock Console](https://us-west-2.console.aws.amazon.com/bedrock/home?region=us-west-2#/api-keys?tab=short-term) |
| `GIT_TOKEN` | [GitHub Personal Access Tokens](https://github.com/settings/tokens) — use minimal permissions, repo-scoped |

Update `.ralph/AGENTS.md` with your project's build commands, test commands, and critical patterns.

</details>

### 3. Customize AGENTS.md

Update `.ralph/AGENTS.md` with your project's build commands, test commands, and critical patterns (the setup wizard can help with this).

<details>
<summary>💡 Sample prompt to generate AGENTS.md</summary>

> Analyze this codebase and create a `.ralph/AGENTS.md` file. Include:
> 1. **Build & Validate** - Commands to build, test, and lint the project
> 2. **Critical Rules** - Important patterns, conventions, or gotchas specific to this codebase
> 3. **Project Structure** - Brief overview of where key code lives
> 4. **Key Patterns** - Architecture patterns used (e.g., repository pattern, dependency injection)
> 5. **Git** - Any specific git workflows or branch naming conventions
>
> Keep it brief and operational—this file is loaded into every AI iteration's context.

</details>

### 4. Create your spec

Work with your AI agent to create a detailed specification. Save it to `.ralph/specs/my-feature.md`.
A sample prompt template to work off of is defined in `.ralph/prompts/requirements.md`

### 5. Build the Docker image

```bash
node .ralph/docker-build.js
```

### 6. Run Ralph

```bash
# Interactive mode - prompts for spec and mode
node .ralph/run.js

# Or specify directly
node .ralph/run.js my-feature plan       # Plan first
node .ralph/run.js my-feature build      # Then build
node .ralph/run.js my-feature review     # Review the implementation
node .ralph/run.js my-feature review-fix # Fix review findings
node .ralph/run.js my-feature debug      # Debug mode (single iteration, no commit)
node .ralph/run.js my-feature full       # Full autonomous cycle
node .ralph/run.js my-feature decompose  # Break large spec into sub-specs
```

> ⚠️ **After plan mode**: Review `.ralph/specs/active.md` and `implementation_plan.md`. Ensure you agree with every line—these drive the build phase.

> ⚠️ **During build mode**: Monitor Ralph's progress. If he strays, interrupt and update `AGENTS.md` to steer him, re-run plan mode, or scrap the plan and spec and start over.

> 💡 **After build mode**: Run review mode to catch bugs, bad patterns, and incomplete implementations before merging.

---

## Usage

### Interactive Mode

Run without arguments for a guided experience:

```bash
node .ralph/run.js
```

```
🍩 Ralph Wiggum - Interactive Mode

Available specs:
  1. my-feature
  2. auth-system

Enter spec name (or number): 1

Modes:
  1. plan       - Analyze codebase and create implementation plan
  2. build      - Implement tasks from the plan
  3. review     - Review implementation for bugs and issues
  4. review-fix - Fix issues identified during review
  5. debug      - Single iteration, verbose, no commits
  6. full       - Full cycle: plan → build → review → check (repeats until complete)
  7. decompose  - Break large spec into ordered sub-specs for full mode

Select mode [1-7 or name] (default: build): plan
Number of iterations (default: 5): 
```

### Command Line

```bash
node .ralph/run.js <spec-name> [mode] [iterations] [--verbose]
node .ralph/run.js [--plan|--build|--review|--full|--decompose] [--verbose]  # Interactive with mode pre-selected
```

| Argument | Description | Default |
|----------|-------------|---------|
| `spec-name` | Name of spec file (without `.md`) | Required (or interactive) |
| `mode` | `plan`, `build`, `review`, `review-fix`, `debug`, `full`, or `decompose` | `build` |
| `iterations` | Number of loop iterations (or cycles for full mode) | 5 (plan) / 10 (build/review/full) / 1 (decompose) |
| `--verbose` / `-v` | Show full Claude output (JSON stream) | Off (shows summary only) |
| `--plan` | Pre-select plan mode in interactive | — |
| `--build` | Pre-select build mode in interactive | — |
| `--review` | Pre-select review mode in interactive | — |
| `--full` / `--yolo` | Pre-select full mode in interactive | — |
| `--decompose` | Pre-select decompose mode in interactive | — |
| `--background` / `-b` | Run in background (Ralph clones repo) | Off (On for full mode) |
| `--foreground` / `-f` / `--no-background` | Force foreground mode | — |

Examples:

```bash
node .ralph/run.js my-feature              # Build mode, 10 iterations, quiet
node .ralph/run.js my-feature plan         # Plan mode, 5 iterations, quiet
node .ralph/run.js my-feature build 20     # Build mode, 20 iterations, quiet
node .ralph/run.js my-feature review       # Review mode, 10 iterations, quiet
node .ralph/run.js my-feature review-fix   # Review-fix mode, 5 iterations
node .ralph/run.js my-feature debug        # Debug mode (1 iteration, verbose, no commit)
node .ralph/run.js my-feature full         # Full mode, 10 max cycles
node .ralph/run.js my-feature full 20      # Full mode, 20 max cycles
node .ralph/run.js my-feature decompose    # Decompose large spec into sub-specs
node .ralph/run.js my-feature --verbose    # Build mode with full output
```

### NPM Scripts

Add to your `package.json`:

```json
{
  "scripts": {
    "ralph": "node .ralph/run.js",
    "ralph:plan": "node .ralph/run.js --plan",
    "ralph:build": "node .ralph/run.js --build",
    "ralph:review": "node .ralph/run.js --review",
    "ralph:full": "node .ralph/run.js --full",
    "ralph:yolo": "node .ralph/run.js --full",
    "ralph:decompose": "node .ralph/run.js --decompose",
    "ralph:docker": "node .ralph/docker-build.js"
  }
}
```

Then run:

```bash
npm run ralph                              # Interactive mode
npm run ralph:plan                         # Interactive with plan mode pre-selected
npm run ralph:full                         # Full autonomous cycle
npm run ralph -- my-feature debug          # Debug mode
```

---

## Modes

### Plan Mode

```bash
node .ralph/run.js <spec-name> plan [iterations]
```

| What it does | What it doesn't do |
|--------------|--------------------|
| ✅ Analyzes codebase against spec | ❌ Write any code |
| ✅ Creates/updates `implementation_plan.md` | ❌ Run tests |
| ✅ Adds complexity tags (`[Simple]`, `[Medium]`, `[Complex]`) | ❌ Make commits |
| ✅ Tracks dependencies between tasks | |
| ✅ Identifies high-risk items | |

**When to use**: Starting a new feature, or reassessing priorities mid-project.

### Build Mode

```bash
node .ralph/run.js <spec-name> [build] [iterations]
```

| What it does |
|--------------|
| ✅ Picks highest-priority incomplete task |
| ✅ Batches simple tasks (up to 3 `[Simple]` items per turn) |
| ✅ Implements using Claude Code + subagents |
| ✅ Runs tests after each change |
| ✅ Reverts and documents if stuck (3-strikes rule) |
| ✅ Commits and pushes after success |
| ✅ Updates `implementation_plan.md` |

**When to use**: After you've reviewed and approved the plan.

### Review Mode

```bash
node .ralph/run.js <spec-name> review [iterations]
```

| What it does | What it outputs |
|--------------|-----------------|
| ✅ Creates `review_checklist.md` (setup phase) | 📄 `review_checklist.md` - tracking document |
| ✅ Reviews up to 5 items per iteration | 📄 `review.md` - comprehensive findings |
| ✅ Compares implementation against spec | |
| ✅ Detects bugs, bad patterns, security issues | |
| ✅ Logs issues with file paths and line numbers | |
| ✅ **Routes to specialist reviewers** based on file type and content | |

**Specialist Reviewers**: Items are automatically routed to the right expert:

| Specialist | Tag | Focus Areas |
|------------|-----|-------------|
| 🔒 **Security** | `[SEC]` | Authentication, authorization, input validation, secrets, encryption |
| 🗄️ **DB Expert** | `[DB]` | SQL queries, migrations, data models, query performance, data integrity |
| 🔌 **API Expert** | `[API]` | REST endpoints, API contracts, error responses, documentation |
| ⚡ **Performance** | `[PERF]` | Algorithm complexity, caching, memory usage, N+1 queries |
| 🎨 **UX Expert** | `[UX]` | React/Vue components, CSS, accessibility, responsive design |
| 🔍 **QA Expert** | `[QA]` | Business logic, error handling, testing, general quality |

**When to use**: After build mode, before merging. Review findings feed back into plan mode.

### Review-Fix Mode

```bash
node .ralph/run.js <spec-name> review-fix [iterations]
```

| What it does |
|--------------|
| ✅ Fixes BLOCKING and NEEDS ATTENTION issues from review |
| ✅ Updates `review.md` to mark issues as resolved |
| ✅ Adds regression tests for fixes |
| ✅ Commits with `fix:` prefix |

**When to use**: After review mode identifies issues. Bridges the gap between review findings and the next build cycle.

### Debug Mode

```bash
node .ralph/run.js <spec-name> debug
```

| What it does | What it doesn't do |
|--------------|--------------------|
| ✅ Runs exactly 1 iteration | ❌ Commit changes |
| ✅ Forces verbose output | ❌ Push to remote |
| ✅ Shows full Claude reasoning | ❌ Run multiple iterations |

**When to use**: Testing prompt changes, debugging Ralph behavior, or understanding why something failed.

### Full Mode

```bash
node .ralph/run.js <spec-name> full [max-cycles]
```

| What it does |
|--------------|
| ✅ Runs complete cycles: Plan → Build → Review → Review-Fix → Check |
| ✅ Automatically checks if implementation is complete after each cycle |
| ✅ Reports confidence scores (0.0 - 1.0) |
| ✅ Exits early when spec is fully implemented |
| ✅ Protected by circuit breaker |
| ✅ **Runs in background by default** |
| ✅ **Supports decomposed specs** — auto-cycles through sub-specs when manifest exists |

**Default iterations per cycle**:
| Phase | Default | Environment Variable |
|-------|---------|---------------------|
| Plan | 5 | `FULL_PLAN_ITERS` |
| Build | 10 | `FULL_BUILD_ITERS` |
| Review | 15 | `FULL_REVIEW_ITERS` |
| Review-Fix | 5 | `FULL_REVIEWFIX_ITERS` |

**When to use**: When you want fully autonomous implementation with minimal supervision.

**With decomposed specs**: If a manifest exists (`specs/{name}/manifest.json`), full mode automatically:
1. Runs **spec select** to pick the next sub-spec
2. Completes one full cycle (plan → build → review → check) for that sub-spec
3. Marks the sub-spec complete and selects the next one
4. After all sub-specs complete, runs a **master completion check** to verify holistic coverage
5. Warns you if a spec is large (200+ lines) but hasn't been decomposed yet

### Decompose Mode

```bash
node .ralph/run.js <spec-name> decompose
```

| What it does | What it creates |
|--------------|-----------------|
| ✅ Analyzes master spec for natural boundaries | 📁 `specs/{name}/` directory |
| ✅ Identifies dependencies between components | 📄 Numbered sub-spec files (`01-data-model.md`, etc.) |
| ✅ Sizes each sub-spec for ~1 full mode cycle | 📄 `manifest.json` tracking progress |
| ✅ Ensures every requirement is covered (no gaps) | |
| ✅ Always runs in foreground | |

**Flow**:
```
Large spec → decompose → sub-specs + manifest
                              ↓
Full mode → spec select → plan → build → review → check
                              ↓
                    Sub-spec complete? → next sub-spec
                              ↓
                    All done? → master completion check → done
```

**When to use**: Before running full mode on a large spec (200+ lines). Decomposition keeps each cycle focused and prevents context overflow.

```bash
# Step 1: Decompose the large spec
node .ralph/run.js my-feature decompose

# Step 2: Review the sub-specs in specs/my-feature/
# Step 3: Run full mode — it will auto-cycle through sub-specs
node .ralph/run.js my-feature full
```

---

## Advanced Features

### Circuit Breaker

Ralph includes a circuit breaker that stops execution after consecutive failures to prevent runaway API costs.

```bash
# Default: 3 consecutive failures
MAX_CONSECUTIVE_FAILURES=5 node .ralph/run.js my-feature build
```

When triggered:
- Creates `.ralph/paused.md` with context
- Commits and pushes the pause state
- Exits with instructions for human intervention

To resume after fixing the issue:
```bash
rm .ralph/paused.md
node .ralph/run.js my-feature build
```

### Checkpointing

Ralph saves state to `.ralph/state.json` before each iteration:

```json
{
  "spec_name": "my-feature",
  "current_phase": "build",
  "current_iteration": 7,
  "last_successful_commit": "abc123",
  "session_start": "2026-02-05T10:00:00Z",
  "consecutive_failures": 0,
  "total_iterations": 42,
  "error_count": 1
}
```

If Ralph crashes, it will show the checkpoint on restart.

### Complexity Estimation

Plan mode tags every item with complexity estimates:

| Tag | Estimated Iterations | When Used |
|-----|---------------------|-----------|
| `[Simple]` | ~1 iteration | Single file, <50 lines, straightforward |
| `[Medium]` | ~2-3 iterations | Multiple files, moderate complexity |
| `[Complex]` | ~5+ iterations | Architectural changes, many files |
| `[RISK]` | +1-2 extra | Modifies shared code, needs extra testing |
| `[BLOCKED]` | — | Cannot proceed, needs human intervention |

### Dynamic Batching

Build mode intelligently batches work:

- **`[Simple]` items**: Up to 3 per turn (if independent)
- **`[Medium]`/`[Complex]`/`[RISK]` items**: 1 per turn

### Specialist Reviewers

Review mode routes items to specialist prompts based on content analysis:

| Detection Pattern | Specialist |
|------------------|------------|
| `bcrypt`, `jwt`, `auth`, `password` | Security |
| `SELECT`, `INSERT`, Prisma/TypeORM | Database |
| `fetch()`, `axios`, route handlers | API |
| Loops over large data, `cache`, `memoize` | Performance |
| JSX/TSX, CSS, `aria-*` | UX/Frontend |
| Everything else | QA |

---

## User Review Notes

After manually testing Ralph's work, add your feedback to `.ralph/user-review.md`:

```markdown
## 🐛 Bugs Found
- Login button doesn't work on mobile
- Form validation message is cut off

## ❌ Implementation Issues  
- The date picker should use UTC, not local time
- API response format doesn't match the spec

## 🎯 Focus Areas for Next Iteration
- Prioritize fixing the authentication flow
- Don't touch the dashboard yet
```

Then run **1-3 plan iterations** to have Ralph research and formalize your notes into the implementation plan. Your notes become "Phase 0: User Review Fixes" — the highest priority items.

| Priority | Source | Phase in Plan |
|----------|--------|---------------|
| 🥇 Highest | `user-review.md` (your notes) | Phase 0: User Review Fixes |
| 🥈 High | `review.md` (automated review) | Phase 0.5: Review Fixes |
| 🥉 Normal | Spec requirements | Phase 1+ |

---

## File Structure

```
.ralph/
├── .env                   # API keys (create from .env.example)
├── AGENTS.md              # Build commands, patterns, rules
├── implementation_plan.md # Task checklist (auto-managed)
├── user-review.md         # YOUR manual review notes (highest priority in plan mode)
├── review_checklist.md    # Review tracking (created by review mode)
├── review.md              # Review findings (created by review mode)
├── state.json             # Checkpoint state (auto-managed)
├── paused.md              # Created when circuit breaker trips
├── specs/
│   ├── sample.md          # Template for new specs
│   ├── my-feature.md      # Your feature specs
│   ├── active.md          # Auto-copied current spec
│   └── my-feature/        # Decomposed sub-specs (created by decompose mode)
│       ├── manifest.json  # Sub-spec progress tracking
│       ├── 01-data-model.md
│       └── 02-api-endpoints.md
├── prompts/
│   ├── plan.md            # Plan mode instructions
│   ├── build.md           # Build mode instructions
│   ├── review_setup.md    # Review mode setup (tags items by specialist)
│   ├── review.md          # General review fallback
│   ├── review_ux.md       # UX/Frontend specialist review
│   ├── review_db.md       # Database specialist review
│   ├── review_qa.md       # QA specialist review (default)
│   ├── review_security.md # Security specialist review
│   ├── review_perf.md     # Performance specialist review
│   ├── review_api.md      # API specialist review
│   ├── review_fix.md      # Review-fix mode instructions
│   ├── completion_check.md # Full mode completion check
│   ├── decompose.md       # Decompose mode - break spec into sub-specs
│   ├── spec_select.md     # Sub-spec selection for decomposed full mode
│   ├── master_completion_check.md # Final check across all sub-specs
│   └── requirements.md    # Template for gathering requirements
├── run.js                 # Entry point (Node.js)
├── setup.js               # Interactive setup wizard
├── loop.sh                # Iteration loop (runs in Docker)
├── Dockerfile             # Container definition
└── docker-compose.yml     # Docker compose config
```

---

## Branch Strategy

Ralph automatically manages branches:

| Spec Name | Branch Created |
|-----------|---------------|
| `my-feature` | `ralph/my-feature` |
| `auth-system` | `ralph/auth-system` |

- Creates branch if it doesn't exist
- Commits and pushes after each successful iteration
- You can switch specs by running with a different spec name

---

## Active Spec Pattern

When you run Ralph with a spec name:

1. **Copy**: `specs/my-feature.md` → `specs/active.md`
2. **Reference**: Prompts always read `@.ralph/specs/active.md`
3. **Branch**: Still named after original spec (`ralph/my-feature`)

This pattern lets prompts reference a consistent file path without variable substitution.

---

## Customization

### AGENTS.md

Your operational guide. Keep it brief—loaded every iteration.

| Section | Purpose |
|---------|---------|
| Build & Validate | Commands to build, test, lint |
| Critical Rules | Must-follow patterns and gotchas |
| Project Structure | Where key code lives |
| Key Patterns | Architecture conventions |

### Specs

Create detailed specifications in `.ralph/specs/`. Include:

- Problem statement and requirements
- Architecture decisions
- API contracts / data models
- Edge cases and error handling
- Testing strategy

See `.ralph/specs/sample.md` for a comprehensive template.

### Implementation Plan

A living checklist that Ralph updates:

- `- [ ]` Pending tasks
- `- [x]` Completed tasks
- `[Simple]`/`[Medium]`/`[Complex]`/`[RISK]` complexity tags
- Dependencies: what items depend on
- Enables: what items this unblocks
- `[BLOCKED]` items that need human intervention

---

## Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Docker | Latest | Docker Desktop on Windows/Mac |
| Node.js | 18+ | For run scripts |
| Git | 2.x+ | Branch management |
| API Key | — | AWS Bedrock or Anthropic |

---

## Tips

| Tip | Why |
|-----|-----|
| 🎯 **Start with plan mode** | Creates a solid task list before coding |
| 👀 **Review the plan** | Catch misunderstandings before build phase |
| 🔍 **Run review after build** | Catches bugs, bad patterns before merging |
| 🔄 **Use the full loop** | Plan → Build → Review → Review-Fix → Check |
| 🐛 **Use debug mode** | Test prompt changes without committing |
| 📝 **Keep AGENTS.md minimal** | Large files waste context tokens |
| 📖 **Write detailed specs** | More context = better implementation |
| 👁️ **Monitor iterations** | Catch issues before they compound |
| 🎯 **One spec at a time** | `active.md` enforces focus |
| ⚡ **Trust the circuit breaker** | Don't disable it—fix the root cause |

---

## Docker Image Updates

**Rebuild required** (`node .ralph/docker-build.js`):
- Update Claude Code CLI version
- Modify `Dockerfile` or `entrypoint.sh`

**No rebuild needed** (mounted/passed at runtime):
- All other `.ralph/` files (loop.sh, prompts, specs, AGENTS.md)
- `.env` credentials (passed via `--env-file`)

---

## Troubleshooting

### "Spec name is required"

Run with a spec name or use interactive mode:

```bash
node .ralph/run.js my-feature
# or
node .ralph/run.js  # interactive
```

### "Spec file not found"

Create the spec at `.ralph/specs/{spec-name}.md`

### Docker image not building

```bash
# Ensure Docker is running, then:
docker build -t ralph-wiggum -f .ralph/Dockerfile .
```

### "bad interpreter" error (Windows)

Shell scripts have Windows line endings. Fix with:

```bash
git add --renormalize .
git commit -m "Normalize line endings"
```

### Ralph keeps making the same mistakes

Update `.ralph/AGENTS.md` with a new "Critical Rule" to prevent the behavior.

### Circuit breaker keeps tripping

Check `.ralph/paused.md` for context. Common causes:
- Test infrastructure issues
- Missing dependencies
- Spec inconsistencies

### Ralph is stuck on a task

1. Check for `[BLOCKED]` items in `implementation_plan.md`
2. Review the "Discovered Issues" section
3. Add guidance to `AGENTS.md`
4. Consider decomposing complex tasks

---

## References

Based on the [Ralph Wiggum loop pattern](https://github.com/ghuntley/how-to-ralph-wiggum) by Geoffrey Huntley.

### Recommended Reading

| Resource | Description |
|----------|-------------|
| [How to Ralph](https://github.com/ghuntley/how-to-ralph-wiggum) | Original concept and prompts |
| [Ralph Wiggum Playbook](https://paddo.dev/blog/ralph-wiggum-playbook/) | Practical tips and workflows |
| [You're using Ralph wrong](https://www.youtube.com/watch?v=I7azCAgoUHc) | Common mistakes to avoid |
