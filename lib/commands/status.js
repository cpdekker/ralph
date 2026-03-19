const { c, header, separator, info, error } = require('../utils/colors');
const { resolveContainer, containerReadFile } = require('../utils/container');

async function run(spec) {
  const result = resolveContainer(spec);

  if (!result) {
    error('No running Ralph containers found.');
    console.log(`  Run ${c('cyan', 'ralph full <spec>')} to start one.\n`);
    process.exit(1);
  }

  if (Array.isArray(result)) {
    error('Multiple Ralph containers running. Specify a spec:');
    result.forEach(name => console.log(`    ${c('cyan', name)}`));
    console.log('');
    process.exit(1);
  }

  const containerName = result;
  header(`Status: ${containerName}`);

  // Read state.json
  const stateRaw = containerReadFile(containerName, '.ralph/state.json');
  if (stateRaw) {
    try {
      const state = JSON.parse(stateRaw);
      info(`Spec:         ${state.spec_name}`);
      info(`Phase:        ${state.current_phase}`);
      info(`Iteration:    ${state.current_iteration}`);
      info(`Total iters:  ${state.total_iterations}`);
      info(`Failures:     ${state.consecutive_failures}`);
      info(`Errors:       ${state.error_count}`);
      info(`Last update:  ${state.last_update}`);
      if (state.current_task) {
        info(`Task:         ${state.current_task}`);
      }
      if (state.is_decomposed) {
        info(`Sub-spec:     ${state.current_subspec || 'none'}`);
      }
    } catch {
      console.log(stateRaw);
    }
  } else {
    info('No state.json found (Ralph may be between iterations or completed)');
  }

  console.log('');

  // Read plan progress
  const plan = containerReadFile(containerName, '.ralph/implementation_plan.md');
  if (plan) {
    const checked = (plan.match(/- \[x\]/gi) || []).length;
    const unchecked = (plan.match(/- \[ \]/g) || []).length;
    const total = checked + unchecked;
    const pct = total > 0 ? Math.round((checked / total) * 100) : 0;
    const bar = total > 0
      ? '[' + '#'.repeat(Math.round(pct / 5)) + '-'.repeat(20 - Math.round(pct / 5)) + ']'
      : '';
    info(`Plan progress: ${checked}/${total} tasks ${bar} ${pct}%`);
  }

  // Check pause state
  const paused = containerReadFile(containerName, '.ralph/pause');
  if (paused !== null) {
    console.log(`\n  ${c('yellow', '⏸  Ralph is PAUSED')}. Run ${c('cyan', 'ralph resume')} to continue.`);
  }

  // Check mailbox
  const mailbox = containerReadFile(containerName, '.ralph/mailbox.md');
  if (mailbox) {
    console.log(`\n  ${c('cyan', '📬 Pending mailbox directive')} (will be processed next iteration)`);
  }

  // Check mailbox reply
  const reply = containerReadFile(containerName, '.ralph/mailbox-reply.md');
  if (reply) {
    console.log(`\n  ${c('green', '📨 Mailbox reply available:')}`);
    separator();
    console.log(reply);
    separator();
  }

  console.log('');
}

module.exports = { run };
