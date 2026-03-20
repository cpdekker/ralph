# Ralph Claude Code Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Ralph available as a Claude Code plugin with skills as guided entry points and an MCP server for Docker container orchestration.

**Architecture:** Self-contained `plugin/` directory in the Ralph repo. A Node.js MCP server (ESM, `@modelcontextprotocol/sdk`) wraps Ralph's existing CJS utilities via adapters. Skills are markdown files that guide users through launching and monitoring Ralph containers. A SessionStart hook provides ambient awareness of running containers.

**Tech Stack:** Node.js (ESM), `@modelcontextprotocol/sdk`, Ralph `lib/utils/` (CJS), Docker, bash hooks

**Spec:** `docs/superpowers/specs/2026-03-20-ralph-claude-code-plugin-design.md`

---

## File Structure

```
plugin/
├── .claude-plugin/
│   └── plugin.json                  # Plugin manifest (name, version, skills/agents/hooks pointers)
├── .mcp.json                        # MCP server registration (command: node mcp/server.js)
├── package.json                     # ESM, dependencies: @modelcontextprotocol/sdk
├── mcp/
│   ├── server.js                    # MCP server entry point — registers all tools, stdio transport
│   ├── lib/
│   │   ├── paths-adapter.js         # Wraps lib/utils/paths.js — RALPH_WORKDIR override for repoDir()
│   │   ├── docker-adapter.js        # Wraps lib/utils/docker.js — async wrappers where needed
│   │   ├── container-adapter.js     # Wraps lib/utils/container.js — async wrappers
│   │   ├── git-adapter.js           # Wraps lib/utils/git.js — adds worktree operations
│   │   ├── lifecycle.js             # Container registry — persists to .ralph/plugin-state.json
│   │   └── errors.js               # Structured error creation (code, message, suggestion)
│   └── tools/
│       ├── setup.js                 # ralph_setup — pre-flight checks, image build
│       ├── start.js                 # ralph_start — launch container (branch prep, docker run)
│       ├── status.js                # ralph_status — check running/stopped containers
│       ├── logs.js                  # ralph_logs — retrieve container output
│       ├── steer.js                 # ralph_steer — write to mailbox
│       ├── control.js               # ralph_control — pause/resume/cleanup
│       └── result.js                # ralph_result — pull artifacts from container or branch
├── skills/
│   ├── setup/
│   │   └── SKILL.md                 # /ralph:setup — first-run wizard
│   ├── full/
│   │   └── SKILL.md                 # /ralph:full — autonomous full cycle
│   ├── build/
│   │   └── SKILL.md                 # /ralph:build — implement from plan
│   ├── research/
│   │   └── SKILL.md                 # /ralph:research — deep research mode
│   ├── review/
│   │   └── SKILL.md                 # /ralph:review — specialist code review
│   └── spec/
│       └── SKILL.md                 # /ralph:spec — interactive spec creation
├── agents/
│   └── ralph-monitor.md             # Background monitor agent persona
└── hooks/
    ├── hooks.json                   # SessionStart hook registration
    ├── session-start                # Bash hook — checks for running/stopped containers
    └── run-hook.cmd                 # Windows polyglot wrapper (bash/cmd)
```

---

### Task 1: Plugin scaffold and manifest files

**Files:**
- Create: `plugin/.claude-plugin/plugin.json`
- Create: `plugin/.mcp.json`
- Create: `plugin/package.json`

- [ ] **Step 1: Create plugin directory structure**

```bash
mkdir -p plugin/.claude-plugin plugin/mcp/lib plugin/mcp/tools plugin/skills/setup plugin/skills/full plugin/skills/build plugin/skills/research plugin/skills/review plugin/skills/spec plugin/agents plugin/hooks
```

- [ ] **Step 2: Write plugin.json manifest**

Create `plugin/.claude-plugin/plugin.json`:

```json
{
  "name": "ralph",
  "description": "Ralph Wiggum — spin up Docker containers for autonomous coding tasks (build, research, spec, review) from within Claude Code",
  "version": "0.1.0",
  "author": {
    "name": "Chris Dekker"
  },
  "homepage": "https://github.com/cpdekker/ralph",
  "repository": "https://github.com/cpdekker/ralph",
  "license": "MIT",
  "keywords": ["ralph", "docker", "autonomous", "build", "research", "review", "spec"]
}
```

- [ ] **Step 3: Write .mcp.json**

Create `plugin/.mcp.json`. Use the playwright plugin format (no `mcpServers` wrapper — just command/args at top level):

```json
{
  "ralph": {
    "command": "node",
    "args": ["mcp/server.js"],
    "cwd": "${CLAUDE_PLUGIN_ROOT}"
  }
}
```

- [ ] **Step 4: Write package.json**

Create `plugin/package.json`:

```json
{
  "name": "ralph-claude-plugin",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  }
}
```

- [ ] **Step 5: Install dependencies**

```bash
cd plugin && npm install
```

- [ ] **Step 6: Commit**

```bash
git add plugin/.claude-plugin/plugin.json plugin/.mcp.json plugin/package.json plugin/package-lock.json
git commit -m "feat(plugin): scaffold plugin directory with manifest and MCP registration"
```

---

### Task 2: Patch lib/utils/paths.js for RALPH_WORKDIR support

The core `paths.js` uses `process.cwd()` for `repoDir()`. When called from the MCP server process, this returns the wrong directory. We need to patch it to check `RALPH_WORKDIR` first. This is critical because `docker.js`, `container.js`, and all functions that transitively call `repoDir()` (like `isInitialized()`, `getAvailableSpecs()`, etc.) depend on it.

**Files:**
- Modify: `lib/utils/paths.js`

- [ ] **Step 1: Patch repoDir() in lib/utils/paths.js**

In `lib/utils/paths.js`, change the `repoDir()` function from:

```javascript
function repoDir() {
  return process.cwd();
}
```

To:

```javascript
function repoDir() {
  return process.env.RALPH_WORKDIR || process.cwd();
}
```

This is backward-compatible — when `RALPH_WORKDIR` is not set (normal CLI usage), it falls back to `process.cwd()` as before. When set by the MCP adapter, all core functions automatically use the correct directory.

- [ ] **Step 2: Verify existing Ralph CLI still works**

```bash
node bin/ralph.js --help
```

Expected: Help output unchanged. The env var is not set during normal usage.

- [ ] **Step 3: Commit**

```bash
git add lib/utils/paths.js
git commit -m "feat(paths): support RALPH_WORKDIR env var override for MCP plugin"
```

---

### Task 3: MCP adapter layer — paths, errors, lifecycle

These are the foundational modules every tool depends on. No tests yet — these are thin wrappers. We'll validate them via integration tests when we build the tools.

**Files:**
- Create: `plugin/mcp/lib/paths-adapter.js`
- Create: `plugin/mcp/lib/errors.js`
- Create: `plugin/mcp/lib/lifecycle.js`

