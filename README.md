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
│  ├── IMPLEMENTATION_PLAN.md  ← Task checklist (what's left)    │
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
│  6. Loops until done                                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Copy `.ralph` into your project

Copy the `.ralph` directory to the root of your repository.

### 2. Configure environment

Add to .gitignore

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

### 3. Customize AGENTS.md

Update `.ralph/AGENTS.md` with your project's build commands, test commands, and critical patterns.

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
node .ralph/run.js my-feature plan   # Plan first
node .ralph/run.js my-feature build  # Then build
```

> ⚠️ **After plan mode**: Review `.ralph/specs/active.md` and `IMPLEMENTATION_PLAN.md`. Ensure you agree with every line—these drive the build phase.

> ⚠️ **During build mode**: Monitor Ralph's progress. If he strays, interrupt and update `AGENTS.md` to steer him, re-run plan mode, or scrap the plan and spec and start over.

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
  1. plan  - Analyze codebase and create implementation plan
  2. build - Implement tasks from the plan

Select mode [1/2 or plan/build] (default: build): plan
Number of iterations (default: 5): 
```

### Command Line

```bash
node .ralph/run.js <spec-name> [mode] [iterations] [--verbose]
node .ralph/run.js [--plan|--build] [--verbose]  # Interactive with mode pre-selected
```

| Argument | Description | Default |
|----------|-------------|---------|
| `spec-name` | Name of spec file (without `.md`) | Required (or interactive) |
| `mode` | `plan` or `build` | `build` |
| `iterations` | Number of loop iterations | 5 (plan) / 10 (build) |
| `--verbose` / `-v` | Show full Claude output (JSON stream) | Off (shows summary only) |
| `--plan` | Pre-select plan mode in interactive | — |
| `--build` | Pre-select build mode in interactive | — |
| `--background` / `-b` | Run in background (Ralph clones repo) | Off |

Examples:

```bash
node .ralph/run.js my-feature              # Build mode, 10 iterations, quiet
node .ralph/run.js my-feature plan         # Plan mode, 5 iterations, quiet
node .ralph/run.js my-feature build 20     # Build mode, 20 iterations, quiet
node .ralph/run.js my-feature --verbose    # Build mode with full output
node .ralph/run.js my-feature plan -v      # Plan mode with full output
```

### NPM Scripts

Add to your `package.json`:

```json
{
  "scripts": {
    "ralph": "node .ralph/run.js",
    "ralph:plan": "node .ralph/run.js --plan",
    "ralph:build": "node .ralph/run.js --build",
    "ralph:docker": "node .ralph/docker-build.js"
  }
}
```

Then run:

```bash
npm run ralph                              # Interactive mode
npm run ralph:plan                         # Interactive with plan mode pre-selected
npm run ralph:build                        # Interactive with build mode pre-selected
npm run ralph -- my-feature                # Build mode (quiet)
npm run ralph -- my-feature plan           # Plan mode (quiet)
npm run ralph -- my-feature build 20       # Build with 20 iterations
npm run ralph -- my-feature --verbose      # Build with full output
npm run ralph -- my-feature plan -v        # Plan with full output
```

---

## Modes

### Plan Mode

```bash
node .ralph/run.js <spec-name> plan [iterations]
```

| What it does | What it doesn't do |
|--------------|-------------------|
| ✅ Analyzes codebase against spec | ❌ Write any code |
| ✅ Creates/updates `IMPLEMENTATION_PLAN.md` | ❌ Run tests |
| ✅ Identifies gaps and inconsistencies | ❌ Make commits |
| ✅ Prioritizes tasks | |

**When to use**: Starting a new feature, or reassessing priorities mid-project.

### Build Mode

```bash
node .ralph/run.js <spec-name> [build] [iterations]
```

| What it does |
|--------------|
| ✅ Picks highest-priority incomplete task |
| ✅ Implements using Claude Code + subagents |
| ✅ Runs tests after each change |
| ✅ Commits and pushes after success |
| ✅ Updates `IMPLEMENTATION_PLAN.md` |

**When to use**: After you've reviewed and approved the plan.

---

## File Structure

```
.ralph/
├── .env                   # API keys (create from .env.example)
├── AGENTS.md              # Build commands, patterns, rules
├── IMPLEMENTATION_PLAN.md # Task checklist (auto-managed)
├── specs/
│   ├── sample.md          # Template for new specs
│   ├── my-feature.md      # Your feature specs
│   └── active.md          # Auto-copied current spec
├── prompts/
│   ├── plan.md            # Plan mode instructions
│   ├── build.md           # Build mode instructions
│   └── requirements.md    # Template for gathering requirements
├── run.js                 # Entry point (Node.js)
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
- Prioritized top to bottom
- Add notes that persist across iterations

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
| 📝 **Keep AGENTS.md minimal** | Large files waste context tokens |
| 📖 **Write detailed specs** | More context = better implementation |
| 👁️ **Monitor iterations** | Catch issues before they compound |
| 🎯 **One spec at a time** | `active.md` enforces focus |

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

Or manually:

```bash
sed -i 's/\r$//' .ralph/*.sh
```

### Ralph keeps making the same mistakes

Update `.ralph/AGENTS.md` with a new "Critical Rule" to prevent the behavior.

---

## References

Based on the [Ralph Wiggum loop pattern](https://github.com/ghuntley/how-to-ralph-wiggum) by Geoffrey Huntley.

### Recommended Reading

| Resource | Description |
|----------|-------------|
| [How to Ralph](https://github.com/ghuntley/how-to-ralph-wiggum) | Original concept and prompts |
| [Ralph Wiggum Playbook](https://paddo.dev/blog/ralph-wiggum-playbook/) | Practical tips and workflows |
| [You're using Ralph wrong](https://www.youtube.com/watch?v=I7azCAgoUHc) | Common mistakes to avoid |
