const { execSync } = require('child_process');
const { c, error } = require('../utils/colors');
const { resolveContainer, containerReadFile } = require('../utils/container');

async function run(spec, action) {
  const result = resolveContainer(spec);

  if (!result) {
    error('No running Ralph containers found.');
    process.exit(1);
  }

  if (Array.isArray(result)) {
    error('Multiple Ralph containers running. Specify a spec:');
    result.forEach(name => console.log(`    ${c('cyan', name)}`));
    process.exit(1);
  }

  const containerName = result;

  if (action === 'pause') {
    // Check if already paused
    const existing = containerReadFile(containerName, '.ralph/pause');
    if (existing !== null) {
      console.log(`  ${c('yellow', '⏸  Ralph is already paused.')}`);
      process.exit(0);
    }

    try {
      execSync(`docker exec ${containerName} touch .ralph/pause`, {
        encoding: 'utf-8',
        timeout: 5000,
      });
      console.log(`  ${c('yellow', '⏸  Ralph will pause after the current iteration completes.')}`);
      console.log(`  Run ${c('cyan', 'ralph resume')} to continue.\n`);
    } catch (err) {
      error(`Failed to pause: ${err.message}`);
      process.exit(1);
    }
  } else if (action === 'resume') {
    // Check if actually paused
    const existing = containerReadFile(containerName, '.ralph/pause');
    if (existing === null) {
      console.log(`  ${c('green', '▶  Ralph is not paused.')}`);
      process.exit(0);
    }

    try {
      execSync(`docker exec ${containerName} rm -f .ralph/pause`, {
        encoding: 'utf-8',
        timeout: 5000,
      });
      console.log(`  ${c('green', '▶  Ralph resumed!')}\n`);
    } catch (err) {
      error(`Failed to resume: ${err.message}`);
      process.exit(1);
    }
  }
}

module.exports = { run };