- [ ] **Step 1: Write paths-adapter.js**

Create `plugin/mcp/lib/paths-adapter.js`. This is a thin ESM wrapper that sets `RALPH_WORKDIR` and re-exports from core (which now respects the env var):

```javascript
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);

// Resolve Ralph lib path — env var or relative to this file
const libPath = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
const corePaths = require(path.join(libPath, 'utils', 'paths.js'));

/**
 * Set the working directory for all Ralph path operations.
 * Sets RALPH_WORKDIR which is read by core paths.js repoDir().
 * Must be called before any tool that uses repoDir().
 */
export function setWorkdir(workdir) {
  process.env.RALPH_WORKDIR = workdir;
}

// Re-export all core functions — they now respect RALPH_WORKDIR
export const {
  repoDir, ralphDir, isInitialized, getPromptPath,
  getAvailableSpecs, validateSpec, getSpecDetails, toDockerPath,
  libDir, pkgDir
} = corePaths;
```

- [ ] **Step 2: Write errors.js**

Create `plugin/mcp/lib/errors.js`:

```javascript
/**
 * Create a structured Ralph error object for MCP tool responses.
 */
export function ralphError(code, message, suggestion) {
  return {
    isError: true,
    content: [{
      type: 'text',
      text: JSON.stringify({ error: { code, message, suggestion } })
    }]
  };
}

// Pre-defined error factories
export const errors = {
  dockerNotRunning: () =>
    ralphError('DOCKER_NOT_RUNNING', 'Docker is not running', 'Start Docker Desktop and try again'),
  imageNotFound: (imageName) =>
    ralphError('IMAGE_NOT_FOUND', `Docker image "${imageName}" not found`, 'Run /ralph:setup to build the Docker image'),
  containerNotFound: (id) =>
    ralphError('CONTAINER_NOT_FOUND', `Container "${id}" not found`, 'Use ralph_status to list available containers'),
  containerStopped: (id, exitCode) =>
    ralphError('CONTAINER_STOPPED', `Container "${id}" has stopped (exit code ${exitCode})`, 'Check ralph_logs for details or ralph_result for outputs'),
  execTimeout: (id) =>
    ralphError('EXEC_TIMEOUT', `Command timed out on container "${id}"`, 'Check container health with ralph_status'),
  notInitialized: () =>
    ralphError('NOT_INITIALIZED', '.ralph directory not found in this repository', 'Run /ralph:setup to initialize Ralph'),
  noGitRepo: () =>
    ralphError('NO_GIT_REPO', 'Not a git repository', 'Navigate to a git repository and try again'),
};
```

- [ ] **Step 3: Write lifecycle.js**

Create `plugin/mcp/lib/lifecycle.js`. Container registry with JSON persistence:

```javascript
import fs from 'node:fs';
import path from 'node:path';
import { ralphDir } from './paths-adapter.js';

const STATE_FILE = 'plugin-state.json';

function statePath() {
  return path.join(ralphDir(), STATE_FILE);
}

function readState() {
  try {
    return JSON.parse(fs.readFileSync(statePath(), 'utf-8'));
  } catch {
    return { containers: {} };
  }
}

function writeState(state) {
  const dir = ralphDir();
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(statePath(), JSON.stringify(state, null, 2));
}

export function registerContainer({ containerId, containerName, mode, spec, branch }) {
  const state = readState();
  state.containers[containerId] = {
    containerName,
    mode,
    spec,
    branch,
    startTime: new Date().toISOString(),
    lastStatus: 'running',
    lastLogOffset: null
  };
  writeState(state);
}

export function deregisterContainer(containerId) {
  const state = readState();
  delete state.containers[containerId];
  writeState(state);
}

export function updateContainer(containerId, updates) {
  const state = readState();
  if (state.containers[containerId]) {
    Object.assign(state.containers[containerId], updates);
    writeState(state);
  }
}

export function getContainer(containerId) {
  const state = readState();
  return state.containers[containerId] || null;
}

export function getAllContainers() {
  const state = readState();
  return state.containers;
}
```

- [ ] **Step 4: Commit**

```bash
git add plugin/mcp/lib/paths-adapter.js plugin/mcp/lib/errors.js plugin/mcp/lib/lifecycle.js
git commit -m "feat(plugin): add MCP adapter layer — paths, errors, lifecycle registry"
```

---

### Task 3: MCP adapter layer — docker, container, git

**Files:**
- Create: `plugin/mcp/lib/docker-adapter.js`
- Create: `plugin/mcp/lib/container-adapter.js`
- Create: `plugin/mcp/lib/git-adapter.js`

- [ ] **Step 1: Write docker-adapter.js**

Create `plugin/mcp/lib/docker-adapter.js`. Wraps `lib/utils/docker.js` with workdir awareness and async `buildImage`:

```javascript
import { createRequire } from 'node:module';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { setWorkdir, repoDir } from './paths-adapter.js';

const execFileAsync = promisify(execFile);
const require = createRequire(import.meta.url);
const libPath = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
const coreDocker = require(path.join(libPath, 'utils', 'docker.js'));

/**
 * Get the Docker image name for a given workdir.
 */
export function getImageName(workdir) {
  setWorkdir(workdir);
  return coreDocker.getImageName();
}

/**
 * Check if Docker image exists. Synchronous (fast).
 */
export function imageExists(workdir, imageName) {
  setWorkdir(workdir);
  return coreDocker.imageExists(imageName);
}

/**
 * Build Docker image. Async because this can take minutes.
 */
export async function buildImage(workdir, imageName) {
  setWorkdir(workdir);
  const target = imageName || getImageName(workdir);
  const dockerDir = path.join(libPath, 'docker');
  await execFileAsync('docker', ['build', '-t', target, dockerDir], {
    cwd: repoDir()
  });
}

/**
 * Check if Docker daemon is available and running. Synchronous (fast).
 */
export function isDockerAvailable() {
  return coreDocker.isDockerAvailable();
}

export function isDockerRunning() {
  return coreDocker.isDockerRunning();
}
```

- [ ] **Step 2: Write container-adapter.js**

Create `plugin/mcp/lib/container-adapter.js`. Wraps `lib/utils/container.js`:

```javascript
import { createRequire } from 'node:module';
import path from 'node:path';
import { setWorkdir } from './paths-adapter.js';

const require = createRequire(import.meta.url);
const libPath = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
const coreContainer = require(path.join(libPath, 'utils', 'container.js'));

export function findRalphContainers(workdir, spec) {
  setWorkdir(workdir);
  return coreContainer.findRalphContainers(spec);
}

export function resolveContainer(workdir, spec) {
  setWorkdir(workdir);
  return coreContainer.resolveContainer(spec);
}

export function containerReadFile(containerName, filePath) {
  return coreContainer.containerReadFile(containerName, filePath);
}

export function containerWriteFile(containerName, filePath, content) {
  return coreContainer.containerWriteFile(containerName, filePath, content);
}

export function containerExec(containerName, command) {
  return coreContainer.containerExec(containerName, command);
}
```

