# Ralph Claude Code Plugin — Design Spec

## Overview

Make Ralph available as a Claude Code plugin, enabling users to spin up Docker containers for long-running autonomous tasks (build, research, spec, review, full cycle) directly from within a Claude Code session. The plugin uses a hybrid architecture: skills as guided entry points, an MCP server as the orchestration engine.

## Decisions

- **Hybrid model**: Skills for UX, MCP tools for container orchestration
- **Managed lifecycle with steer**: Containers report back on completion; users can redirect via mailbox mid-run
- **Curated skill set**: full, build, research, review, spec, setup — other modes accessible via MCP tools directly
- **Lives in Ralph repo**: Self-contained `plugin/` directory alongside `lib/` and `.ralph/`
- **Node.js MCP server**: Reuses Ralph's existing `lib/utils/` (docker.js, container.js, git.js)
- **MCP server as orchestrator**: High-level composite tools, not just primitives — skills delegate to single tool calls
- **Guided setup skill**: `/ralph:setup` for first-run; other skills do pre-flight checks and point to setup if needed
- **Background-only containers**: `ralph_start` always launches detached — Ralph is always an async background job from Claude Code's perspective

## MCP Server Registration

`.mcp.json` at the plugin root. Note: the exact variable interpolation syntax (`${CLAUDE_PLUGIN_ROOT}`) needs to be verified against Claude Code's plugin API during implementation. If not supported, the MCP server will resolve paths relative to `__dirname` at runtime instead.

```json
{
  "mcpServers": {
    "ralph": {
      "command": "node",
      "args": ["mcp/server.js"],
      "cwd": "${CLAUDE_PLUGIN_ROOT}",
      "env": {
        "RALPH_LIB_PATH": "${CLAUDE_PLUGIN_ROOT}/../lib"
      }
    }
  }
}
```

**Fallback if variable interpolation is not supported**: The MCP server resolves all paths relative to `import.meta.dirname` (ESM equivalent of `__dirname`). `RALPH_LIB_PATH` defaults to `path.resolve(import.meta.dirname, '../../lib')`.

The MCP server communicates via stdio transport. Claude Code discovers it through the `.mcp.json` file in the plugin directory.

## Plugin Directory Structure

```
plugin/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── .mcp.json                    # MCP server registration
├── package.json                 # Dependencies
├── skills/
│   ├── setup/
│   │   └── SKILL.md             # /ralph:setup — first-run wizard
│   ├── build/
│   │   └── SKILL.md             # /ralph:build — implement from plan
│   ├── full/
│   │   └── SKILL.md             # /ralph:full — complete autonomous cycle
│   ├── research/
│   │   └── SKILL.md             # /ralph:research — deep research mode
│   ├── review/
│   │   └── SKILL.md             # /ralph:review — specialist code review
│   └── spec/
│       └── SKILL.md             # /ralph:spec — interactive spec creation
├── agents/
│   └── ralph-monitor.md         # Agent for background monitoring of running containers
├── hooks/
│   ├── hooks.json               # SessionStart hook registration
│   ├── session-start            # Bootstrap script (bash)
│   └── run-hook.cmd             # Windows wrapper
└── mcp/
    ├── server.js                # MCP server entry point
    ├── tools/
    │   ├── start.js             # ralph_start — launch container for any mode
    │   ├── status.js            # ralph_status — check running containers
    │   ├── logs.js              # ralph_logs — retrieve iteration logs
    │   ├── steer.js             # ralph_steer — write to mailbox
    │   ├── control.js           # ralph_control — pause/resume/cleanup
    │   ├── result.js            # ralph_result — pull final outputs
    │   └── setup.js             # ralph_setup — pre-flight checks, image build
    └── lib/
        ├── container.js         # Adapter for ../../lib/utils/container.js
        ├── docker.js            # Adapter for ../../lib/utils/docker.js
        └── lifecycle.js         # Container registry, completion detection
```

## MCP Server Tools

### ralph_setup — Pre-flight and initialization

- **Inputs**: `workdir` (optional, defaults to cwd)
- **Checks**: Docker running, image exists, `.env` configured, git repo
- **Returns**: `{ ready: bool, missing: string[] }`
- **Behavior**: Can auto-build the Docker image if that's the only missing piece

### ralph_start — Launch a Ralph container

