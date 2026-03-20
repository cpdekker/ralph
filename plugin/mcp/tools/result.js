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
    execFileSync('git', ['fetch', 'origin', branch], { cwd: workdir, timeout: 30000 });

    if (singleFilePaths[artifact]) {
      return execFileSync('git', ['show', `origin/${branch}:${singleFilePaths[artifact]}`], {
        cwd: workdir, encoding: 'utf-8', timeout: 10000
      });
    }

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
    let content = readFromContainer(meta.containerName, art);

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
