const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { c, error } = require('../utils/colors');
const {
  isInitialized, ralphDir, repoDir, getAvailableSpecs, validateSpec,
  toDockerPath, libDir,
} = require('../utils/paths');
const { getRemoteUrl, getBranch } = require('../utils/git');
const { getImageName, ensureImage } = require('../utils/docker');

// Track running Docker process for cleanup
let dockerProcess = null;
let signalRl = null;

function cleanup(signal) {
  console.log(`\n${c('yellow', `Received ${signal}, shutting down...`)}`);
  if (dockerProcess) {
    try {
      dockerProcess.kill('SIGTERM');
      setTimeout(() => {
        if (dockerProcess && !dockerProcess.killed) {
          console.log(c('yellow', 'Force killing Docker container...'));
          dockerProcess.kill('SIGKILL');
        }
      }, 3000);
    } catch {}
  }
  if (signalRl) signalRl.close();
  setTimeout(() => process.exit(130), 500);
}

function setupSignalHandlers() {
  process.on('SIGINT', () => cleanup('SIGINT'));
  process.on('SIGTERM', () => cleanup('SIGTERM'));
}

function setupWindowsSignalHandler() {
  if (process.platform === 'win32' && !signalRl) {
    signalRl = readline.createInterface({ input: process.stdin, output: process.stdout });
    signalRl.on('SIGINT', () => cleanup('SIGINT'));
    signalRl.on('line', () => {});
  }
}

function checkEnvFile() {
  const envPath = path.join(ralphDir(), '.env');
  if (!fs.existsSync(envPath)) {
    console.error(c('red', 'Error: .ralph/.env not found. Run "ralph init" to configure credentials.'));
    process.exit(1);
  }
}

async function specGatherWizard(specName) {
  const seedPath = path.join(ralphDir(), 'spec_seed.md');
  const specPath = path.join(ralphDir(), 'specs', `${specName}.md`);

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const question = (prompt) => new Promise((resolve) => rl.question(prompt, resolve));

  const readMultiline = async (prompt) => {
    console.log(`  ${prompt}`);
    console.log(c('dim', '  (Enter each item on its own line. Empty line to finish.)'));
    const lines = [];
    while (true) {
      const line = await question('  > ');
      if (line.trim() === '') break;
      lines.push(line.trim());
    }
    return lines;
  };

  console.log(`\n${c('magenta', 'Spec Gather Wizard')}`);
  console.log(c('dim', '─────────────────────────────────\n'));

  if (fs.existsSync(seedPath)) {
    console.log(c('yellow', 'Found existing spec_seed.md'));
    const reuse = await question('Skip wizard and continue refinement? [Y/n]: ');
    if (reuse.trim().toLowerCase() !== 'n' && reuse.trim().toLowerCase() !== 'no') {
      console.log(c('green', '✓ Reusing existing spec_seed.md\n'));
      rl.close();
      return;
    }
    console.log('');
  }

  if (fs.existsSync(specPath)) {
    console.log(c('yellow', `Warning: specs/${specName}.md already exists.`));
    console.log(c('yellow', '   It will be overwritten during the draft phase.\n'));
  }

  // Step 1: Summary
  console.log(c('cyan', '[1/5] Executive Summary'));
  console.log(c('dim', '  What is this feature? Describe it in 1-3 sentences.'));
  const summaryLines = [];
  while (true) {
    const line = await question('  > ');
    if (line.trim() === '') {
      if (summaryLines.length > 0) break;
      console.log(c('red', '  Please enter at least one line.'));
      continue;
    }
    summaryLines.push(line.trim());
  }
  console.log('');

  // Step 2: Requirements
  console.log(c('cyan', '[2/5] Key Requirements'));
  const requirements = await readMultiline('What are the key requirements?');
  console.log('');

  // Step 3: Preferences
  console.log(c('cyan', '[3/5] Developer Preferences'));
  console.log(c('dim', '  Any patterns, libraries, or approaches you want to follow? (optional)'));
  const preferences = await readMultiline('Preferences:');
  console.log('');

  // Step 4: Constraints
  console.log(c('cyan', '[4/5] Known Constraints'));
  console.log(c('dim', '  Any limitations, deadlines, or technical constraints? (optional)'));
  const constraints = await readMultiline('Constraints:');
  console.log('');

  // Step 5: URLs
  console.log(c('cyan', '[5/5] Reference URLs'));
  console.log(c('dim', '  Any reference links (docs, designs, APIs)? (optional)'));
  const urls = await readMultiline('URLs:');

  rl.close();

  // Build spec_seed.md
  let seed = `# Spec Seed: ${specName}\n\n`;
  seed += `## Feature Name\n${specName}\n\n`;
  seed += `## Summary\n${summaryLines.join('\n')}\n\n`;

  seed += `## Requirements\n`;
  if (requirements.length > 0) {
    requirements.forEach(r => { seed += `- ${r}\n`; });
  } else {
    seed += `(No specific requirements provided — AI will infer from summary)\n`;
  }
  seed += '\n';

  if (preferences.length > 0) {
    seed += `## Preferences\n`;
    preferences.forEach(p => { seed += `- ${p}\n`; });
    seed += '\n';
  }
  if (constraints.length > 0) {
    seed += `## Constraints\n`;
    constraints.forEach(c => { seed += `- ${c}\n`; });
    seed += '\n';
  }
  if (urls.length > 0) {
    seed += `## References\n`;
    urls.forEach(u => { seed += `- ${u}\n`; });
    seed += '\n';
  }

  fs.writeFileSync(seedPath, seed);
  console.log(`\n${c('green', '✓ Created .ralph/spec_seed.md')}\n`);
}