- **Inputs**: `spec` (string), `mode` (enum: plan|build|review|review-fix|full|decompose|spec|research|insights|debug|parallel-full), `workdir` (string, required — repo root path), `options` (object: `{ iterations?, verbose?, insights?, seedContent? }`)
- **Returns**: `{ containerId, containerName, branch, mode, spec }`
- **Behavior**: Always runs detached. Resolves image name, `.env`, and volume mounts from `workdir`. Branch preparation uses a temporary worktree (`git worktree add`) to avoid touching the user's working tree — checks out/creates `ralph/<spec>` in the worktree, commits seed files if `seedContent` provided, pushes to remote, then removes the worktree. This means `ralph_start` never modifies the user's checkout, even if they have uncommitted changes. Derives `RALPH_REPO_URL` and `RALPH_BRANCH` env vars for the container. Container names follow the pattern `ralph-<repo>-<spec>-<short-hash>` to avoid collisions when running multiple specs concurrently. Registers container in plugin state.

### ralph_status — Check running containers

- **Inputs**: `containerId` (optional — omit to list all Ralph containers)
- **Returns**: `{ containers: [{ id, name, mode, spec, running, exitCode, iterationCount, lastActivity }] }`
- **Behavior**: Calls `docker inspect` + reads `.ralph/state.json` from container.

### ralph_logs — Retrieve output

- **Inputs**: `containerId`, `tail` (number, default 100), `since` (timestamp, optional)
- **Returns**: `{ logs: string }`
- **Behavior**: Supports incremental fetching via `since` parameter.

### ralph_steer — Send directive to running container

- **Inputs**: `containerId`, `directive` (string)
- **Returns**: `{ delivered: bool }`
- **Behavior**: Writes directive to `.ralph/mailbox.md` inside the container via `docker exec`.

### ralph_control — Lifecycle control (pause/resume/cleanup)

- **Inputs**: `containerId`, `action` (enum: pause|resume|cleanup)
- **Returns**: `{ status: "paused" | "resumed" | "removed" }`
- **Behavior**: Creates/removes `.ralph/paused.md` inside container. `cleanup` removes stopped container and deregisters from plugin state.

### ralph_result — Pull final outputs

- **Inputs**: `containerId`, `artifact` (enum: plan|review|research|insights|spec|all)
- **Returns**: `{ artifact, content: string }` (or map of all artifacts for `all`)
- **Behavior**: Reads from container filesystem. Falls back to checking the git branch if container is gone — runs `git fetch origin ralph/<spec>` first to ensure the branch is available locally, since background mode pushes to remote only.

## Skills

All skills share a common pattern:
1. Pre-flight check via `ralph_setup`
2. Gather inputs from the user
3. Launch via `ralph_start`
4. Report container ID and how to check in

### /ralph:setup — First-run wizard

Walks through initialization: checks Docker, image, env configuration. Builds Docker image. Only needs to run once per repo. Other skills point here if pre-flight fails.

### /ralph:full — Autonomous full cycle

Asks for spec file. Confirms iterations. Launches full mode (plan -> build -> review -> fix -> distill -> check). Suggests monitoring options. On completion, surfaces summary of branch, commits, and review results.

### /ralph:build — Implement from plan

Checks that a plan exists (`.ralph/implementation_plan.md`). If not, suggests `/ralph:full` or creating a plan first. Launches build mode. On completion, summarizes commits and test results.

### /ralph:research — Deep research

Asks for a research topic/question. Creates a `research_seed.md` file with the topic and any context the user provides. Passes seed content to `ralph_start` via `options.seedContent`. On completion, pulls research artifacts from `.ralph/references/` and presents findings.

### /ralph:review — Specialist code review

Asks for spec or branch to review. Launches review mode with specialist routing (security, db, api, perf, ux, qa). On completion, pulls `.ralph/review.md` and presents findings by severity.

### /ralph:spec — Interactive spec creation

Asks for a name and gathers initial requirements conversationally (what to build, constraints, success criteria). Creates a `spec_seed.md` with this context. Passes seed content to `ralph_start` via `options.seedContent`. Launches spec mode (gather -> research -> draft -> debate -> refine). On completion, presents generated spec for user review.

### Common "while it's running" guidance

Each skill tells the user they can:
- Ask for status anytime (triggers `ralph_status` + `ralph_logs`)
- Steer Ralph with natural language (triggers `ralph_steer`)
- Pause/resume if needed

## Ralph Monitor Agent

The `ralph-monitor.md` agent is dispatched by skills after launching a container. It runs as a background subagent that:
- Periodically checks container status via `ralph_status`
- When the container completes (or fails), notifies the main conversation with a summary
- On success: reports branch name, commit count, and offers to pull results
- On failure: reports exit code, last log lines, and suggests next steps (retry, debug, check logs)

This provides the "managed lifecycle" behavior — the user doesn't have to remember to check back.

## Lifecycle Management

### Container registry

The MCP server maintains a lightweight registry of launched containers, persisted to `.ralph/plugin-state.json` at the git root (resolved via `RALPH_WORKDIR`, not `cwd`). Tracks: container ID, mode, spec, start time, last known status, last log offset.

### Completion detection

