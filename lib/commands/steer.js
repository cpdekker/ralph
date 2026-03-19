const { c, error, info } = require('../utils/colors');
const { resolveContainer, containerReadFile, containerWriteFile } = require('../utils/container');

async function run(message, spec) {
  if (!message || !message.trim()) {
    error('Please provide a message. Usage: ralph steer "your directive here"');
    process.exit(1);
  }

  const result = resolveContainer(spec);

  if (!result) {
    error('No running Ralph containers found.');
    process.exit(1);
  }

  if (Array.isArray(result)) {
    error('Multiple Ralph containers running. Use --spec to target one:');
    result.forEach(name => console.log(`    ${c('cyan', name)}`));
    process.exit(1);
  }

  const containerName = result;

  // Check if there's already a pending mailbox
  const existing = containerReadFile(containerName, '.ralph/mailbox.md');
  if (existing) {
    console.log(c('yellow', '  Warning: There is already a pending directive. It will be overwritten.\n'));
  }

  // Read current state for context
  let stateContext = '';
  const stateRaw = containerReadFile(containerName, '.ralph/state.json');
  if (stateRaw) {
    try {
      const state = JSON.parse(stateRaw);
      stateContext = `Iteration ${state.current_iteration}, ${state.current_phase} phase`;
    } catch {}
  }

  const timestamp = new Date().toISOString();
  const mailboxContent = `# User Directive
**Time**: ${timestamp}
**Context**: ${stateContext || 'unknown'}

## Directive
${message.trim()}

## Instructions
Please read this directive and take appropriate action. This may include:
- Modifying the implementation plan
- Adjusting your approach for upcoming iterations
- Answering a question (write response to .ralph/mailbox-reply.md)
- Updating the spec or review checklist

After processing, continue with your normal work.
`;

  if (containerWriteFile(containerName, '.ralph/mailbox.md', mailboxContent)) {
    console.log(`  ${c('green', '✓')} Directive sent to Ralph.`);
    info('Ralph will process it at the start of the next iteration.');
    console.log('');
  } else {
    error('Failed to send directive to container.');
    process.exit(1);
  }
}

module.exports = { run };
