# Ralph Wiggum - Docker Isolation Guide

Ralph runs inside a Docker container based on the [Claude Code dev container](https://code.claude.com/docs/en/devcontainer). The container includes Node.js, Git, Claude Code CLI, and a firewall for network isolation.

## Building the Image

```bash
# Using the build script (recommended)
node .ralph/docker/build.js

# Or manually
docker build -t ralph-wiggum -f .devcontainer/Dockerfile .
```

## How It Works

1. **Build** the Docker image (based on Claude Code dev container with firewall)
2. **Load** credentials from `.ralph/.env` via `--env-file`
3. **Mount** the repo at `/workspace` (foreground mode) or **clone** it (background mode)
4. **Run** the loop script inside the container

## Manual Docker Commands

If you prefer manual control:

```bash
# Build once
docker build -t ralph-wiggum -f .devcontainer/Dockerfile .

# Run interactive shell
docker run -it --rm --cap-add=NET_ADMIN --cap-add=NET_RAW --env-file .ralph/.env -v "$(pwd):/workspace" -w /workspace ralph-wiggum bash

# Run loop directly
docker run -it --rm --cap-add=NET_ADMIN --cap-add=NET_RAW --env-file .ralph/.env -v "$(pwd):/workspace" -w /workspace ralph-wiggum bash ./.ralph/scripts/loop.sh my-feature plan 2
```

## VS Code Dev Container

You can also use the `.devcontainer/` configuration directly with VS Code:

1. Install VS Code and the Remote - Containers extension
2. Open the project in VS Code
3. Click "Reopen in Container" when prompted

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
5. **Firewall** restricts outbound network to only required services (GitHub, npm, Anthropic API)

## Troubleshooting

**Auth errors:** Verify `.ralph/.env` has correct API credentials for your provider. Run `claude -p <<< "test"` inside the container to test authentication.

**Image not found:** Rebuild with `node .ralph/docker/build.js`

**Firewall errors:** Ensure `--cap-add=NET_ADMIN --cap-add=NET_RAW` flags are present in docker run commands.

## Cleanup

```bash
docker rmi ralph-wiggum
docker system prune
```
