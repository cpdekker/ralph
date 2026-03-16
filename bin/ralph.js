#!/usr/bin/env node
const { Command } = require('commander');
const path = require('path');
const pkg = require('../package.json');

const program = new Command();

program
  .name('ralph')
  .description('Ralph Wiggum - AI agent that autonomously implements features using Claude Code')
  .version(pkg.version);

// Common options shared by mode commands
function addModeOptions(cmd) {
  return cmd
    .option('-n, --iterations <number>', 'number of iterations')
    .option('-v, --verbose', 'show full output')
    .option('-b, --background', 'run in background (Ralph clones repo)')
    .option('-l, --local', 'run locally via bash (no Docker)')
    .option('-y, --yes', 'skip interactive prompts, use defaults')
    .option('--insights', 'enable insights collection and analysis')
    .option('--insights-github', 'also create GitHub issues for findings');
}

// ralph init
program
  .command('init')
  .description('Initialize Ralph in the current repository')
  .action(async () => {
    const { run } = require('../lib/commands/init');
    await run();
  });

// ralph plan <spec> [iterations]
addModeOptions(
  program
    .command('plan [spec]')
    .description('Analyze codebase and create implementation plan')
).action(async (spec, opts) => {
  if (!opts.iterations) opts.iterations = '5';
  const { run } = require('../lib/commands/mode');
  await run(spec, 'plan', opts);
});

// ralph build <spec> [iterations]
addModeOptions(
  program
    .command('build [spec]')
    .description('Implement tasks from the implementation plan')
).action(async (spec, opts) => {
  if (!opts.iterations) opts.iterations = '10';
  const { run } = require('../lib/commands/mode');
  await run(spec, 'build', opts);
});

// ralph review <spec>
addModeOptions(
  program
    .command('review [spec]')
    .description('Review implementation for bugs and issues')
).action(async (spec, opts) => {
  if (!opts.iterations) opts.iterations = '10';
  const { run } = require('../lib/commands/mode');
  await run(spec, 'review', opts);
});

// ralph review-fix <spec>
addModeOptions(
  program
    .command('review-fix [spec]')
    .description('Fix issues identified during review')
).action(async (spec, opts) => {
  if (!opts.iterations) opts.iterations = '5';
  const { run } = require('../lib/commands/mode');
  await run(spec, 'review-fix', opts);
});

// ralph full <spec>
addModeOptions(
  program
    .command('full [spec]')
    .description('Full cycle: plan -> build -> review -> check (repeats until complete)')
    .option('-f, --foreground', 'force foreground mode')
).action(async (spec, opts) => {
  if (!opts.iterations) opts.iterations = '10';
  const { run } = require('../lib/commands/mode');
  // Full mode defaults to background unless --foreground or --local
  if (!opts.foreground && !opts.local && opts.background === undefined) {
    opts.background = true;
  }
  await run(spec, 'full', opts);
});

// ralph debug <spec>
program
  .command('debug [spec]')
  .description('Single iteration, verbose, no commits')
  .option('-l, --local', 'run locally via bash (no Docker)')
  .option('-y, --yes', 'skip interactive prompts, use defaults')
  .option('--insights', 'enable insights collection and analysis')
  .option('--insights-github', 'also create GitHub issues for findings')
  .action(async (spec, opts) => {
    const { run } = require('../lib/commands/mode');
    await run(spec, 'debug', { ...opts, iterations: '1', verbose: true });
  });

// ralph decompose <spec>
program
  .command('decompose [spec]')
  .description('Break large spec into ordered sub-specs')
  .option('-l, --local', 'run locally via bash (no Docker)')
  .option('-y, --yes', 'skip interactive prompts, use defaults')
  .option('--insights', 'enable insights collection and analysis')
  .option('--insights-github', 'also create GitHub issues for findings')
  .action(async (spec, opts) => {
    const { run } = require('../lib/commands/mode');
    await run(spec, 'decompose', { ...opts, iterations: '1', verbose: true });
  });

// ralph spec [name]
addModeOptions(
  program
    .command('spec [name]')
    .description('Create spec interactively: gather -> research -> draft -> review')
).action(async (name, opts) => {
  if (!opts.iterations) opts.iterations = '8';
  const { run } = require('../lib/commands/mode');
  await run(name, 'spec', opts);
});

// ralph insights [spec]
program
  .command('insights [spec]')
  .description('Run insights analysis on existing iteration logs')
  .option('--github', 'create GitHub issues for HIGH/CRITICAL findings')
  .option('-v, --verbose', 'show full output')
  .option('-y, --yes', 'skip interactive prompts')
  .action(async (spec, opts) => {
    const { run } = require('../lib/commands/mode');
    await run(spec, 'insights', { ...opts, iterations: '1', verbose: true, insights: true, insightsGithub: !!opts.github });
  });

// ralph parallel-full <spec> [-j N]
program
  .command('parallel-full [spec]')
  .description('Run decomposed sub-specs in parallel containers')
  .option('-j, --parallel <number>', 'max parallel sub-specs', '3')
  .option('-n, --iterations <number>', 'max iterations per sub-spec', '100')
  .option('-v, --verbose', 'verbose output')
  .action(async (spec, opts) => {
    const { run } = require('../lib/commands/parallel-full');
    await run(spec, opts);
  });

// ralph run (agent mode, or --legacy for old interactive)
program
  .command('run')
  .description('Launch Ralph agent mode (or --legacy for old interactive menu)')
  .option('--legacy', 'use old interactive menu instead of agent mode')
  .action(async (opts) => {
    if (opts.legacy) {
      const { run } = require('../lib/commands/interactive');
      await run();
    } else {
      const { run } = require('../lib/commands/agent');
      await run();
    }
  });

// ralph update
program
  .command('update')
  .description('Update Ralph to the latest version')
  .action(async () => {
    const { run } = require('../lib/commands/update');
    await run();
  });

// Default to agent mode when no command given
program.action(async () => {
  const { run } = require('../lib/commands/agent');
  await run();
});

program.parseAsync(process.argv).catch((err) => {
  const { error } = require('../lib/utils/colors');
  error(err.message);
  process.exit(1);
});
