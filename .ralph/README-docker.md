# Ralph Wiggum - Docker Isolation Guide

Run the autonomous Claude Code loop in an isolated Docker environment.

## Quick Start

Since you already have `.ralph/.env` configured:

```powershell
# From repo root - runs interactive shell
.\.ralph\run.ps1

# Inside container, run the loop
./.ralph/loop.sh plan 2
```

Or run directly:

```powershell
.\.ralph\run.ps1 plan 2      # Plan mode, 2 iterations
.\.ralph\run.ps1 5           # Build mode, 5 iterations
```

## What the Scripts Do

1. **Build** the Docker image (if not already built)
2. **Load** credentials from `.ralph/.env`
3. **Mount** the repo at `/workspace`
4. **Run** the container interactively or with the loop

## Manual Docker Commands

If you prefer manual control:

```powershell
# Build once
docker build -t ralph-wiggum -f .ralph/Dockerfile .

# Run interactive
docker run -it --rm --env-file .ralph/.env -v "${PWD}:/workspace" -w /workspace ralph-wiggum bash

# Run loop directly
docker run -it --rm --env-file .ralph/.env -v "${PWD}:/workspace" -w /workspace ralph-wiggum ./.ralph/loop.sh plan 2
```

## Loop Modes

| Command | Description |
|---------|-------------|
| `./.ralph/loop.sh plan 2` | Research/planning only, 2 iterations |
| `./.ralph/loop.sh 5` | Build mode, 5 iterations |
| `./.ralph/loop.sh` | Build mode, 10 iterations (default) |

## Safety Tips

1. **Start with plan mode** - review what Claude intends before building
2. **Use low iteration counts** - start with 1-2, review changes
3. **You're on a branch** (`ralph-trial`) - good for isolation
4. **Volume mount is live** - changes persist to your real repo

## Git Push

The loop pushes after each iteration. Configure git inside the container:

```bash
# Inside container - configure for HTTPS
git config --global credential.helper store
echo "https://username:token@github.com" > ~/.git-credentials
```

Or mount SSH keys:

```powershell
docker run -it --rm `
    --env-file .ralph/.env `
    -v "${PWD}:/workspace" `
    -v "$env:USERPROFILE\.ssh:/home/ralph/.ssh:ro" `
    -w /workspace `
    ralph-wiggum bash
```

## Troubleshooting

**Auth errors:** Verify `.ralph/.env` has correct values:
```
CLAUDE_CODE_USE_BEDROCK=1
AWS_BEARER_TOKEN_BEDROCK=your-actual-key
```

**Image not found:** Rebuild with `docker build -t ralph-wiggum -f .ralph/Dockerfile .`

**Permission denied on scripts:** Run `chmod +x .ralph/*.sh` inside container

## Cleanup

```powershell
docker rmi ralph-wiggum
docker system prune
```
