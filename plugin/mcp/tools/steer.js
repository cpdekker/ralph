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