- [ ] **Step 3: Write git-adapter.js**

Create `plugin/mcp/lib/git-adapter.js`. Wraps `lib/utils/git.js` and adds worktree operations:

```javascript
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';

const require = createRequire(import.meta.url);
const libPath = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
const coreGit = require(path.join(libPath, 'utils', 'git.js'));

export const { getRemoteUrl, getBranch, isGitRepo } = coreGit;

/**
 * Prepare a spec branch using a temporary git worktree.
 * Does NOT modify the user's working tree.
 *
 * @param {string} workdir - The repo root
 * @param {string} spec - Spec name (branch will be ralph/<spec>)
 * @param {string|null} seedContent - Optional seed file content
 * @param {string} seedFilename - Name for seed file (default: spec_seed.md)
 * @returns {{ branch: string }} The prepared branch name
 */
export function prepareSpecBranch(workdir, spec, seedContent = null, seedFilename = 'spec_seed.md') {
  const branch = `ralph/${spec}`;
  const worktreeDir = path.join(os.tmpdir(), `ralph-worktree-${spec}-${Date.now()}`);

  try {
    // Check if branch exists on remote
    let branchExists = false;
    try {
      execFileSync('git', ['ls-remote', '--exit-code', '--heads', 'origin', branch], { cwd: workdir });
      branchExists = true;
    } catch { /* branch doesn't exist remotely */ }

    // Check if branch exists locally
    if (!branchExists) {
      try {
        execFileSync('git', ['rev-parse', '--verify', branch], { cwd: workdir });
        branchExists = true;
      } catch { /* branch doesn't exist locally either */ }
    }

    // Create worktree
    if (branchExists) {
      execFileSync('git', ['worktree', 'add', worktreeDir, branch], { cwd: workdir });
    } else {
      const baseBranch = getBranch(workdir) || 'main';
      execFileSync('git', ['worktree', 'add', '-b', branch, worktreeDir, baseBranch], { cwd: workdir });
    }

    // Write seed file if provided
    if (seedContent) {
      const ralphSpecsDir = path.join(worktreeDir, '.ralph', 'specs');
      fs.mkdirSync(ralphSpecsDir, { recursive: true });
      fs.writeFileSync(path.join(worktreeDir, '.ralph', seedFilename), seedContent);

      execFileSync('git', ['add', '.'], { cwd: worktreeDir });
      execFileSync('git', ['commit', '-m', `Ralph: add ${seedFilename} for ${spec}`], { cwd: worktreeDir });
    }

    // Push branch to remote
    try {
      execFileSync('git', ['push', '-u', 'origin', branch], { cwd: worktreeDir });
    } catch {
      // Push may fail if no remote — that's ok for foreground mode
    }

    return { branch };
  } finally {
    // Always clean up worktree
    try {
      execFileSync('git', ['worktree', 'remove', '--force', worktreeDir], { cwd: workdir });
    } catch {
      // Best-effort cleanup
    }
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add plugin/mcp/lib/docker-adapter.js plugin/mcp/lib/container-adapter.js plugin/mcp/lib/git-adapter.js
git commit -m "feat(plugin): add MCP adapters for docker, container, and git utilities"
```

---

### Task 4: MCP server entry point and ralph_setup tool

**Files:**
- Create: `plugin/mcp/server.js`
- Create: `plugin/mcp/tools/setup.js`

- [ ] **Step 1: Write the ralph_setup tool**

Create `plugin/mcp/tools/setup.js`:

```javascript
import fs from 'node:fs';
import path from 'node:path';
import { repoDir, ralphDir, setWorkdir, isInitialized } from '../lib/paths-adapter.js';
import { isDockerAvailable, isDockerRunning, getImageName, imageExists, buildImage } from '../lib/docker-adapter.js';
import { isGitRepo } from '../lib/git-adapter.js';
import { errors } from '../lib/errors.js';

export const definition = {
  name: 'ralph_setup',
  description: 'Pre-flight checks and initialization for Ralph. Checks Docker, image, .env, and git repo. Can auto-build the Docker image.',
  inputSchema: {
    type: 'object',
    properties: {
      workdir: {
        type: 'string',
        description: 'Repository root path. Defaults to current working directory.'
      },
      autoBuild: {
        type: 'boolean',
        description: 'Automatically build the Docker image if missing. Default: true.'
      }
    }
  }
};

export async function handler({ workdir, autoBuild = true }) {
  const dir = workdir || process.cwd();
  setWorkdir(dir);

  const missing = [];

  // Check git repo
  if (!isGitRepo(dir)) return errors.noGitRepo();

  // Check Docker
  if (!isDockerAvailable()) {
    missing.push('docker_not_installed');
  } else if (!isDockerRunning()) {
    missing.push('docker_not_running');
  }

  // Check .ralph directory
  if (!isInitialized()) {
    missing.push('ralph_not_initialized');
  }

  // Check .env file
  const envPath = path.join(ralphDir(), '.env');
  if (!fs.existsSync(envPath)) {
    missing.push('env_file_missing');
  }

  // Check Docker image
  const imageName = getImageName(dir);
  if (missing.length === 0 || !missing.some(m => m.startsWith('docker'))) {
    if (!imageExists(dir, imageName)) {
      if (autoBuild && missing.length === 0) {
        await buildImage(dir, imageName);
      } else {
        missing.push('image_not_built');
      }
    }
  }

  const ready = missing.length === 0;
  return {
    content: [{
      type: 'text',
      text: JSON.stringify({ ready, missing, imageName, workdir: dir })
    }]
  };
}
```

- [ ] **Step 2: Write the MCP server entry point**

Create `plugin/mcp/server.js`. Uses the low-level `Server` class with `setRequestHandler` to avoid Zod dependency — JSON Schema `inputSchema` objects work directly:

```javascript
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';

// Import tools
import * as setupTool from './tools/setup.js';

// Tool registry
const tools = [setupTool];
const toolMap = new Map(tools.map(t => [t.definition.name, t]));

const server = new Server(
  { name: 'ralph', version: '0.1.0' },
  { capabilities: { tools: {} } }
);

// List tools handler
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: tools.map(t => ({
    name: t.definition.name,
    description: t.definition.description,
    inputSchema: t.definition.inputSchema
  }))
}));

// Call tool handler
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const tool = toolMap.get(request.params.name);
  if (!tool) {
    return { content: [{ type: 'text', text: `Unknown tool: ${request.params.name}` }], isError: true };
  }
  try {
    return await tool.handler(request.params.arguments || {});
  } catch (err) {
    return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
  }
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
```

- [ ] **Step 3: Test manually — verify MCP server starts**

```bash
cd plugin && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' | node mcp/server.js
```

Expected: JSON response with server capabilities including `ralph_setup` tool.

- [ ] **Step 4: Commit**

