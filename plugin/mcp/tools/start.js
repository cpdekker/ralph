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

  if (!isGitRepo(workdir)) return errors.noGitRepo();

  const imageName = getImageName(workdir);
  if (!imageExists(workdir, imageName)) return errors.imageNotFound(imageName);

  const repoUrl = getRemoteUrl(workdir);
  if (!repoUrl) {
    return ralphError('NO_REMOTE', 'No git remote "origin" configured', 'Add a git remote: git remote add origin <url>');
  }

  const seedFilename = mode === 'research' ? 'research_seed.md' : 'spec_seed.md';
  const { branch } = prepareSpecBranch(workdir, spec, options.seedContent || null, seedFilename);

  const repoName = path.basename(workdir).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const shortHash = crypto.randomBytes(4).toString('hex');
  const containerName = `ralph-${repoName}-${spec}-${shortHash}`.replace(/[^a-z0-9-]/g, '-');

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

  if (options.verbose) dockerArgs.push('--verbose');

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
