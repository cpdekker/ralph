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