```bash
git add plugin/mcp/server.js plugin/mcp/tools/setup.js
git commit -m "feat(plugin): add MCP server entry point and ralph_setup tool"
```

---

### Task 5: ralph_start tool

**Files:**
- Create: `plugin/mcp/tools/start.js`

- [ ] **Step 1: Write ralph_start tool**

Create `plugin/mcp/tools/start.js`. This is the core tool — launches a detached Docker container:

```javascript
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import path from 'node:path';
import { setWorkdir, repoDir, ralphDir, toDockerPath } from '../lib/paths-adapter.js';
import { getImageName, imageExists } from '../lib/docker-adapter.js';
import { isGitRepo, getRemoteUrl, getBranch, prepareSpecBranch } from '../lib/git-adapter.js';
import { registerContainer } from '../lib/lifecycle.js';
import { errors, ralphError } from '../lib/errors.js';

const VALID_MODES = [
  'plan', 'build', 'review', 'review-fix', 'full', 'decompose',
  'spec', 'research', 'insights', 'debug', 'parallel-full'
];

const DEFAULT_ITERATIONS = {
  plan: 5, build: 10, review: 10, 'review-fix': 5, debug: 1,
  full: 10, decompose: 1, spec: 8, research: 10, insights: 1,
  'parallel-full': 100
};

export const definition = {
  name: 'ralph_start',
  description: 'Launch a Ralph container for autonomous coding tasks. Always runs in background (detached Docker container). Handles branch preparation via git worktree.',
  inputSchema: {
    type: 'object',
    properties: {
      spec: { type: 'string', description: 'Spec name (maps to .ralph/specs/<spec>.md)' },
      mode: { type: 'string', enum: VALID_MODES, description: 'Ralph mode to run' },
      workdir: { type: 'string', description: 'Repository root path (required)' },
      options: {
        type: 'object',
        properties: {
          iterations: { type: 'number', description: 'Number of iterations' },
          verbose: { type: 'boolean', description: 'Enable verbose output' },
          insights: { type: 'boolean', description: 'Enable insights collection' },
          seedContent: { type: 'string', description: 'Seed file content for spec/research modes' }
        }
      }
    },
    required: ['spec', 'mode', 'workdir']
  }
};

export async function handler({ spec, mode, workdir, options = {} }) {
  setWorkdir(workdir);

  // Validate
  if (!isGitRepo(workdir)) return errors.noGitRepo();

  const imageName = getImageName(workdir);
  if (!imageExists(workdir, imageName)) return errors.imageNotFound(imageName);

  const repoUrl = getRemoteUrl(workdir);
  if (!repoUrl) {
    return errors.ralphError?.('NO_REMOTE', 'No git remote "origin" configured', 'Add a git remote: git remote add origin <url>') ||
      { isError: true, content: [{ type: 'text', text: 'No git remote origin configured' }] };
  }

  // Prepare branch (uses worktree — does not touch user's checkout)
  const seedFilename = mode === 'research' ? 'research_seed.md' : 'spec_seed.md';
  const { branch } = prepareSpecBranch(workdir, spec, options.seedContent || null, seedFilename);

  // Build container name
  const repoName = path.basename(workdir).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const shortHash = crypto.randomBytes(4).toString('hex');
  const containerName = `ralph-${repoName}-${spec}-${shortHash}`.replace(/[^a-z0-9-]/g, '-');

  // Build docker run args
  const iterations = options.iterations || DEFAULT_ITERATIONS[mode] || 10;
  const libDir = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
  const libDockerPath = toDockerPath(libDir);
  const envFilePath = path.join(ralphDir(), '.env');
  const baseBranch = getBranch(workdir);

  const dockerArgs = [
    'run', '-d',
    '--name', containerName,
    '--label', `ralph.repo=${repoName}`,
    '--label', `ralph.spec=${spec}`,
    '--label', `ralph.mode=${mode}`,
    '--env-file', envFilePath,
    '-v', `${libDockerPath}:/ralph-lib:ro`,
    '-e', `RALPH_REPO_URL=${repoUrl}`,
    '-e', `RALPH_BRANCH=${branch}`,
    '-e', `RALPH_BASE_BRANCH=${baseBranch}`
  ];

  if (options.insights) dockerArgs.push('-e', 'RALPH_INSIGHTS=true');
  if (options.verbose) dockerArgs.push('-e', 'RALPH_VERBOSE=true');

  dockerArgs.push(
    imageName,
    'bash', '/ralph-lib/scripts/loop.sh',
    spec, mode, String(iterations)
  );

  // Note: --verbose is passed as env var RALPH_VERBOSE above, not as a positional arg.
  // loop.sh checks the --verbose flag at position 4, so pass it correctly if needed.
  if (options.verbose) dockerArgs.push('--verbose');

  // Launch
  let containerId;
  try {
    containerId = execFileSync('docker', dockerArgs, {
      encoding: 'utf-8',
      cwd: workdir
    }).trim();
  } catch (err) {
    return ralphError('DOCKER_RUN_FAILED', `Failed to start container: ${err.message}`,
      'Check Docker is running and the image exists. Run /ralph:setup if needed.');
  }

  // Register in lifecycle
  registerContainer({
    containerId: containerId.substring(0, 12),
    containerName,
    mode,
    spec,
    branch
  });

  return {
    content: [{
      type: 'text',
      text: JSON.stringify({
        containerId: containerId.substring(0, 12),
        containerName,
        branch,
        mode,
        spec,
        iterations
      })
    }]
  };
}
```

- [ ] **Step 2: Register in server.js**

Add import at the top of `plugin/mcp/server.js`:

```javascript
import * as startTool from './tools/start.js';
```

Add `startTool` to the `tools` array:

```javascript
const tools = [setupTool, startTool];
```

- [ ] **Step 3: Commit**

```bash
git add plugin/mcp/tools/start.js plugin/mcp/server.js
git commit -m "feat(plugin): add ralph_start tool — launches detached Docker containers"
```

---

### Task 6: ralph_status tool

**Files:**
- Create: `plugin/mcp/tools/status.js`

- [ ] **Step 1: Write ralph_status tool**

Create `plugin/mcp/tools/status.js`:

