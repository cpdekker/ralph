---
name: setup
description: Initialize Ralph in the current repository — checks Docker, builds image, configures environment. Run this before using other Ralph skills.
---

# Ralph Setup

Run `ralph_setup` with the current working directory to check what's needed.

## Steps

1. Call `ralph_setup` tool with `workdir` set to the current repo root
2. If `ready: true` — tell the user Ralph is ready and suggest trying `/ralph:full` or `/ralph:research`
3. If `missing` contains items, walk through each:
   - `docker_not_installed` — Tell user to install Docker Desktop
   - `docker_not_running` — Tell user to start Docker Desktop
   - `ralph_not_initialized` — Run `ralph init` via Bash tool in the repo, or create `.ralph/` directory with required files
   - `env_file_missing` — Ask user for their API credentials and create `.ralph/.env` file
   - `image_not_built` — Call `ralph_setup` again with `autoBuild: true` to build the image

After resolving all issues, call `ralph_setup` again to verify everything is ready.

## Important
- The `.ralph/.env` file contains secrets — never commit it
- Docker image build can take a few minutes on first run
- Once setup is complete, it persists — no need to re-run unless Docker image is deleted
