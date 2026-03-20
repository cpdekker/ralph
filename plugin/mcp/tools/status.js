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