```javascript
import { execFileSync } from 'node:child_process';
import { getAllContainers, getContainer, updateContainer } from '../lib/lifecycle.js';
import { containerReadFile } from '../lib/container-adapter.js';

export const definition = {
  name: 'ralph_status',
  description: 'Check status of running and stopped Ralph containers. Omit containerId to list all.',
  inputSchema: {
    type: 'object',
    properties: {
      containerId: {
        type: 'string',
        description: 'Container ID to check. Omit to list all Ralph containers.'
      }
    }
  }
};

function inspectContainer(containerId) {
  try {
    const json = execFileSync('docker', ['inspect', '--format', '{{json .State}}', containerId], {
      encoding: 'utf-8',
      timeout: 10000
    }).trim();
    return JSON.parse(json);
  } catch {
    return null;
  }
}

function getIterationInfo(containerName) {
  const stateJson = containerReadFile(containerName, '/workspace/.ralph/state.json');
  if (stateJson) {
    try {
      const state = JSON.parse(stateJson);
      return { iteration: state.iteration, maxIterations: state.max_iterations };
    } catch { /* ignore */ }
  }
  return null;
}

export async function handler({ containerId } = {}) {
  const registered = containerId ? { [containerId]: getContainer(containerId) } : getAllContainers();
  const containers = [];

  for (const [id, meta] of Object.entries(registered)) {
    if (!meta) continue;

    const state = inspectContainer(id);
    const running = state?.Running ?? false;
    const exitCode = state?.ExitCode ?? null;
    const iterationInfo = running ? getIterationInfo(meta.containerName) : null;

    updateContainer(id, { lastStatus: running ? 'running' : 'stopped' });

    containers.push({
      id,
      name: meta.containerName,
      mode: meta.mode,
      spec: meta.spec,
      branch: meta.branch,
      running,
      exitCode,
      iterationCount: iterationInfo?.iteration ?? null,
      maxIterations: iterationInfo?.maxIterations ?? null,
      lastActivity: meta.startTime
    });
  }

  return {
    content: [{
      type: 'text',
      text: JSON.stringify({ containers })
    }]
  };
}
```

- [ ] **Step 2: Register in server.js**

Add `import * as statusTool from './tools/status.js';` and add `statusTool` to the `tools` array.

- [ ] **Step 3: Commit**

```bash
git add plugin/mcp/tools/status.js plugin/mcp/server.js
git commit -m "feat(plugin): add ralph_status tool — check container status"
```

---

### Task 7: ralph_logs, ralph_steer, ralph_control tools

**Files:**
- Create: `plugin/mcp/tools/logs.js`
- Create: `plugin/mcp/tools/steer.js`
- Create: `plugin/mcp/tools/control.js`

- [ ] **Step 1: Write ralph_logs tool**

Create `plugin/mcp/tools/logs.js`:

```javascript
import { execFileSync } from 'node:child_process';
import { getContainer, updateContainer } from '../lib/lifecycle.js';
import { errors } from '../lib/errors.js';

export const definition = {
  name: 'ralph_logs',
  description: 'Retrieve output logs from a Ralph container.',
  inputSchema: {
    type: 'object',
    properties: {
      containerId: { type: 'string', description: 'Container ID' },
      tail: { type: 'number', description: 'Number of lines to retrieve (default: 100)' },
      since: { type: 'string', description: 'Only show logs since this timestamp (ISO-8601)' }
    },
    required: ['containerId']
  }
};

export async function handler({ containerId, tail = 100, since }) {
  const meta = getContainer(containerId);
  if (!meta) return errors.containerNotFound(containerId);

  const args = ['logs'];
  if (tail) args.push('--tail', String(tail));
  if (since) args.push('--since', since);
  args.push(containerId);

  try {
    const logs = execFileSync('docker', args, {
      encoding: 'utf-8',
      timeout: 15000,
      maxBuffer: 1024 * 1024 // 1MB
    });

    updateContainer(containerId, { lastLogOffset: new Date().toISOString() });

    return {
      content: [{ type: 'text', text: logs || '(no logs yet)' }]
    };
  } catch (err) {
    return errors.containerNotFound(containerId);
  }
}
```

- [ ] **Step 2: Write ralph_steer tool**

Create `plugin/mcp/tools/steer.js`:

```javascript
import { getContainer } from '../lib/lifecycle.js';
import { containerExec } from '../lib/container-adapter.js';
import { errors } from '../lib/errors.js';

export const definition = {
  name: 'ralph_steer',
  description: 'Send a directive to a running Ralph container via the mailbox system. Ralph picks it up on the next iteration boundary.',
  inputSchema: {
    type: 'object',
    properties: {
      containerId: { type: 'string', description: 'Container ID' },
      directive: { type: 'string', description: 'Directive text for Ralph' }
    },
    required: ['containerId', 'directive']
  }
};

export async function handler({ containerId, directive }) {
  const meta = getContainer(containerId);
  if (!meta) return errors.containerNotFound(containerId);

  // Append to mailbox using >> to avoid race condition with Ralph reading/clearing it
  const timestamp = new Date().toISOString();
  const escaped = directive.replace(/'/g, "'\\''");
  const result = containerExec(
    meta.containerName,
    `bash -c 'echo "---" >> /workspace/.ralph/mailbox.md && echo "**[${timestamp}]** ${escaped}" >> /workspace/.ralph/mailbox.md'`
  );

  if (result === null) {
    return errors.containerStopped(containerId, 'unknown');
  }

  return {
    content: [{
      type: 'text',
      text: JSON.stringify({ delivered: true, directive })
    }]
  };
}
```

- [ ] **Step 3: Write ralph_control tool**

Create `plugin/mcp/tools/control.js`:

```javascript
import { execFileSync } from 'node:child_process';
import { getContainer, deregisterContainer } from '../lib/lifecycle.js';
import { containerWriteFile, containerExec } from '../lib/container-adapter.js';
import { errors } from '../lib/errors.js';

export const definition = {
  name: 'ralph_control',
  description: 'Lifecycle control for Ralph containers: pause, resume, or cleanup (remove stopped container).',
  inputSchema: {
    type: 'object',
    properties: {
      containerId: { type: 'string', description: 'Container ID' },
      action: { type: 'string', enum: ['pause', 'resume', 'cleanup'], description: 'Action to perform' }
    },
    required: ['containerId', 'action']
  }
};

export async function handler({ containerId, action }) {
  const meta = getContainer(containerId);
  if (!meta) return errors.containerNotFound(containerId);

  switch (action) {
    case 'pause': {
      const content = `Paused by Claude Code plugin at ${new Date().toISOString()}\n`;
      const ok = containerWriteFile(meta.containerName, '/workspace/.ralph/paused.md', content);
      if (!ok) return errors.containerStopped(containerId, 'unknown');
      return { content: [{ type: 'text', text: JSON.stringify({ status: 'paused' }) }] };
    }

    case 'resume': {
      containerExec(meta.containerName, 'rm -f /workspace/.ralph/paused.md');
      return { content: [{ type: 'text', text: JSON.stringify({ status: 'resumed' }) }] };
    }

    case 'cleanup': {
      try {
        execFileSync('docker', ['rm', '-f', containerId], { encoding: 'utf-8', timeout: 10000 });
      } catch { /* container may already be gone */ }
      deregisterContainer(containerId);
      return { content: [{ type: 'text', text: JSON.stringify({ status: 'removed' }) }] };
    }
  }
}
```

- [ ] **Step 4: Register all three in server.js**

Add imports for `logsTool`, `steerTool`, `controlTool` and add all three to the `tools` array.

- [ ] **Step 5: Commit**