function runForeground(spec, mode, iterations, verbose, insights, insightsGithub) {
  const root = repoDir();
  const imageName = getImageName();
  const loopScript = path.join(libDir, 'scripts', 'loop.sh');
  const dockerRootDir = toDockerPath(root);

  // We need to mount both the repo AND the ralph lib directory
  // so loop.sh can find the prompts
  const libDockerPath = toDockerPath(libDir);

  const dockerArgs = [
    'run', '-it', '--rm',
    '--env-file', path.join(ralphDir(), '.env'),
    '-v', `${dockerRootDir}:/workspace`,
    '-v', `${libDockerPath}:/ralph-lib:ro`,
    '-w', '/workspace',
    imageName,
    'bash', '/ralph-lib/scripts/loop.sh',
    spec,
    mode,
    String(iterations),
  ];

  if (verbose) dockerArgs.push('--verbose');
  if (insights) {
    dockerArgs.splice(dockerArgs.indexOf('--rm') + 1, 0, '-e', 'RALPH_INSIGHTS=true');
  }
  if (insightsGithub) {
    dockerArgs.splice(dockerArgs.indexOf('--rm') + 1, 0, '-e', 'RALPH_INSIGHTS_GITHUB=true');
  }

  dockerProcess = spawn('docker', dockerArgs, {
    stdio: 'inherit',
    cwd: root,
    shell: true,
  });

  dockerProcess.on('close', (code) => {
    dockerProcess = null;
    if (signalRl) signalRl.close();
    process.exit(code || 0);
  });

  dockerProcess.on('error', (err) => {
    console.error(c('red', `Failed to start Docker: ${err.message}`));
    process.exit(1);
  });
}

