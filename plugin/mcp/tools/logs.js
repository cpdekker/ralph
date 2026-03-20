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
      maxBuffer: 1024 * 1024
    });

    updateContainer(containerId, { lastLogOffset: new Date().toISOString() });

    return {
      content: [{ type: 'text', text: logs || '(no logs yet)' }]
    };
  } catch (err) {
    return errors.containerNotFound(containerId);
  }
}