```bash
git add plugin/mcp/tools/logs.js plugin/mcp/tools/steer.js plugin/mcp/tools/control.js plugin/mcp/server.js
git commit -m "feat(plugin): add ralph_logs, ralph_steer, ralph_control tools"
```

---

### Task 8: ralph_result tool

**Files:**
- Create: `plugin/mcp/tools/result.js`

- [ ] **Step 1: Write ralph_result tool**

Create `plugin/mcp/tools/result.js`:

```javascript
import { execFileSync } from 'node:child_process';
import { getContainer } from '../lib/lifecycle.js';
import { containerReadFile, containerExec } from '../lib/container-adapter.js';
import { errors } from '../lib/errors.js';

const ARTIFACT_PATHS = {
  plan: '/workspace/.ralph/implementation_plan.md',
  review: '/workspace/.ralph/review.md',
  spec: '/workspace/.ralph/specs/active.md',
  insights: '/workspace/.ralph/insights/',
  research: '/workspace/.ralph/references/'
};

export const definition = {
  name: 'ralph_result',
  description: 'Pull final outputs from a completed Ralph container. Falls back to git branch if container is gone.',
  inputSchema: {
    type: 'object',
    properties: {
      containerId: { type: 'string', description: 'Container ID' },
      artifact: {
        type: 'string',
        enum: ['plan', 'review', 'research', 'insights', 'spec', 'all'],
        description: 'Which artifact to retrieve'
      }
    },
    required: ['containerId', 'artifact']
  }
};

function readFromContainer(containerName, artifact) {
  const artifactPath = ARTIFACT_PATHS[artifact];
  if (!artifactPath) return null;

  // For directories (research, insights), list and read all files
  if (artifactPath.endsWith('/')) {
    const listing = containerExec(containerName, `find ${artifactPath} -name "*.md" -type f 2>/dev/null`);
    if (!listing) return null;

    const files = listing.trim().split('\n').filter(Boolean);
    const results = {};
    for (const f of files) {
      const content = containerReadFile(containerName, f);
      if (content) results[f.replace(artifactPath, '')] = content;
    }
    return Object.keys(results).length > 0 ? JSON.stringify(results) : null;
  }

  return containerReadFile(containerName, artifactPath);
}

function readFromBranch(workdir, branch, artifact) {
  const singleFilePaths = {
    plan: '.ralph/implementation_plan.md',
    review: '.ralph/review.md',
    spec: '.ralph/specs/active.md'
  };

  const dirPaths = {
    research: '.ralph/references/',
    insights: '.ralph/insights/'
  };

  try {
    // Fetch branch from remote first
    execFileSync('git', ['fetch', 'origin', branch], { cwd: workdir, timeout: 30000 });

    // Single file artifacts
    if (singleFilePaths[artifact]) {
      return execFileSync('git', ['show', `origin/${branch}:${singleFilePaths[artifact]}`], {
        cwd: workdir, encoding: 'utf-8', timeout: 10000
      });
    }

    // Directory artifacts (research, insights) — list and read all .md files
    if (dirPaths[artifact]) {
      const dirPath = dirPaths[artifact];
      const listing = execFileSync('git', ['ls-tree', '-r', '--name-only', `origin/${branch}`, dirPath], {
        cwd: workdir, encoding: 'utf-8', timeout: 10000
      }).trim();
      if (!listing) return null;

      const files = listing.split('\n').filter(f => f.endsWith('.md'));
      const results = {};
      for (const f of files) {
        try {
          results[f.replace(dirPath, '')] = execFileSync('git', ['show', `origin/${branch}:${f}`], {
            cwd: workdir, encoding: 'utf-8', timeout: 10000
          });
        } catch { /* skip unreadable files */ }
      }
      return Object.keys(results).length > 0 ? JSON.stringify(results) : null;
    }

    return null;
  } catch {
    return null;
  }
}

export async function handler({ containerId, artifact }) {
  const meta = getContainer(containerId);
  if (!meta) return errors.containerNotFound(containerId);

  const artifacts = artifact === 'all'
    ? ['plan', 'review', 'research', 'insights', 'spec']
    : [artifact];

  const results = {};

  for (const art of artifacts) {
    // Try container first
    let content = readFromContainer(meta.containerName, art);

    // Fall back to git branch
    if (!content && meta.branch) {
      const workdir = process.env.RALPH_WORKDIR || process.cwd();
      content = readFromBranch(workdir, meta.branch, art);
    }

    if (content) results[art] = content;
  }

  if (Object.keys(results).length === 0) {
    return {
      content: [{ type: 'text', text: JSON.stringify({ artifact, content: null, message: 'No artifacts found. Container may still be running.' }) }]
    };
  }

  return {
    content: [{
      type: 'text',
      text: artifact === 'all'
        ? JSON.stringify(results)
        : JSON.stringify({ artifact, content: results[artifact] })
    }]
  };
}
```

- [ ] **Step 2: Register in server.js**

Add `import * as resultTool from './tools/result.js';` and add `resultTool` to the `tools` array. At this point the array should be:

```javascript
const tools = [setupTool, startTool, statusTool, logsTool, steerTool, controlTool, resultTool];
```

All 7 tools are now registered.

- [ ] **Step 3: Commit**

```bash
git add plugin/mcp/tools/result.js plugin/mcp/server.js
git commit -m "feat(plugin): add ralph_result tool — pull artifacts from containers or branches"
```

---

### Task 9: SessionStart hook

**Files:**
- Create: `plugin/hooks/hooks.json`
- Create: `plugin/hooks/session-start`
- Create: `plugin/hooks/run-hook.cmd`

- [ ] **Step 1: Write hooks.json**

Create `plugin/hooks/hooks.json`:

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

- [ ] **Step 2: Write session-start hook script**

Create `plugin/hooks/session-start`:

```bash
#!/usr/bin/env bash
# SessionStart hook for Ralph plugin
# Checks for running/stopped Ralph containers and injects context

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Check if .ralph/ exists in current directory
if [ ! -d ".ralph" ]; then
  # No Ralph setup — emit empty context
  printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": ""\n  }\n}\n'
  exit 0
fi

# Check for Ralph containers
context_parts=()

# Running containers
running=$(docker ps --filter "label=ralph.repo" --format '{{.Names}} {{.Label "ralph.spec"}} {{.Label "ralph.mode"}}' 2>/dev/null || true)
if [ -n "$running" ]; then
  while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    spec=$(echo "$line" | awk '{print $2}')
    mode=$(echo "$line" | awk '{print $3}')
    context_parts+=("Ralph is running: \`${spec}\` in \`${mode}\` mode (container: ${name}).")
  done <<< "$running"
fi

# Stopped containers (not removed)
stopped=$(docker ps -a --filter "label=ralph.repo" --filter "status=exited" --format '{{.Names}} {{.Label "ralph.spec"}} {{.Label "ralph.mode"}}' 2>/dev/null || true)
if [ -n "$stopped" ]; then
  while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    spec=$(echo "$line" | awk '{print $2}')
    mode=$(echo "$line" | awk '{print $3}')
    context_parts+=("Ralph finished \`${spec}\` (\`${mode}\` mode) — results ready to pull (container: ${name}).")
  done <<< "$stopped"
fi

# Build context message
if [ ${#context_parts[@]} -gt 0 ]; then
  context="Ralph containers detected:\\n"
  for part in "${context_parts[@]}"; do
    context+="- ${part}\\n"
  done
  context+="\\nUse ralph_status for details, ralph_logs for output, or ralph_result to pull artifacts."
else
  context=""
fi

# Escape for JSON
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

escaped=$(escape_for_json "$context")

# Output platform-appropriate JSON
if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
  printf '{\n  "additional_context": "%s"\n}\n' "$escaped"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$escaped"
else
  printf '{\n  "additional_context": "%s"\n}\n' "$escaped"
fi

exit 0
```

