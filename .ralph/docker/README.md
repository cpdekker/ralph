# Ralph Wiggum - Docker Isolation Guide

Ralph runs inside a Docker container for isolation. The container includes Node.js, Git, and the Claude Code CLI.

## Building the Image

```bash
# Using the build script (recommended)
node .ralph/docker/build.js

# Or manually
docker build -t ralph-wiggum -f .ralph/docker/Dockerfile .
```

## How It Works

1. **Build** the Docker image (includes Claude Code CLI)
2. **Load** credentials from `.ralph/.env` via `--env-file`
3. **Mount** the repo at `/workspace` (foreground mode) or **clone** it (background mode)
4. **Run** the loop script inside the container

## Manual Docker Commands

If you prefer manual control:

```bash
# Build once
docker build -t ralph-wiggum -f .ralph/docker/Dockerfile .

# Run interactive shell
docker run -it --rm --env-file .ralph/.env -v "$(pwd):/workspace" -w /workspace ralph-wiggum bash

# Run loop directly
docker run -it --rm --env-file .ralph/.env -v "$(pwd):/workspace" -w /workspace ralph-wiggum bash ./.ralph/scripts/loop.sh my-feature plan 2
```

## API Provider Configuration

The container receives API credentials via `--env-file .ralph/.env`. Configure your provider in `.ralph/.env` — see `.ralph/.env.example` for options:

- **Anthropic API**: Set `ANTHROPIC_API_KEY`
- **AWS Bedrock**: Set `CLAUDE_CODE_USE_BEDROCK=1` plus AWS credentials
- **Google Vertex AI**: Set `CLAUDE_CODE_USE_VERTEX=1` plus GCP project details

## Safety Tips

1. **Start with plan mode** — review what Claude intends before building
2. **Use low iteration counts** — start with 1-2, review changes
3. **Ralph works on a branch** (`ralph/<spec-name>`) — your main branch is safe
4. **Volume mount is live** in foreground mode — changes persist to your real repo

## Troubleshooting

**Auth errors:** Verify `.ralph/.env` has correct API credentials for your provider. Run `claude -p <<< "test"` inside the container to test authentication.

**Image not found:** Rebuild with `node .ralph/docker/build.js`

**Permission denied on scripts:** Run `chmod +x .ralph/scripts/*.sh .ralph/docker/entrypoint.sh` inside the container.

## Cleanup

```bash
docker rmi ralph-wiggum
docker system prune
```
