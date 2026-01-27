# Ralph Wiggum 🍩

An AI agent framework that uses Claude Code to iteratively implement features from specifications. Ralph runs in a loop, picking up tasks from your implementation plan and building them out—one iteration at a time.

## Table of Contents

- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [NPM Integration](#npm-integration)
- [Modes](#modes)
  - [Plan Mode](#plan-mode)
  - [Build Mode](#build-mode)
- [File Structure](#file-structure)
- [Branch Strategy](#branch-strategy)
- [Active Spec Pattern](#active-spec-pattern)
- [Customization](#customization)
- [Requirements](#requirements)
- [Tips](#tips)
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

## Quick Start

### 1. Copy `.ralph` into your project

Copy the `.ralph` directory to the root of your repository.

### 2. Configure environment

```bash
cp .ralph/.env.example .ralph/.env
```

Edit `.ralph/.env` and add:
```env
AWS_BEARER_TOKEN_BEDROCK=...

GIT_USER=your-github-username
GIT_TOKEN=ghp_your_personal_access_token
```
You can generate the Bedrock token in [AWS Bedrock](https://us-west-2.console.aws.amazon.com/bedrock/home?region=us-west-2#/api-keys?tab=short-term)

The GIT_TOKEN can be created as a personal access token [here](https://github.com/settings/tokens). Ensure the token only has access to the repository you are adding ralph to and has the most limited permissions possible.

### 3. Customize AGENTS.md

Update `.ralph/AGENTS.md` with your project's build commands, test commands, and critical patterns.

### 4. Create your spec

Using `.ralph/prompts/requirements.md` as a sample, work with your AI agent to create an initial spec. Save it to `.ralph/specs/my-feature.md`. This is the most important step as the generated spec will be used by all the subsequent steps.

### 5. Build Ralph Image

```bash
node .ralph/docker-build.js
# or, if you have the npm script set up
npm run ralph:docker
```

### 6. Run Ralph Plan

```bash
# Plan mode - creates/refines implementation plan (5 iterations)
node .ralph/run.js my-feature plan
# or
npm run ralph -- my-feature plan
```

This process has Ralph iterate on the initial plan and spec you put together. It explores the codebase, does gap analysis and solidifies the plan you had started. After this process is complete, review the spec and implementation plan files.

**IMPORTANT**: Ensure you sign off on each line of these files. They will be used to create the implementation in the next step, so it's important that you know what you are signing off on.

### 7. Run Ralph Build

```bash
# Build mode - implements plan (default 10 iterations)
node .ralph/run.js my-feature build
# or
npm run ralph -- my-feature build
```

This is the implementation step. Ralph will iterate through your IMPLEMENTATION_PLAN.md one item at a time, implement it, add tests, update the docs, then commit the changes. Each iteration uses a fresh model context.

**IMPORTANT**: Look in on what Ralph is doing and ensure he is going down the right path. If he starts to stray, don't hesitate to interrupt the loop and modify the AGENTS.md file to steer him, or go back to plan mode and rebuild the plan.

---

## NPM Integration

Add these scripts to your `package.json` for easy access:

```json
{
  "scripts": {
    "ralph": "node .ralph/run.js",
    "ralph:docker": "node .ralph/docker-build.js"
  }
}
```

Then run:

```bash
# Build mode (10 iterations)
npm run ralph -- my-feature

# Build mode with custom iterations
npm run ralph -- my-feature build 20

# Plan mode (5 iterations)
npm run ralph -- my-feature plan

# Plan mode with custom iterations
npm run ralph -- my-feature plan 10
```

---

## Modes

### Plan Mode

```bash
node .ralph/run.js <spec-name> plan [iterations]
```

- Copies spec to `active.md` for prompts to reference
- Analyzes codebase against specifications
- Creates/updates `IMPLEMENTATION_PLAN.md` with prioritized tasks
- Identifies gaps, TODOs, and inconsistencies
- **Does NOT implement anything**—planning only

Use plan mode when starting a new feature or when you need to reassess priorities.

### Build Mode

```bash
node .ralph/run.js <spec-name> [build] [iterations]
```

- Copies spec to `active.md` for prompts to reference
- Picks the most important task from `IMPLEMENTATION_PLAN.md`
- Implements using Claude Code with parallel subagents
- Runs tests after each change
- Commits and pushes after each successful implementation
- Updates the implementation plan as tasks complete

Use build mode for actual development work.

---

## File Structure

```
.ralph/
├── .env                  # API keys and configuration (create from .env.example)
├── AGENTS.md             # Operational guide: build commands, patterns, rules
├── IMPLEMENTATION_PLAN.md # Current task checklist (auto-managed by Ralph)
├── specs/                # Feature specifications
│   ├── sample.md         # Template for new specs
│   └── active.md         # Auto-generated: copy of current spec being worked on
├── prompts/              # Mode-specific instructions
│   ├── plan.md           # Instructions for plan mode
│   ├── build.md          # Instructions for build mode
│   └── requirements.md   # Template for gathering requirements
├── run.js                # Main entry point (Node.js)
├── loop.sh               # Iteration loop script
├── Dockerfile            # Container definition
└── docker-compose.yml    # Docker compose config
```

---

## Branch Strategy

Ralph automatically manages branches based on your spec name:

- Spec `my-feature` → Branch `ralph/my-feature`
- Creates the branch if it doesn't exist
- Commits and pushes after each successful iteration

---

## Active Spec Pattern

When you run Ralph with a spec name:

1. The spec file (e.g., `.ralph/specs/my-feature.md`) is copied to `.ralph/specs/active.md`
2. Prompts reference `active.md` as the single source of truth
3. This allows prompts to always look at `@.ralph/specs/active.md` without needing variable substitution
4. The branch name is still derived from the original spec name

---

## Customization

### AGENTS.md

This file tells Ralph how to work in your codebase. Include:

- **Build commands**: How to compile/build the project
- **Test commands**: How to run tests (unit, integration)
- **Critical rules**: Patterns and conventions Ralph must follow
- **Project structure**: Where different code lives

Keep this file brief—it's loaded into every iteration's context.

### Specs

Create detailed specifications in `.ralph/specs/`. Each spec should include:

- Problem statement
- Requirements (functional and non-functional)
- Architecture/design decisions
- API contracts
- UI/UX details if applicable

See `.ralph/specs/sample.md` for a comprehensive template.

### Implementation Plan

The `IMPLEMENTATION_PLAN.md` is a living document that Ralph updates as it works:

- Checkbox items for each task
- Prioritized from top to bottom
- Ralph checks items off as it completes them
- Add notes or learnings that persist across iterations

---

## Requirements

- **Docker**: Required for running the containerized Claude Code environment
- **Node.js**: For the run script (`run.js`)
- **Git**: For branch management and commits
- **Bedrock API Key**: For Claude Code access

---

## Tips

1. **Start with plan mode**: Let Ralph analyze and create a solid implementation plan before building
2. **Review the plan**: Check `IMPLEMENTATION_PLAN.md` between modes to ensure priorities are correct
3. **Keep AGENTS.md minimal**: Only operational information—no status updates or progress notes
4. **Write detailed specs**: The more context Ralph has, the better the implementation
5. **Monitor iterations**: Watch the output to catch issues early
6. **One spec at a time**: The `active.md` pattern ensures focus on a single feature

---

## Troubleshooting

### "Spec name is required"
Provide the spec name as the first argument: `npm run ralph -- my-feature`

### "Spec file not found"
Create the spec at `.ralph/specs/{spec-name}.md`

### Docker image not building
Ensure Docker is running and you have permissions. Try: `docker build -t ralph-wiggum -f .ralph/Dockerfile .`

### "bad interpreter" or script errors in Docker (Windows)
If you see errors like `/bin/bash^M: bad interpreter`, the shell scripts have Windows (CRLF) line endings. Fix with:
```bash
# Re-normalize line endings after cloning
git add --renormalize .
git commit -m "Normalize line endings"
```
Or manually convert the files:
```bash
# Using Git Bash or WSL
sed -i 's/\r$//' .ralph/*.sh
```

---

## References

The initial `build.md` and `plan.md` prompts as well as the `loop.sh` come from this repo: https://github.com/ghuntley/how-to-ralph-wiggum

### Recommended reading
- [How to Ralph](https://github.com/ghuntley/how-to-ralph-wiggum)
- [Ralph Wiggum Playbook](https://paddo.dev/blog/ralph-wiggum-playbook/)
- [You're using Ralph Wiggum loops wrong](https://www.youtube.com/watch?v=I7azCAgoUHc)
