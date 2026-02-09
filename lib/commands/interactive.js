const readline = require('readline');
const { c } = require('../utils/colors');
const { isInitialized, getAvailableSpecs, validateSpec, getSpecDetails } = require('../utils/paths');
const { run: runMode } = require('./mode');

async function run() {
  if (!isInitialized()) {
    console.log(c('red', '\n  Error: .ralph directory not found. Run "ralph init" first.\n'));
    process.exit(1);
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (prompt) => new Promise((resolve) => rl.question(prompt, resolve));

  console.log(`\n${c('yellow', '  Ralph Wiggum - Interactive Mode')}\n`);

  const availableSpecs = getAvailableSpecs();
  let spec = '';
  let mode = '';

  // Select spec
  if (availableSpecs.length === 1) {
    spec = availableSpecs[0];
    console.log(`${c('green', `  Auto-selected spec: ${spec}`)}\n`);
  } else if (availableSpecs.length > 1) {
    console.log('  Available specs:');
    availableSpecs.forEach((s, i) => {
      const details = getSpecDetails(s);
      const suffix = details ? ` ${c('cyan', `[${details.complete}/${details.total} sub-specs]`)}` : '';
      console.log(`    ${i + 1}. ${s}${suffix}`);
    });
    console.log('');

    while (!spec) {
      const input = await question('  Enter spec name (or number): ');
      const trimmed = input.trim();
      const num = parseInt(trimmed);
      if (!isNaN(num) && num >= 1 && num <= availableSpecs.length) {
        spec = availableSpecs[num - 1];
      } else if (trimmed) {
        if (validateSpec(trimmed)) {
          spec = trimmed;
        } else {
          console.log(c('red', `  Spec not found: .ralph/specs/${trimmed}.md`));
        }
      }
    }
  } else {
    console.log(c('yellow', '  No specs found. Create one at .ralph/specs/<name>.md or use "ralph spec <name>".\n'));
    rl.close();
    process.exit(1);
  }

  // Select mode
  console.log('  Modes:');
  console.log('    1. plan       - Analyze codebase and create implementation plan');
  console.log('    2. build      - Implement tasks from the plan');
  console.log('    3. review     - Review implementation for bugs and issues');
  console.log('    4. review-fix - Fix issues identified during review');
  console.log('    5. debug      - Single iteration, verbose, no commits');
  console.log('    6. full       - Full cycle: plan → build → review → check');
  console.log('    7. decompose  - Break large spec into ordered sub-specs');
  console.log('    8. spec       - Create spec interactively');
  console.log('    9. insights   - Analyze iteration logs for patterns and improvements');
  console.log('');

  const modeMap = {
    '1': 'plan', 'plan': 'plan',
    '2': 'build', 'build': 'build',
    '3': 'review', 'review': 'review',
    '4': 'review-fix', 'review-fix': 'review-fix',
    '5': 'debug', 'debug': 'debug',
    '6': 'full', 'full': 'full', 'yolo': 'full',
    '7': 'decompose', 'decompose': 'decompose',
    '8': 'spec', 'spec': 'spec',
    '9': 'insights', 'insights': 'insights',
  };

  const defaultIterations = {
    plan: '5', build: '10', review: '10', 'review-fix': '5',
    debug: '1', full: '10', decompose: '1', spec: '8', insights: '1',
  };

  while (!mode) {
    const input = await question('  Select mode [1-9 or name] (default: build): ');
    const trimmed = input.trim().toLowerCase();
    mode = modeMap[trimmed] || (trimmed === '' ? 'build' : null);
    if (!mode) console.log(c('red', '  Invalid selection. Enter 1-9 or mode name.'));
  }

  rl.close();

  const background = mode === 'full' ? true : undefined;
  const modeOpts = {
    iterations: defaultIterations[mode],
    background,
  };
  if (mode === 'insights') {
    modeOpts.verbose = true;
    modeOpts.insights = true;
  }

  await runMode(spec, mode, modeOpts);
}

module.exports = { run };