function runBackground(spec, mode, iterations, verbose, insights, insightsGithub) {
  const root = repoDir();
  const imageName = getImageName();
  const repoName = path.basename(root).toLowerCase().replace(/[^a-z0-9-]/g, '-');

  console.log(`\n${c('magenta', 'BACKGROUND MODE')}`);
  console.log(`${c('cyan', `Spec: ${spec}`)}`);
  console.log(`${c('cyan', `Mode: ${mode}`)}`);
  console.log(`${c('cyan', `Iterations: ${iterations}`)}\n`);

  const specSuffix = spec.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const backgroundImageName = `${imageName}-${specSuffix}`;

  ensureImage(backgroundImageName);
  checkEnvFile();

  const repoUrl = getRemoteUrl(root);
  if (!repoUrl) {
    console.error(c('red', 'Error: Could not get git remote URL. Is this a git repository?'));
    process.exit(1);
  }

  // Warn about uncommitted .ralph changes
  try {
    const status = execSync('git status --porcelain .ralph/', { encoding: 'utf-8', cwd: root }).trim();
    if (status) {
      console.log(c('yellow', 'Warning: You have uncommitted changes in .ralph/'));
      console.log(c('yellow', '   Background mode uses committed code only.\n'));
    }
  } catch {}

  const baseBranch = getBranch(root);
  const targetBranch = `ralph/${spec}`;
  const containerName = `ralph-${repoName}-${spec}`.replace(/[^a-z0-9-]/g, '-');

  console.log(`${c('cyan', `Repo: ${repoUrl}`)}`);
  console.log(`${c('cyan', `Base branch: ${baseBranch}`)}`);
  console.log(`${c('cyan', `Target branch: ${targetBranch}`)}`);
  console.log(`${c('cyan', `Container: ${containerName}`)}\n`);

  // Check for already running container
  try {
    const running = execSync(`docker ps --filter "name=${containerName}" --format "{{.Names}}"`, {
      encoding: 'utf-8', cwd: root,
    }).trim();
    if (running) {
      console.log(c('yellow', `Container ${containerName} is already running.`));
      console.log(`\nTo view logs:   docker logs -f ${containerName}`);
      console.log(`To stop:        docker stop ${containerName}`);
      process.exit(0);
    }
  } catch {}

  // Remove stopped container with same name
  try { execSync(`docker rm ${containerName}`, { cwd: root, stdio: 'ignore' }); } catch {}

  const libDockerPath = toDockerPath(libDir);

  const dockerArgs = [
    'run', '-d',
    '--name', containerName,
    '--env-file', path.join(ralphDir(), '.env'),
    '-v', `${libDockerPath}:/ralph-lib:ro`,
    '-e', `RALPH_REPO_URL=${repoUrl}`,
    '-e', `RALPH_BRANCH=${targetBranch}`,
    '-e', `RALPH_BASE_BRANCH=${baseBranch}`,
  ];

  if (insights) {
    dockerArgs.push('-e', 'RALPH_INSIGHTS=true');
  }
  if (insightsGithub) {
    dockerArgs.push('-e', 'RALPH_INSIGHTS_GITHUB=true');
  }

  // Spec mode: mount the locally-generated spec_seed.md into the cloned workspace
  if (mode === 'spec') {
    const seedPath = path.join(ralphDir(), 'spec_seed.md');
    if (fs.existsSync(seedPath)) {
      const seedDockerPath = toDockerPath(seedPath);
      dockerArgs.push('-v', `${seedDockerPath}:/workspace/.ralph/spec_seed.md:ro`);
    }
  }

  dockerArgs.push(
    backgroundImageName,
    'bash', '/ralph-lib/scripts/loop.sh',
    spec,
    mode,
    String(iterations),
  );

  if (verbose) dockerArgs.push('--verbose');

  try {
    execSync(`docker ${dockerArgs.join(' ')}`, { encoding: 'utf-8', cwd: root });

    console.log(`${c('green', '✓ Ralph is running in the background!')}\n`);
    console.log('Commands:');
    console.log(`  Check status:  docker ps --filter "name=${containerName}"`);
    console.log(`  Stop:          docker stop ${containerName}`);
    console.log(`  Pull changes:  git fetch origin && git checkout ${targetBranch}`);
    console.log('');
    console.log(`${c('cyan', 'Attaching to logs (Ctrl+C to stop Ralph)...')}\n`);

    const logsProcess = spawn('docker', ['logs', '-f', containerName], {
      stdio: 'inherit', cwd: root,
    });

    const stopContainer = () => {
      console.log(`\n${c('yellow', 'Stopping Ralph...')}`);
      try {
        execSync(`docker stop ${containerName}`, { stdio: 'ignore' });
        console.log(c('green', 'Ralph stopped.'));
        console.log(`Pull changes:  git fetch origin && git checkout ${targetBranch}\n`);
      } catch {}
      process.exit(0);
    };

    process.on('SIGINT', stopContainer);
    process.on('SIGTERM', stopContainer);

    if (process.platform === 'win32') {
      const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
      rl.on('SIGINT', stopContainer);
      rl.on('close', () => {});
    }

    logsProcess.on('close', () => {
      console.log(`\n${c('green', 'Ralph finished.')}`);
      console.log(`Pull changes:  git fetch origin && git checkout ${targetBranch}\n`);
      process.exit(0);
    });

  } catch (err) {
    console.error(c('red', `Failed to start background container: ${err.message}`));
    process.exit(1);
  }
}

