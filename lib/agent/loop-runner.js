const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const { createWorktree, getWorktreePath, removeWorktree, worktreeExists, worktreesDir } = require('../utils/worktree');
const { libDir, ralphDir, toDockerPath } = require('../utils/paths');
const { getImageName, ensureImage } = require('../utils/docker');

// In-memory registry of running loop processes
const runningLoops = new Map();

/**
 * Convert a Windows path to a bash-compatible path.
 * Git Bash on Windows uses /c/Users/... style paths.
 */
function toBashPath(p) {
  if (process.platform !== 'win32') return p;
  return p
    .replace(/\\/g, '/')
    .replace(/^([A-Za-z]):/, (_, letter) => `/${letter.toLowerCase()}`);
}

/**
 * Generate a Docker container name for a spec.
 */
function containerName(spec) {
  const repoName = path.basename(process.cwd()).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const specSuffix = spec.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  return `ralph-${repoName}-${specSuffix}`;
}

/**
 * Check if a Docker container is running.
 */
function isContainerRunning(name) {
  try {
    const result = execSync(`docker inspect -f "{{.State.Running}}" ${name}`, {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
    return result === 'true';
  } catch {
    return false;
  }
}

/**
 * Check if a Docker container exists (running or stopped).
 */
function containerExists(name) {
  try {
    execSync(`docker inspect ${name}`, { stdio: ['pipe', 'pipe', 'pipe'] });
    return true;
  } catch {
    return false;
  }
}

/**
 * Start a loop in a worktree using Docker.
 * Creates the worktree if needed, then spawns a detached Docker container.
 */
function startLoop(spec, mode = 'build', opts = {}) {
  const { iterations = getDefaultIterations(mode), verbose = false, local = false } = opts;

  if (runningLoops.has(spec)) {
    const existing = runningLoops.get(spec);
    if (existing.container && isContainerRunning(existing.container)) {
      throw new Error(`Loop for "${spec}" is already running (container ${existing.container})`);
    }
    if (existing.pid && isProcessAlive(existing.pid)) {
      throw new Error(`Loop for "${spec}" is already running (PID ${existing.pid})`);
    }
    // Dead process — clean up registry
    runningLoops.delete(spec);
  }

  // Create worktree (no-op if already exists)
  const wtPath = createWorktree(spec);
  const wtRalph = path.join(wtPath, '.ralph');

  // Ensure log directory
  fs.mkdirSync(wtRalph, { recursive: true });

  const logPath = path.join(wtRalph, 'loop.log');
  const pidPath = path.join(wtRalph, 'loop.pid');

  if (local) {
    return startLoopLocal(spec, mode, iterations, verbose, wtPath, wtRalph, logPath, pidPath);
  }

  return startLoopDocker(spec, mode, iterations, verbose, wtPath, wtRalph, logPath, pidPath);
}

/**
 * Start a loop via Docker (default, sandboxed).
 */
function startLoopDocker(spec, mode, iterations, verbose, wtPath, wtRalph, logPath, pidPath) {
  const imageName = getImageName();
  ensureImage(imageName);

  const cName = containerName(spec);

  // Remove any stopped container with the same name
  if (containerExists(cName)) {
    try { execSync(`docker rm -f ${cName}`, { stdio: 'ignore' }); } catch {}
  }

  const envFile = path.join(ralphDir(), '.env');
  const wtDockerPath = toDockerPath(wtPath);
  const libDockerPath = toDockerPath(libDir);

  const dockerArgs = [
    'run', '-d',
    '--name', cName,
  ];

  // Add env file if it exists
  if (fs.existsSync(envFile)) {
    dockerArgs.push('--env-file', envFile);
  }

  // Mount worktree as workspace and lib as read-only
  dockerArgs.push(
    '-v', `${wtDockerPath}:/workspace`,
    '-v', `${libDockerPath}:/ralph-lib:ro`,
    '-w', '/workspace',
    imageName,
    'bash', '/ralph-lib/scripts/loop.sh',
    spec,
    mode,
    String(iterations),
  );

  if (verbose) dockerArgs.push('--verbose');

  // Run docker container
  const containerId = execSync(`docker ${dockerArgs.join(' ')}`, {
    encoding: 'utf-8',
    cwd: wtPath,
  }).trim();

  // Write container name to pid file (reusing pid file for container tracking)
  fs.writeFileSync(pidPath, `container:${cName}`);

  // Start tailing logs to the log file in background
  const logFd = fs.openSync(logPath, 'w');
  const logProcess = spawn('docker', ['logs', '-f', cName], {
    stdio: ['ignore', logFd, logFd],
    detached: true,
    shell: false,
  });
  logProcess.unref();
  fs.closeSync(logFd);

  const entry = {
    spec,
    mode,
    iterations,
    container: cName,
    containerId: containerId.slice(0, 12),
    pid: logProcess.pid,
    wtPath,
    logPath,
    pidPath,
    startedAt: new Date().toISOString(),
  };

  runningLoops.set(spec, entry);
  return entry;
}

/**
 * Start a loop locally via bash (opt-in, no Docker).
 */
function startLoopLocal(spec, mode, iterations, verbose, wtPath, wtRalph, logPath, pidPath) {
  const loopScript = path.join(libDir, 'scripts', 'loop.sh');
  const bashLoopScript = toBashPath(loopScript);
  const args = [bashLoopScript, spec, mode, String(iterations)];
  if (verbose) args.push('--verbose');

  // Build env from .ralph/.env in worktree
  const env = { ...process.env, RALPH_LIB_DIR: toBashPath(libDir) };
  const envFile = path.join(wtRalph, '.env');
  if (fs.existsSync(envFile)) {
    const lines = fs.readFileSync(envFile, 'utf-8').split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith('#')) {
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          env[trimmed.slice(0, eqIdx)] = trimmed.slice(eqIdx + 1);
        }
      }
    }
  }

  const logFd = fs.openSync(logPath, 'w');

  const child = spawn('bash', args, {
    cwd: wtPath,
    env,
    stdio: ['ignore', logFd, logFd],
    detached: true,
    shell: false,
  });

  child.on('error', (err) => {
    try {
      fs.appendFileSync(logPath, `\nSPAWN ERROR: ${err.message}\n`);
    } catch {}
  });

  child.unref();
  fs.closeSync(logFd);

  fs.writeFileSync(pidPath, String(child.pid));

  const entry = {
    spec,
    mode,
    iterations,
    pid: child.pid,
    container: null,
    wtPath,
    logPath,
    pidPath,
    startedAt: new Date().toISOString(),
  };

  runningLoops.set(spec, entry);
  return entry;
}