- [ ] **Step 3: Write run-hook.cmd**

Copy the polyglot wrapper from superpowers — it's platform-agnostic and works as-is:

Create `plugin/hooks/run-hook.cmd`:

```
: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot wrapper for hook scripts.
REM On Windows: cmd.exe runs the batch portion, which finds and calls bash.
REM On Unix: the shell interprets this as a script (: is a no-op in bash).

if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)

set "HOOK_DIR=%~dp0"

REM Try Git for Windows bash in standard locations
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM Try bash on PATH
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

exit /b 0
CMDBLOCK

# Unix: run the named script directly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
```

- [ ] **Step 4: Make session-start executable**

```bash
chmod +x plugin/hooks/session-start
```

- [ ] **Step 5: Commit**

```bash
git add plugin/hooks/hooks.json plugin/hooks/session-start plugin/hooks/run-hook.cmd
git commit -m "feat(plugin): add SessionStart hook — ambient awareness of running containers"
```

---

### Task 10: Skills — setup, full, build

**Files:**
- Create: `plugin/skills/setup/SKILL.md`
- Create: `plugin/skills/full/SKILL.md`
- Create: `plugin/skills/build/SKILL.md`

- [ ] **Step 1: Write /ralph:setup skill**

Create `plugin/skills/setup/SKILL.md`:

```markdown
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
```

- [ ] **Step 2: Write /ralph:full skill**

Create `plugin/skills/full/SKILL.md`:

```markdown
---
name: full
description: Launch Ralph's full autonomous cycle — plan, build, review, fix, and check — in a background Docker container. Use for end-to-end feature implementation from a spec.
---

# Ralph Full Cycle

Launch an autonomous Ralph container that runs: plan -> build -> review -> fix -> distill -> completion check, repeating until done.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Pick spec**: Ask the user which spec to run. If they provide a name, verify it exists as `.ralph/specs/<name>.md`. If they're unsure, list available specs from the `.ralph/specs/` directory using the Glob tool.

3. **Confirm options**: Ask the user to confirm:
   - Iterations (default: 10 cycles)
   - Whether to enable insights collection
   Show defaults and let user press enter to accept.

4. **Launch**: Call `ralph_start` with:
   - `spec`: the chosen spec name
   - `mode`: `"full"`
   - `workdir`: current repo root
   - `options`: `{ iterations, insights }` as confirmed

5. **Report**: Tell the user:
   - Container ID and name
   - Branch being worked on (`ralph/<spec>`)
   - How to check in: "Ask me for status anytime", "Say 'show Ralph logs' for recent output", "Say 'tell Ralph to...' to steer it"

## While Running

The user can interact naturally:
- "What's Ralph doing?" → call `ralph_status` then `ralph_logs`
- "Tell Ralph to skip tests" → call `ralph_steer` with the directive
- "Pause Ralph" → call `ralph_control` with `action: "pause"`
- "Resume Ralph" → call `ralph_control` with `action: "resume"`

## On Completion

When the user asks for results or status shows the container stopped:
1. Call `ralph_result` with `artifact: "all"` to pull everything
2. Summarize: what was built (plan), what was reviewed (review findings), branch name
3. Suggest: "Check out the `ralph/<spec>` branch to see the changes, or I can show you specific artifacts"
4. Offer cleanup: "Want me to remove the container?"
```

- [ ] **Step 3: Write /ralph:build skill**

Create `plugin/skills/build/SKILL.md`:

```markdown
---
name: build
description: Launch Ralph's build mode — implement tasks from an existing implementation plan in a background Docker container. Requires a plan to exist first.
---

# Ralph Build

Launch Ralph in build mode to implement tasks from an existing implementation plan.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Check plan exists**: Read `.ralph/implementation_plan.md` using the Read tool. If it doesn't exist, tell the user: "No implementation plan found. Run `/ralph:full` to create one automatically, or create `.ralph/implementation_plan.md` manually."

3. **Pick spec**: Ask the user which spec to build from. Verify it exists.

4. **Confirm options**: Default 10 iterations. Let user adjust.

5. **Launch**: Call `ralph_start` with:
   - `spec`: chosen spec
   - `mode`: `"build"`
   - `workdir`: current repo root
   - `options`: as confirmed

6. **Report**: Same as /ralph:full — container ID, branch, how to check in.

## While Running / On Completion

Same interaction patterns as /ralph:full. On completion, summarize commits made and test results.
```

- [ ] **Step 4: Commit**

```bash
git add plugin/skills/setup/SKILL.md plugin/skills/full/SKILL.md plugin/skills/build/SKILL.md
git commit -m "feat(plugin): add setup, full, and build skills"
```

---

### Task 11: Skills — research, review, spec

**Files:**
- Create: `plugin/skills/research/SKILL.md`
- Create: `plugin/skills/review/SKILL.md`
- Create: `plugin/skills/spec/SKILL.md`

- [ ] **Step 1: Write /ralph:research skill**

Create `plugin/skills/research/SKILL.md`:

```markdown
---
name: research
description: Launch Ralph's deep research mode — parallel codebase and web research in a background Docker container. Use for investigating topics, understanding systems, or gathering context.
---

# Ralph Research

Launch Ralph in research mode for deep parallel investigation of a topic.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Gather topic**: Ask the user what they want to research. Get:
   - Research question or topic
   - Any specific areas to focus on
   - Context they already have

3. **Create seed**: Compose the seed content as a markdown document:
   ```
   # Research: <topic>

   ## Question
   <user's research question>

   ## Focus Areas
   <specific areas>

   ## Known Context
   <what user already knows>
   ```

4. **Choose name**: Ask the user for a short name for this research (used as branch name).

5. **Launch**: Call `ralph_start` with:
   - `spec`: the chosen name
   - `mode`: `"research"`
   - `workdir`: current repo root
   - `options`: `{ iterations: 10, seedContent: <the seed markdown> }`

6. **Report**: Container ID, branch, how to check in.

## On Completion

1. Call `ralph_result` with `artifact: "research"` to pull research outputs from `.ralph/references/`
2. Present a summary of findings organized by topic
3. Offer to show full research documents
```

