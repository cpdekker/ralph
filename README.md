# Ralph Wiggum

An AI agent that uses Claude Code to iteratively implement features from specifications. Ralph runs in a loop, picking up tasks from your implementation plan and building them out—one iteration at a time.

**Why use Ralph?** Instead of manually prompting an AI for each change, Ralph autonomously works through a prioritized task list, running tests, committing code, and pushing changes. You define *what* to build; Ralph figures out *how* and executes it.

## Table of Contents

- [How It Works](#how-it-works)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Modes](#modes)
  - [Plan Mode](#plan-mode)
  - [Build Mode](#build-mode)
  - [Review Mode](#review-mode)
  - [Review-Fix Mode](#review-fix-mode)
  - [Debug Mode](#debug-mode)
  - [Full Mode](#full-mode)
  - [Decompose Mode](#decompose-mode)
  - [Spec Mode](#spec-mode)
- [Advanced Features](#advanced-features)
  - [Circuit Breaker](#circuit-breaker)
  - [Checkpointing](#checkpointing)
  - [Complexity Estimation](#complexity-estimation)
  - [Dynamic Batching](#dynamic-batching)
  - [Specialist Reviewers](#specialist-reviewers)
- [Customizing Prompts](#customizing-prompts)
- [Project Files](#project-files)
- [Branch Strategy](#branch-strategy)
- [Requirements](#requirements)
- [API Providers](#api-providers)
- [Updating](#updating)
- [Tips](#tips)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Security](#security)
- [References](#references)

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Repository                          │
├─────────────────────────────────────────────────────────────────┤
│  .ralph/                                                        │
│  ├── specs/           ← Feature specifications (what to build) │
│  │   └── my-feature.md   ← Your spec files                     │
│  ├── AGENTS.md        ← Operational guide (how to build/test)  │
│  ├── implementation_plan.md  ← Task checklist (what's left)    │
│  └── prompts/         ← Optional local prompt overrides        │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────┴──────────────────────────────────┐
│                     Ralph CLI (Docker Container)                │
│  1. Reads spec + implementation plan + AGENTS.md                │
│  2. Picks highest-priority incomplete task                      │
│  3. Implements using Claude Code + subagents                    │
│  4. Runs tests, updates plan, commits & pushes                  │
│  5. Loops until done (with circuit breaker protection)          │
└─────────────────────────────────────────────────────────────────┘
```

Ralph uses the "Ralph Wiggum Loop" pattern — each iteration spawns a fresh Claude Code context. State persists in files and git, not in the LLM's memory. This avoids "context pollution" where accumulated conversation history degrades output quality.

---

## Installation

### From npm

```bash
npm install -g ralph-cli
```

### From source

```bash
git clone https://github.com/cpdekker/ralph.git
cd ralph
npm install
npm install -g .
```

Verify the installation:

```bash
ralph --version
```

---

## Quick Start

### 1. Initialize Ralph in your repo

```bash
cd your-project
ralph init
```

The interactive setup wizard will guide you through:
- Checking prerequisites (Docker, Node.js, Git)
- Creating `.ralph/.env` with your API credentials
- Adding `.ralph/.env` to `.gitignore`
- Generating `AGENTS.md` using Claude (analyzes your codebase)
- Building the Docker image

### 2. Customize AGENTS.md

Review `.ralph/AGENTS.md` and refine it with your project's build commands, test commands, and critical patterns. This file is loaded into every iteration's context.

### 3. Create your spec

**Option A — Interactive spec mode (recommended)**:
```bash
ralph spec my-feature
```
This runs a wizard to gather your requirements, then uses AI to research, draft, refine, and review the spec.

**Option B — Manual**: Copy the sample spec and edit it.
```bash
cp .ralph/specs/sample.md .ralph/specs/my-feature.md
```

### 4. Run Ralph

```bash
ralph plan my-feature       # Create implementation plan
ralph build my-feature      # Implement tasks from the plan
ralph review my-feature     # Review the implementation
ralph full my-feature       # Or run the full autonomous cycle
```

> **After plan mode**: Review `.ralph/IMPLEMENTATION_PLAN.md`. Ensure you agree with every line—it drives the build phase.

> **During build mode**: Monitor Ralph's progress. If he strays, interrupt and update `AGENTS.md` to steer him.

> **After build mode**: Run review mode to catch bugs, bad patterns, and incomplete implementations before merging.

---

## Commands

```bash
ralph init                        # Initialize Ralph in the current repo
ralph plan <spec> [options]       # Create implementation plan
ralph build <spec> [options]      # Implement tasks from the plan
ralph review <spec> [options]     # Review implementation for issues
ralph review-fix <spec> [options] # Fix issues from review
ralph debug <spec>                # Single iteration, verbose, no commits
ralph full <spec> [options]       # Full cycle: plan → build → review → check
ralph decompose <spec>            # Break large spec into sub-specs
ralph spec <name> [options]       # Create spec interactively
ralph                             # Interactive mode
ralph update                      # Update Ralph to the latest version
ralph --version                   # Show version
```

### Common Options

| Option | Description |
|--------|-------------|
| `-n, --iterations <number>` | Number of iterations (or cycles for full mode) |
| `-v, --verbose` | Show full Claude output |
| `-b, --background` | Run in background (Ralph clones repo) |
| `-f, --foreground` | Force foreground mode |

### Examples

```bash
ralph plan my-feature              # Plan mode, 5 iterations
ralph build my-feature -n 20      # Build mode, 20 iterations
ralph build my-feature -v         # Build mode with verbose output
ralph full my-feature             # Full cycle (background by default)
ralph full my-feature -f          # Full cycle, foreground
ralph                             # Interactive: pick spec and mode
```

---

## Modes

### Plan Mode

```bash
ralph plan <spec> [-n iterations]
```

| What it does | What it doesn't do |
|--------------|--------------------|
| Analyzes codebase against spec | Write any code |
| Creates/updates `implementation_plan.md` | Run tests |
| Adds complexity tags (`[Simple]`, `[Medium]`, `[Complex]`) | Make commits |
| Tracks dependencies between tasks | |
| Identifies high-risk items | |

**When to use**: Starting a new feature, or reassessing priorities mid-project.

### Build Mode

```bash
ralph build <spec> [-n iterations]
```

| What it does |
|--------------|
| Picks highest-priority incomplete task |
| Batches simple tasks (up to 3 `[Simple]` items per turn) |
| Implements using Claude Code + subagents |
| Runs tests after each change |
| Reverts and documents if stuck (3-strikes rule) |
| Commits and pushes after success |
| Updates `implementation_plan.md` |

**When to use**: After you've reviewed and approved the plan.

### Review Mode

```bash
ralph review <spec> [-n iterations]
```

| What it does | What it outputs |
|--------------|-----------------|
| Creates `review_checklist.md` (setup phase) | `review_checklist.md` - tracking document |
| Reviews up to 5 items per iteration | `review.md` - comprehensive findings |
| Compares implementation against spec | |
| Detects bugs, bad patterns, security issues | |
| Routes to specialist reviewers based on content | |

**Specialist Reviewers**: Items are automatically routed to the right expert:

| Specialist | Tag | Focus Areas |
|------------|-----|-------------|
| Security | `[SEC]` | Authentication, authorization, input validation, secrets |
| DB Expert | `[DB]` | SQL queries, migrations, data models, query performance |
| API Expert | `[API]` | REST endpoints, API contracts, error responses |
| Performance | `[PERF]` | Algorithm complexity, caching, memory usage |
| UX Expert | `[UX]` | React/Vue components, CSS, accessibility |
| QA Expert | `[QA]` | Business logic, error handling, testing, general quality |

**When to use**: After build mode, before merging.

### Review-Fix Mode

```bash
ralph review-fix <spec> [-n iterations]
```

| What it does |
|--------------|
| Fixes BLOCKING and NEEDS ATTENTION issues from review |
| Updates `review.md` to mark issues as resolved |
| Adds regression tests for fixes |
| Commits with `fix:` prefix |

**When to use**: After review mode identifies issues.

### Debug Mode

```bash
ralph debug <spec>
```

| What it does | What it doesn't do |
|--------------|--------------------|
| Runs exactly 1 iteration | Commit changes |
| Forces verbose output | Push to remote |
| Shows full Claude reasoning | Run multiple iterations |

**When to use**: Testing prompt changes, debugging Ralph behavior, or understanding why something failed.

### Full Mode

```bash
ralph full <spec> [-n max-cycles]
```

| What it does |
|--------------|
| Runs complete cycles: Plan → Build → Review → Review-Fix → Check |
| Automatically checks if implementation is complete after each cycle |
| Reports confidence scores (0.0 - 1.0) |
| Exits early when spec is fully implemented |
| Protected by circuit breaker |
| Runs in background by default |
| Supports decomposed specs — auto-cycles through sub-specs |

**Default iterations per cycle**:
| Phase | Default | Environment Variable |
|-------|---------|---------------------|
| Plan | 5 | `FULL_PLAN_ITERS` |
| Build | 10 | `FULL_BUILD_ITERS` |
| Review | 15 | `FULL_REVIEW_ITERS` |
| Review-Fix | 5 | `FULL_REVIEWFIX_ITERS` |

**With decomposed specs**: If a manifest exists (`specs/{name}/manifest.json`), full mode automatically:
1. Runs **spec select** to pick the next sub-spec
2. Completes one full cycle for that sub-spec
3. Marks the sub-spec complete and selects the next one
4. After all sub-specs complete, runs a **master completion check**

**When to use**: When you want fully autonomous implementation with minimal supervision.

### Decompose Mode

```bash
ralph decompose <spec>
```

| What it does | What it creates |
|--------------|-----------------|
| Analyzes master spec for natural boundaries | `specs/{name}/` directory |
| Identifies dependencies between components | Numbered sub-spec files (`01-data-model.md`, etc.) |
| Sizes each sub-spec for ~1 full mode cycle | `manifest.json` tracking progress |
| Ensures every requirement is covered (no gaps) | |

**When to use**: Before running full mode on a large spec (200+ lines).

```bash
ralph decompose my-feature      # Break into sub-specs
ralph full my-feature           # Auto-cycles through them
```

### Spec Mode

```bash
ralph spec <name> [-n iterations]
```

| What it does | What it creates |
|--------------|-----------------|
| Interactive wizard gathers requirements | `.ralph/spec_seed.md` — your input |
| AI researches codebase and best practices | `.ralph/spec_research.md` — findings |
| Generates full spec from template | `specs/{name}.md` — the spec |
| Creates structured questions for clarification | `.ralph/spec_questions.md` — Q&A |
| Refines spec with your answers and feedback | |
| Reviews spec quality against rubric | `.ralph/spec_review.md` — assessment |
| Signs off when ready | |

**Flow**: Wizard (host) → Research → Draft → Refine (1-3x) → Review → Fix → Sign-off

**File-based feedback**: Between refine iterations, edit these files to provide input:
- `.ralph/spec_questions.md` — Fill in `A:` lines to answer questions
- `.ralph/user-review.md` — Add freeform feedback, corrections, or focus areas

**When to use**: When starting a new feature and you want AI-assisted spec creation with quality checks.

---

## Advanced Features

### Circuit Breaker

Ralph stops execution after consecutive failures to prevent runaway API costs.

```bash
# Default: 3 consecutive failures
MAX_CONSECUTIVE_FAILURES=5 ralph build my-feature
```

When triggered:
- Creates `.ralph/paused.md` with context
- Commits and pushes the pause state
- Exits with instructions for human intervention

To resume after fixing the issue:
```bash
rm .ralph/paused.md
ralph build my-feature
```

### Checkpointing

Ralph saves state to `.ralph/state.json` before each iteration. If Ralph crashes, it will show the checkpoint on restart.

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
## Bugs Found
- Login button doesn't work on mobile
- Form validation message is cut off

## Implementation Issues
- The date picker should use UTC, not local time
- API response format doesn't match the spec

## Focus Areas for Next Iteration
- Prioritize fixing the authentication flow
- Don't touch the dashboard yet
```

Then run plan mode to have Ralph formalize your notes into the implementation plan. Your notes become "Phase 0: User Review Fixes" — the highest priority items.

| Priority | Source | Phase in Plan |
|----------|--------|---------------|
| Highest | `user-review.md` (your notes) | Phase 0: User Review Fixes |
| High | `review.md` (automated review) | Phase 0.5: Review Fixes |
| Normal | Spec requirements | Phase 1+ |

---

## Customizing Prompts

Ralph ships with built-in prompts for each mode. You can **override any prompt** by placing a file with the same name in `.ralph/prompts/`.

### How It Works

When Ralph looks for a prompt file, it checks:
1. `.ralph/prompts/<name>.md` in your repo (local override)
2. The built-in prompt bundled with the CLI (default)

The local file wins if it exists.

### Example: Customize the Build Prompt

```bash
mkdir -p .ralph/prompts

# Copy the built-in prompt as a starting point
cp $(npm root -g)/ralph-cli/lib/prompts/build.md .ralph/prompts/build.md

# Edit to your needs
$EDITOR .ralph/prompts/build.md
```

### Available Prompts

**Main Modes:**
- `plan.md` — How Ralph creates the implementation plan
- `build.md` — How Ralph implements code and runs tests
- `decompose.md` — How Ralph breaks large specs into sub-specs
- `completion_check.md` — How Ralph decides if a spec is fully implemented
- `master_completion_check.md` — Completion check for decomposed specs
- `spec_select.md` — How Ralph picks the next sub-spec

**Review Specialists:**
- `review/setup.md` — Creates the review checklist
- `review/general.md` — General review (fallback)
- `review/security.md`, `review/ux.md`, `review/db.md`, `review/api.md`, `review/perf.md`, `review/qa.md`
- `review/fix.md` — Fixing review issues

**Spec Creation:**
- `spec/research.md`, `spec/draft.md`, `spec/refine.md`, `spec/review.md`, `spec/review_fix.md`, `spec/signoff.md`

### Tips

- **AGENTS.md is the most impactful file to customize.** It's loaded into every iteration.
- **Start small.** Override one prompt, test it, then expand.
- **Keep overrides minimal.** Only change what you need — makes upgrading easier.
- **Commit your overrides.** They're project-specific configuration.

---

## Project Files

After running `ralph init`, your repo will contain:

```
.ralph/
├── .env                   # API keys (git-ignored)
├── .env.example           # Template for .env
├── AGENTS.md              # Build commands, patterns, rules — customize this
├── IMPLEMENTATION_PLAN.md # Task checklist (auto-managed)
├── user-review.md         # Your manual review notes
├── README.md              # Usage guide
├── specs/
│   ├── sample.md          # Template for new specs
│   └── my-feature.md      # Your feature specs
└── prompts/               # Optional local prompt overrides
```

Files generated during execution (git-ignored):
- `state.json` — Checkpoint state
- `paused.md` — Created when circuit breaker trips
- `review.md`, `review_checklist.md` — Review findings
- `spec_seed.md`, `spec_questions.md`, `spec_review.md` — Spec mode working files

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

## Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Docker | Latest | Docker Desktop on Windows/Mac |
| Node.js | 18+ | For the CLI and Docker container |
| Git | 2.x+ | Branch management |
| API Key | — | Any supported Claude API provider (see below) |

---

## API Providers

Ralph uses [Claude Code](https://docs.anthropic.com/en/docs/claude-code) under the hood. Configure **one** of the following in `.ralph/.env`:

### Anthropic API (recommended for getting started)

```env
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### AWS Bedrock

```env
CLAUDE_CODE_USE_BEDROCK=1
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-west-2
```

Or with bearer token credentials:

```env
CLAUDE_CODE_USE_BEDROCK=1
AWS_BEARER_TOKEN_BEDROCK=your-bearer-token
AWS_REGION=us-west-2
```

### Google Cloud Vertex AI

```env
CLAUDE_CODE_USE_VERTEX=1
ANTHROPIC_VERTEX_PROJECT_ID=your-gcp-project-id
CLOUD_ML_REGION=us-east5
```

---

## Updating

### If installed via npm

```bash
ralph update
```

Or manually:
```bash
npm install -g ralph-cli@latest
```

### If installed from source

```bash
ralph update
```

Or manually:
```bash
cd path/to/ralph
git pull origin main
npm install
npm install -g .
```

`ralph update` auto-detects your install type and handles both paths. Your `.ralph/` project directories are not affected by updates — only the CLI and its built-in prompts change. Local prompt overrides continue to take precedence.

### Releases

New versions are published to npm when a [GitHub Release](https://github.com/cpdekker/ralph/releases) is created. Version tags follow semver (e.g., `v0.2.0`).

---

## Tips

| Tip | Why |
|-----|-----|
| **Start with plan mode** | Creates a solid task list before coding |
| **Review the plan** | Catch misunderstandings before build phase |
| **Run review after build** | Catches bugs, bad patterns before merging |
| **Use the full loop** | Plan → Build → Review → Review-Fix → Check |
| **Use debug mode** | Test prompt changes without committing |
| **Keep AGENTS.md minimal** | Large files waste context tokens |
| **Write detailed specs** | More context = better implementation |
| **Monitor iterations** | Catch issues before they compound |
| **Trust the circuit breaker** | Don't disable it—fix the root cause |

---

## Docker Image Updates

**Rebuild required** (automatic on first run):
- Update Claude Code CLI version
- Modify Dockerfile or entrypoint

**No rebuild needed** (mounted/passed at runtime):
- All prompts, scripts, specs, AGENTS.md
- `.env` credentials (passed via `--env-file`)

---

## Troubleshooting

### "Error: .ralph directory not found"

Run `ralph init` in the root of your repository.

### "Spec file not found"

Create the spec at `.ralph/specs/{spec-name}.md`, or use `ralph spec <name>` to create one interactively.

### Docker image not building

Ensure Docker is running, then try `ralph init` again.

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

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## Security

If you discover a security vulnerability, please see [SECURITY.md](SECURITY.md) for responsible disclosure instructions. **Do not open a public issue for security vulnerabilities.**

---

## References

Based on the [Ralph Wiggum loop pattern](https://github.com/ghuntley/how-to-ralph-wiggum) by Geoffrey Huntley.

| Resource | Description |
|----------|-------------|
| [How to Ralph](https://github.com/ghuntley/how-to-ralph-wiggum) | Original concept and prompts |
| [Ralph Wiggum Playbook](https://paddo.dev/blog/ralph-wiggum-playbook/) | Practical tips and workflows |
| [You're using Ralph wrong](https://www.youtube.com/watch?v=I7azCAgoUHc) | Common mistakes to avoid |

---

## License

[MIT](LICENSE) - Copyright 2026 Chris Dekker