No active polling. On status request:
- Container exited with code 0 -> completed successfully
- Container exited with non-zero -> failed (include last logs)
- `.ralph/paused.md` exists -> paused by circuit breaker or human

### Result retrieval

When a container completes:
1. `ralph_result` reads artifacts from container filesystem before removal
2. If container is gone, checks the `ralph/<spec>` branch in local repo (background mode pushes)

### Steer flow

1. User says "tell Ralph to skip tests"
2. Claude Code invokes `ralph_steer(containerId, "Skip test execution...")`
3. MCP server runs `docker exec <container> bash -c 'echo "..." >> /workspace/.ralph/mailbox.md'`
4. Ralph's loop.sh picks up the directive on next iteration boundary

### Cleanup

Containers are not auto-removed. `ralph_status` surfaces stopped containers. Skills suggest cleanup after pulling results. Avoids losing artifacts from crashed containers.

## Session Hook

### hooks.json

Based on the superpowers plugin reference implementation (which uses the same pattern for its SessionStart hook):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start",
            "async": false
          }
        ]
      }
    ]
  }
}
```

Note: The matcher pattern and format is taken directly from the superpowers plugin's `hooks/hooks.json`. If Claude Code's hook API changes, this should be updated to match.

### SessionStart behavior

When a Claude Code session begins, the `session-start` hook script:
1. Checks if `.ralph/` directory exists in working directory
2. Checks for running Ralph containers for this repo (`docker ps --filter` by label)
3. Also checks for stopped-but-not-removed containers with results waiting
4. Injects context: running containers get "Ralph is running: `<spec>` in `<mode>` mode (iteration N/M). Ask me for status or results." Stopped containers get "Ralph finished `<spec>` — results ready to pull."

### Natural language bridging

MCP tools enable conversational access without explicit skill invocation:
- "What's Ralph doing?" -> `ralph_status`
- "Show me Ralph's latest output" -> `ralph_logs`
- "Tell Ralph to focus on auth first" -> `ralph_steer`
- "Pull Ralph's research results" -> `ralph_result`

## Dependencies on Ralph Core

The MCP server imports from Ralph's `lib/utils/`:
- `docker.js` — image checking, building
- `container.js` — exec, read, write operations
- `git.js` — branch management, remote detection
- `paths.js` — directory/file path resolution
- `colors.js` — not needed (MCP is headless), skip

### Module system and async strategy

The MCP server uses ESM (`"type": "module"` in `plugin/package.json`). Ralph's existing `lib/utils/` uses CommonJS and synchronous `execSync` calls. The `mcp/lib/` adapter layer:
- Imports Ralph utilities via `createRequire()` (ESM importing CJS)
- Wraps `execSync` calls in `child_process.execFile` with promises where blocking would be problematic (e.g., `docker build` which can take minutes)
- Accepts blocking for fast operations (e.g., `docker inspect`, `docker exec` with short timeouts) since the MCP SDK serializes tool calls — one at a time per server instance. This is intentional and acceptable for Ralph's use case
- Uses `@modelcontextprotocol/sdk` for the MCP protocol implementation

### Working directory resolution

Ralph's `paths.js` uses `process.cwd()` for `repoDir()`, which is incorrect when running inside an MCP server process. The adapter layer solves this:
- Every MCP tool that needs the repo root accepts a `workdir` parameter
- The adapter overrides `repoDir()` by setting `process.env.RALPH_WORKDIR` before calling into Ralph utilities
- `paths.js` adapter checks `RALPH_WORKDIR` first, falls back to `process.cwd()`
- The session hook passes the current working directory when starting the MCP server

### Error handling

MCP tools return structured errors with:
- `error.code` — machine-readable error type (e.g., `DOCKER_NOT_RUNNING`, `IMAGE_NOT_FOUND`, `CONTAINER_NOT_FOUND`, `STEER_FAILED`)
- `error.message` — human-readable description
- `error.suggestion` — actionable next step (e.g., "Run /ralph:setup to build the Docker image")

Key error scenarios:
- Docker not running → `DOCKER_NOT_RUNNING`, suggest starting Docker Desktop
- Image not found → `IMAGE_NOT_FOUND`, suggest `/ralph:setup`
- Container not found → `CONTAINER_NOT_FOUND`, suggest `ralph_status` to list available containers
- Steer on stopped container → `CONTAINER_STOPPED`, include exit code and last logs
- Docker exec timeout (>30s) → `EXEC_TIMEOUT`, suggest checking container health

## Out of Scope

- Active polling / push notifications (status is on-demand)
- Auto-cleanup of containers
- Multi-repo orchestration (one repo at a time)
- Plugin marketplace publishing (future consideration)
- Cost tracking / token budgets (existing Ralph gap, not introduced here)