/**
 * Stop a running loop.
 */
function stopLoop(spec, { removeWt = false } = {}) {
  const entry = runningLoops.get(spec);
  let stopped = false;

  // Try to stop Docker container first
  const cName = entry?.container || readContainerName(spec);
  if (cName) {
    try {
      if (isContainerRunning(cName)) {
        execSync(`docker stop ${cName}`, { stdio: 'ignore', timeout: 10000 });
        stopped = true;
      }
      // Remove the stopped container
      try { execSync(`docker rm ${cName}`, { stdio: 'ignore' }); } catch {}
    } catch {}
  }

  // Also kill any local PID (e.g., the log-tailing process, or a local-mode loop)
  const pid = entry?.pid || readPid(spec);
  if (pid && isProcessAlive(pid)) {
    try {
      process.kill(pid, 'SIGTERM');
      setTimeout(() => {
        if (isProcessAlive(pid)) {
          try { process.kill(pid, 'SIGKILL'); } catch {}
        }
      }, 3000);
      stopped = true;
    } catch {}
  }

  runningLoops.delete(spec);

  if (removeWt) {
    removeWorktree(spec);
  }

  return { stopped: true, pid, container: cName };
}

/**
 * Get status for a specific loop or all loops.
 */
function getLoopStatus(spec) {
  if (spec) {
    return getStatusForSpec(spec);
  }

  // All loops: combine in-memory registry with on-disk worktrees
  const statuses = [];
  const seen = new Set();

  // First, check in-memory registry
  for (const [name, entry] of runningLoops) {
    seen.add(name);
    statuses.push(getStatusForSpec(name));
  }

  // Then check worktrees that might have loops from previous sessions
  const wtDir = worktreesDir();
  if (fs.existsSync(wtDir)) {
    for (const dir of fs.readdirSync(wtDir, { withFileTypes: true })) {
      if (dir.isDirectory() && !seen.has(dir.name)) {
        statuses.push(getStatusForSpec(dir.name));
      }
    }
  }

  return statuses;
}

