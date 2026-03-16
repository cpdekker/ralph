const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { repoDir, ralphDir } = require('./paths');

/**
 * Get the absolute path to the worktrees directory.
 * Worktrees are stored alongside the project (sibling directory)
 * to avoid interfering with the project's own build/tooling.
 *
 * Example: /repos/my-project → /repos/my-project-ralph-worktrees/
 */
function worktreesDir() {
  const root = repoDir();
  const repoName = path.basename(root);
  return path.join(path.dirname(root), `${repoName}-ralph-worktrees`);
}

/**
 * Get the absolute path to a specific worktree.
 */
function getWorktreePath(spec) {
  return path.join(worktreesDir(), spec);
}

/**
 * Get the branch name for a spec.
 */
function branchName(spec) {
  return `ralph/${spec}`;
}

/**
 * Ensure the worktrees directory exists.
 */
function ensureWorktreesDir() {
  const dir = worktreesDir();
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

/**
 * Check if a worktree already exists for a spec.
 */
function worktreeExists(spec) {
  return fs.existsSync(getWorktreePath(spec));
}

/**
 * Create a git worktree for a spec.
 * Creates branch ralph/<spec> from current HEAD if it doesn't exist,
 * or checks out the existing branch.
 */
function createWorktree(spec) {
  const root = repoDir();
  const wtPath = getWorktreePath(spec);
  const branch = branchName(spec);

  if (worktreeExists(spec)) {
    return wtPath;
  }

  ensureWorktreesDir();

  // Check if the branch already exists locally
  let branchExists = false;
  try {
    execSync(`git show-ref --verify --quiet refs/heads/${branch}`, { cwd: root, stdio: 'ignore' });
    branchExists = true;
  } catch {}

  // Check remote if not local
  if (!branchExists) {
    try {
      execSync(`git ls-remote --exit-code --heads origin ${branch}`, { cwd: root, stdio: 'ignore' });
      // Fetch the remote branch so we can check it out
      execSync(`git fetch origin ${branch}`, { cwd: root, stdio: 'ignore' });
      branchExists = true;
    } catch {}
  }

  if (branchExists) {
    execSync(`git worktree add "${wtPath}" ${branch}`, { cwd: root, stdio: 'pipe' });
  } else {
    execSync(`git worktree add -b ${branch} "${wtPath}"`, { cwd: root, stdio: 'pipe' });
  }

  // Copy .ralph directory essentials into the worktree
  copyRalphFiles(wtPath);

  return wtPath;
}

/**
 * Copy essential .ralph files into a worktree so loop.sh can find them.
 */
function copyRalphFiles(wtPath) {
  const rd = ralphDir();
  const wtRalph = path.join(wtPath, '.ralph');

  // Ensure .ralph dir exists in worktree
  fs.mkdirSync(path.join(wtRalph, 'specs'), { recursive: true });
  fs.mkdirSync(path.join(wtRalph, 'insights', 'iteration_logs'), { recursive: true });

  // Copy .env if it exists (needed for API keys)
  const envSrc = path.join(rd, '.env');
  if (fs.existsSync(envSrc)) {
    fs.copyFileSync(envSrc, path.join(wtRalph, '.env'));
  }

  // Copy AGENTS.md
  const agentsSrc = path.join(rd, 'AGENTS.md');
  if (fs.existsSync(agentsSrc)) {
    fs.copyFileSync(agentsSrc, path.join(wtRalph, 'AGENTS.md'));
  }

  // Copy all specs
  const specsDir = path.join(rd, 'specs');
  if (fs.existsSync(specsDir)) {
    for (const file of fs.readdirSync(specsDir)) {
      fs.copyFileSync(path.join(specsDir, file), path.join(wtRalph, 'specs', file));
    }
  }

  // Copy prompts if they exist locally (overrides)
  const promptsDir = path.join(rd, 'prompts');
  if (fs.existsSync(promptsDir)) {
    copyDirRecursive(promptsDir, path.join(wtRalph, 'prompts'));
  }

  // Copy guardrails if it exists
  const guardrails = path.join(rd, 'guardrails.md');
  if (fs.existsSync(guardrails)) {
    fs.copyFileSync(guardrails, path.join(wtRalph, 'guardrails.md'));
  }

  // Copy implementation_plan.md template
  const plan = path.join(rd, 'implementation_plan.md');
  if (fs.existsSync(plan)) {
    fs.copyFileSync(plan, path.join(wtRalph, 'implementation_plan.md'));
  }

  // Copy user-review.md template
  const userReview = path.join(rd, 'user-review.md');
  if (fs.existsSync(userReview)) {
    fs.copyFileSync(userReview, path.join(wtRalph, 'user-review.md'));
  }
}

/**
 * Recursively copy a directory.
 */
function copyDirRecursive(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirRecursive(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

/**
 * Remove a worktree for a spec.
 */
function removeWorktree(spec) {
  const root = repoDir();
  const wtPath = getWorktreePath(spec);

  if (!worktreeExists(spec)) {
    return;
  }

  try {
    execSync(`git worktree remove "${wtPath}" --force`, { cwd: root, stdio: 'pipe' });
  } catch {
    // If git worktree remove fails, try manual cleanup
    try {
      fs.rmSync(wtPath, { recursive: true, force: true });
      execSync('git worktree prune', { cwd: root, stdio: 'pipe' });
    } catch {}
  }
}

/**
 * List all Ralph worktrees with their status.
 * Returns array of { spec, path, branch, head }.
 */
function listWorktrees() {
  const root = repoDir();
  const wtDir = worktreesDir();

  if (!fs.existsSync(wtDir)) {
    return [];
  }

  const entries = fs.readdirSync(wtDir, { withFileTypes: true })
    .filter(e => e.isDirectory())
    .map(e => {
      const wtPath = path.join(wtDir, e.name);
      let branch = '';
      let head = '';
      try {
        branch = execSync('git branch --show-current', { cwd: wtPath, encoding: 'utf-8' }).trim();
      } catch {}
      try {
        head = execSync('git log --oneline -1', { cwd: wtPath, encoding: 'utf-8' }).trim();
      } catch {}
      return {
        spec: e.name,
        path: wtPath,
        branch,
        head,
      };
    });

  return entries;
}

module.exports = {
  worktreesDir,
  getWorktreePath,
  branchName,
  ensureWorktreesDir,
  worktreeExists,
  createWorktree,
  removeWorktree,
  listWorktrees,
  copyRalphFiles,
};