- [ ] **Step 2: Write /ralph:review skill**

Create `plugin/skills/review/SKILL.md`:

```markdown
---
name: review
description: Launch Ralph's specialist code review — security, database, API, performance, UX, and QA reviewers analyze your code in a background Docker container.
---

# Ralph Review

Launch Ralph in review mode for multi-specialist code review.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Pick spec**: Ask the user which spec or branch to review. Verify the spec exists.

3. **Confirm options**: Default 10 iterations. Mention that review mode uses specialist reviewers: security, database, API, performance, UX, QA.

4. **Launch**: Call `ralph_start` with:
   - `spec`: chosen spec
   - `mode`: `"review"`
   - `workdir`: current repo root
   - `options`: as confirmed

5. **Report**: Container ID, branch, how to check in.

## On Completion

1. Call `ralph_result` with `artifact: "review"` to pull `.ralph/review.md`
2. Present findings organized by severity (BLOCKING, WARNING, INFO)
3. List which specialists contributed findings
4. If BLOCKING issues found, suggest: "Run `/ralph:full` with review-fix mode to address blocking issues"
```

- [ ] **Step 3: Write /ralph:spec skill**

Create `plugin/skills/spec/SKILL.md`:

```markdown
---
name: spec
description: Launch Ralph's interactive spec creation — gather requirements, research, draft, debate, and refine a specification in a background Docker container.
---

# Ralph Spec

Launch Ralph in spec mode to create a detailed specification through an iterative process.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Gather requirements**: Ask the user about what they want to build:
   - What is the feature or system?
   - What problem does it solve?
   - Any constraints or requirements?
   - Success criteria?

3. **Create seed**: Compose seed content:
   ```
   # Spec: <feature name>

   ## What
   <description of feature/system>

   ## Problem
   <what problem it solves>

   ## Constraints
   <any constraints>

   ## Success Criteria
   <how to know it's done>
   ```

4. **Choose name**: Ask for a short name for the spec.

5. **Launch**: Call `ralph_start` with:
   - `spec`: chosen name
   - `mode`: `"spec"`
   - `workdir`: current repo root
   - `options`: `{ iterations: 8, seedContent: <the seed markdown> }`

6. **Report**: Container ID, branch, how to check in.

## On Completion

1. Call `ralph_result` with `artifact: "spec"` to pull the generated spec
2. Present the full spec for user review
3. Ask if they want to proceed with implementation: "Ready to build this? Run `/ralph:full` with this spec"
```

- [ ] **Step 4: Commit**

```bash
git add plugin/skills/research/SKILL.md plugin/skills/review/SKILL.md plugin/skills/spec/SKILL.md
git commit -m "feat(plugin): add research, review, and spec skills"
```

---

### Task 12: Ralph monitor agent

**Files:**
- Create: `plugin/agents/ralph-monitor.md`

- [ ] **Step 1: Write ralph-monitor agent**

Create `plugin/agents/ralph-monitor.md`:

```markdown
---
name: ralph-monitor
description: Background monitor agent for Ralph containers — checks status and reports completion or failure
---

# Ralph Container Monitor

You are monitoring a Ralph container running in Docker. Your job is to check on it and report back when it completes or fails.

## Your task

You were given a container ID when dispatched. Periodically check its status:

1. Call `ralph_status` with the container ID
2. If `running: true` — wait and check again (use a reasonable interval)
3. If `running: false` and `exitCode: 0` — the container completed successfully:
   - Call `ralph_result` with `artifact: "all"` to pull outputs
   - Report back: branch name, what artifacts are available, brief summary of results
   - Suggest next steps based on the mode (e.g., "check out the branch", "review the findings")
4. If `running: false` and `exitCode != 0` — the container failed:
   - Call `ralph_logs` with `tail: 50` to get recent output
   - Report back: exit code, relevant error logs
   - Suggest: retry, check logs in detail, or debug

## Important
- Keep status checks infrequent — every 30-60 seconds is fine
- Don't flood the user with updates while the container is running
- Only report when there's a state change (started → completed, started → failed)
```

- [ ] **Step 2: Commit**

```bash
git add plugin/agents/ralph-monitor.md
git commit -m "feat(plugin): add ralph-monitor agent for background container monitoring"
```

---

### Task 13: End-to-end smoke test

**Files:**
- No new files — manual verification

- [ ] **Step 1: Verify plugin structure is complete**

```bash
find plugin -type f | sort
```

Expected: All files from the file structure section are present.

- [ ] **Step 2: Verify MCP server starts and lists tools**

```bash
cd plugin && echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | node mcp/server.js
```

Expected: JSON response listing ralph_setup, ralph_start, ralph_status, ralph_logs, ralph_steer, ralph_control, ralph_result.

- [ ] **Step 3: Test ralph_setup tool call**

```bash
cd plugin && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ralph_setup","arguments":{"workdir":"'"$(pwd)/.."'"}}}' | node mcp/server.js
```

Expected: JSON response with `ready` status and any `missing` items. Should correctly identify the Ralph repo as a git repo and check for Docker.

- [ ] **Step 4: Verify skills are well-formed**

Check each SKILL.md has valid frontmatter:

```bash
for f in plugin/skills/*/SKILL.md; do echo "=== $f ==="; head -5 "$f"; echo; done
```

Expected: Each file starts with `---`, `name:`, `description:`, `---`.

- [ ] **Step 5: Verify hooks are in place**

```bash
cat plugin/hooks/hooks.json
ls -la plugin/hooks/session-start
```

Expected: hooks.json has SessionStart configuration. session-start is executable.

- [ ] **Step 6: Commit any fixes from smoke testing**

```bash
git add -A plugin/
git commit -m "fix(plugin): address issues found during smoke testing"
```

Only commit if there were actual fixes needed. Skip if everything passed.

---

### Task 14: Gitignore and final commit

**Files:**
- Modify: `plugin/package.json` (verify dependencies installed correctly)

- [ ] **Step 1: Verify package-lock.json is committed**

```bash
ls plugin/package-lock.json
```

If missing, run `cd plugin && npm install` to generate it.

- [ ] **Step 2: Add plugin to .gitignore appropriately**

Add plugin-specific entries to `.gitignore`:

```bash
echo 'plugin/node_modules/' >> .gitignore
echo '.ralph/plugin-state.json' >> .gitignore
```

The `plugin-state.json` file contains transient runtime data (container IDs, timestamps) and should not be committed.

- [ ] **Step 3: Final commit**

```bash
git add .gitignore plugin/
git commit -m "feat(plugin): Ralph Claude Code plugin — complete initial implementation

Hybrid architecture with skills as guided entry points and MCP server
for Docker container orchestration. Includes:
- 7 MCP tools: setup, start, status, logs, steer, control, result
- 6 skills: setup, full, build, research, review, spec
- SessionStart hook for ambient container awareness
- Ralph monitor agent for background completion tracking"
```