function getStatusForSpec(spec) {
  const wtPath = getWorktreePath(spec);
  const wtRalph = path.join(wtPath, '.ralph');
  const entry = runningLoops.get(spec);

  const status = {
    spec,
    worktree: worktreeExists(spec) ? wtPath : null,
    running: false,
    pid: null,
    container: null,
    mode: entry?.mode || null,
    iterations: entry?.iterations || null,
    startedAt: entry?.startedAt || null,
    state: null,
  };

  // Check Docker container
  const cName = entry?.container || readContainerName(spec);
  if (cName) {
    status.container = cName;
    status.running = isContainerRunning(cName);
  }

  // Check PID (for local mode or log tailer)
  if (!status.running) {
    const pid = entry?.pid || readPid(spec);
    if (pid) {
      status.pid = pid;
      // Only mark as running from PID if no container was found
      if (!cName) {
        status.running = isProcessAlive(pid);
      }
    }
  }

  // Read state.json if present
  const statePath = path.join(wtRalph, 'state.json');
  if (fs.existsSync(statePath)) {
    try {
      status.state = JSON.parse(fs.readFileSync(statePath, 'utf-8'));
    } catch {}
  }

  return status;
}

/**
 * Get recent log lines for a loop.
 */
function getLoopLogs(spec, lines = 50) {
  // Try reading from the log file first
  const logPath = path.join(getWorktreePath(spec), '.ralph', 'loop.log');
  if (fs.existsSync(logPath)) {
    const content = fs.readFileSync(logPath, 'utf-8');
    const allLines = content.split('\n');
    return allLines.slice(-lines).join('\n');
  }

  // Fall back to docker logs if container exists
  const cName = readContainerName(spec) || containerName(spec);
  try {
    return execSync(`docker logs --tail ${lines} ${cName}`, {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch {
    return '(no log file or container found)';
  }
}

/**
 * Read container name from pid file on disk.
 * The pid file may contain "container:<name>" for Docker loops.
 */
function readContainerName(spec) {
  const pidPath = path.join(getWorktreePath(spec), '.ralph', 'loop.pid');
  if (fs.existsSync(pidPath)) {
    try {
      const content = fs.readFileSync(pidPath, 'utf-8').trim();
      if (content.startsWith('container:')) {
        return content.slice('container:'.length);
      }
    } catch {}
  }
  return null;
}

/**
 * Read PID from file on disk.
 */
function readPid(spec) {
  const pidPath = path.join(getWorktreePath(spec), '.ralph', 'loop.pid');
  if (fs.existsSync(pidPath)) {
    try {
      const content = fs.readFileSync(pidPath, 'utf-8').trim();
      // Skip container entries
      if (content.startsWith('container:')) return null;
      return parseInt(content);
    } catch {}
  }
  return null;
}

/**
 * Check if a process is alive.
 */
function isProcessAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function getDefaultIterations(mode) {
  const defaults = {
    plan: 5, build: 10, review: 10, 'review-fix': 5,
    debug: 1, full: 10, decompose: 1, spec: 8, insights: 1,
  };
  return defaults[mode] || 10;
}

module.exports = {
  startLoop,
  stopLoop,
  getLoopStatus,
  getLoopLogs,
  isProcessAlive,
  runningLoops,
};