async function promptCustomization(mode, defaults) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const question = (prompt) => new Promise((resolve) => rl.question(prompt, resolve));

  const iterLabel = mode === 'full' ? 'max cycles' : 'iterations';
  const iterInput = await question(`  Number of ${iterLabel} (default: ${defaults.iterations}): `);
  const iterations = parseInt(iterInput.trim()) || defaults.iterations;

  const verboseInput = await question(`  Verbose output? (default: ${defaults.verbose ? 'Yes' : 'No'}) [${defaults.verbose ? 'Y/n' : 'y/N'}]: `);
  const vTrimmed = verboseInput.trim().toLowerCase();
  const verbose = defaults.verbose
    ? (vTrimmed !== 'n' && vTrimmed !== 'no')
    : (vTrimmed === 'y' || vTrimmed === 'yes');

  let background = defaults.background;
  if (!['debug', 'decompose'].includes(mode)) {
    const bgDefault = defaults.background;
    const bgPrompt = bgDefault
      ? '  Run in background? (default: Yes) [Y/n]: '
      : '  Run in background? (default: No) [y/N]: ';
    const bgInput = await question(bgPrompt);
    const bgTrimmed = bgInput.trim().toLowerCase();
    background = bgDefault
      ? (bgTrimmed !== 'n' && bgTrimmed !== 'no')
      : (bgTrimmed === 'y' || bgTrimmed === 'yes');
  }

  let insights = defaults.insights || false;
  if (!['debug', 'decompose'].includes(mode)) {
    const insightsInput = await question(`  Enable insights? (default: No) [y/N]: `);
    const iTrimmed = insightsInput.trim().toLowerCase();
    insights = (iTrimmed === 'y' || iTrimmed === 'yes');
  }

  rl.close();
  return { iterations, verbose, background, insights };
}

async function run(spec, mode, opts = {}) {
  if (!isInitialized()) {
    console.error(c('red', '\n  Error: .ralph directory not found. Run "ralph init" first.\n'));
    process.exit(1);
  }

  setupSignalHandlers();

  let iterations = parseInt(opts.iterations) || getDefaultIterations(mode);
  let verbose = !!opts.verbose;
  let background = !!opts.background;
  let insights = !!opts.insights || process.env.RALPH_INSIGHTS === 'true';
  let insightsGithub = !!opts.insightsGithub || !!opts.github;
  const skipPrompts = !!opts.yes;

  // If no spec given, auto-select or prompt
  if (!spec) {
    const specs = getAvailableSpecs();
    if (mode === 'spec') {
      // Spec mode: need a name for the new spec
      console.error(c('red', '\n  Error: Please provide a spec name. Usage: ralph spec <name>\n'));
      process.exit(1);
    }
    if (specs.length === 0) {
      console.error(c('red', '\n  No specs found. Create one at .ralph/specs/<name>.md or use "ralph spec <name>".\n'));
      process.exit(1);
    }
    if (specs.length === 1) {
      spec = specs[0];
      console.log(c('green', `\n  Auto-selected spec: ${spec}\n`));
    } else {
      console.error(c('red', '\n  Multiple specs found. Please specify which one:'));
      specs.forEach(s => console.error(`    - ${s}`));
      console.error('');
      process.exit(1);
    }
  }

  // Validate spec exists (unless in spec creation or insights mode)
  if (mode !== 'spec' && mode !== 'insights' && !validateSpec(spec)) {
    console.error(c('red', `\n  Error: Spec file not found: .ralph/specs/${spec}.md`));
    const specs = getAvailableSpecs();
    if (specs.length > 0) {
      console.error('\n  Available specs:');
      specs.forEach(s => console.error(`    - ${s}`));
    }
    console.error('');
    process.exit(1);
  }

  console.log(`\n${c('cyan', `Spec: ${spec}`)}`);
  console.log(`${c('cyan', `Mode: ${mode}`)}\n`);

  // Interactive customization unless --yes
  if (!skipPrompts) {
    const customized = await promptCustomization(mode, { iterations, verbose, background, insights });
    iterations = customized.iterations;
    verbose = customized.verbose;
    background = customized.background;
    if (customized.insights) insights = true;
  }

  console.log(`\n${c('cyan', `Iterations: ${iterations}`)}`);
  console.log(`${c('cyan', `Verbose: ${verbose}`)}`);
  console.log(`${c('cyan', `Background: ${background}`)}`);
  if (insights) console.log(`${c('cyan', `Insights: enabled${insightsGithub ? ' (+ GitHub issues)' : ''}`)}`);
  console.log('');

  ensureImage();
  checkEnvFile();

  // Spec mode: run gather wizard first
  if (mode === 'spec') {
    await specGatherWizard(spec);
  }

  setupWindowsSignalHandler();

  if (background) {
    runBackground(spec, mode, iterations, verbose, insights, insightsGithub);
  } else {
    runForeground(spec, mode, iterations, verbose, insights, insightsGithub);
  }
}

function getDefaultIterations(mode) {
  const defaults = {
    plan: 5, build: 10, review: 10, 'review-fix': 5,
    debug: 1, full: 10, decompose: 1, spec: 8, insights: 1,
  };
  return defaults[mode] || 10;
}

module.exports = { run, runBackground, checkEnvFile };
