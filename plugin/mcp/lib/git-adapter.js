import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';

const require = createRequire(import.meta.url);
const libPath = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
const coreGit = require(path.join(libPath, 'utils', 'git.js'));

export const { getRemoteUrl, getBranch, isGitRepo } = coreGit;

export function prepareSpecBranch(workdir, spec, seedContent = null, seedFilename = 'spec_seed.md') {
  const branch = `ralph/${spec}`;
  const worktreeDir = path.join(os.tmpdir(), `ralph-worktree-${spec}-${Date.now()}`);

  try {
    let branchExists = false;
    try {
      execFileSync('git', ['ls-remote', '--exit-code', '--heads', 'origin', branch], { cwd: workdir });
      branchExists = true;
    } catch { /* branch doesn't exist remotely */ }

    if (!branchExists) {
      try {
        execFileSync('git', ['rev-parse', '--verify', branch], { cwd: workdir });
        branchExists = true;
      } catch { /* branch doesn't exist locally either */ }
    }

    if (branchExists) {
      execFileSync('git', ['worktree', 'add', worktreeDir, branch], { cwd: workdir });
    } else {
      const baseBranch = getBranch(workdir) || 'main';
      execFileSync('git', ['worktree', 'add', '-b', branch, worktreeDir, baseBranch], { cwd: workdir });
    }

    if (seedContent) {
      const ralphSpecsDir = path.join(worktreeDir, '.ralph', 'specs');
      fs.mkdirSync(ralphSpecsDir, { recursive: true });
      fs.writeFileSync(path.join(worktreeDir, '.ralph', seedFilename), seedContent);

      execFileSync('git', ['add', '.'], { cwd: worktreeDir });
      execFileSync('git', ['commit', '-m', `Ralph: add ${seedFilename} for ${spec}`], { cwd: worktreeDir });
    }

    try {
      execFileSync('git', ['push', '-u', 'origin', branch], { cwd: worktreeDir });
    } catch {
      // Push may fail if no remote — that's ok
    }

    return { branch };
  } finally {
    try {
      execFileSync('git', ['worktree', 'remove', '--force', worktreeDir], { cwd: workdir });
    } catch {
      // Best-effort cleanup
    }
  }
}
