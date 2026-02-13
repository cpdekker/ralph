#!/usr/bin/env node
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const ui = require('./lib/ui');
const { c, success, warn, error, info, dim, header, separator, hint, startupBanner, createSpinner } = ui;

const rootDir = path.resolve(__dirname, '..');

// Derive image name from repo directory to avoid conflicts across multiple repos
const repoName = path.basename(rootDir).toLowerCase().replace(/[^a-z0-9-]/g, '-');
const imageName = `ralph-wiggum-${repoName}`;

// Track the running Docker process for cleanup
let dockerProcess = null;
let signalRl = null;

// Cleanup function for signal handlers
function cleanup(signal) {
  console.log(`\n${c('yellow', `Received ${signal}, shutting down...`)}`);

  if (dockerProcess) {
    try {
      dockerProcess.kill('SIGTERM');
      setTimeout(() => {
        if (dockerProcess && !dockerProcess.killed) {
          warn('Force killing Docker container...');
          dockerProcess.kill('SIGKILL');
        }
      }, 3000);
    } catch (e) {
      // Process might already be dead
    }
  }

  if (signalRl) {
    signalRl.close();
  }

  setTimeout(() => {
    process.exit(130);
  }, 500);
}

// Handle Ctrl+C and other termination signals
function setupSignalHandlers() {
  process.on('SIGINT', () => cleanup('SIGINT'));
  process.on('SIGTERM', () => cleanup('SIGTERM'));
}

// Setup Windows-specific SIGINT handler (only call after interactive prompts are done)
function setupWindowsSignalHandler() {
  if (process.platform === 'win32' && !signalRl) {
    signalRl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    signalRl.on('SIGINT', () => cleanup('SIGINT'));
    signalRl.on('line', () => { });
  }
}

// Convert Windows paths to Docker-compatible format
function toDockerPath(windowsPath) {
  if (process.platform !== 'win32') {
    return windowsPath;
  }
  return windowsPath
    .replace(/\\/g, '/')
    .replace(/^([A-Za-z]):/, (_, letter) => `/${letter.toLowerCase()}`);
}

function getAvailableSpecs() {
  const specsDir = path.join(rootDir, '.ralph', 'specs');
  if (!fs.existsSync(specsDir)) return [];
  return fs.readdirSync(specsDir)
    .filter(f => f.endsWith('.md') && f !== 'active.md' && f !== 'sample.md')
    .map(f => f.replace('.md', ''));
}

function getSpecDetails(specName) {
  const manifestPath = path.join(rootDir, '.ralph', 'specs', specName, 'manifest.json');
  if (!fs.existsSync(manifestPath)) return null;
  try {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
    return manifest.progress || null;
  } catch {
    return null;
  }
}

function validateSpec(spec) {
  const specPath = path.join(rootDir, '.ralph', 'specs', `${spec}.md`);
  return fs.existsSync(specPath);
}

function checkDockerImage(targetImageName = imageName) {
  try {
    const images = execSync('docker images --format "{{.Repository}}"', {
      encoding: 'utf-8',
      cwd: rootDir,
    });
    if (!images.split('\n').includes(targetImageName)) {
      console.log(`  Building ${targetImageName} image...`);
      execSync(`docker build -t ${targetImageName} -f .ralph/docker/Dockerfile .`, {
        stdio: 'inherit',
        cwd: rootDir,
      });
    }
  } catch (err) {
    error('Failed to check/build Docker image.');
    process.exit(1);
  }
}

function checkEnvFile() {
  const envPath = path.join(rootDir, '.ralph', '.env');
  if (!fs.existsSync(envPath)) {
    error('.ralph/.env not found.');
    hint('envMissing');
    process.exit(1);
  }
}

function getGitRemoteUrl() {
  try {
    const url = execSync('git remote get-url origin', {
      encoding: 'utf-8',
      cwd: rootDir,
    }).trim();
    if (url.startsWith('git@github.com:')) {
      return url.replace('git@github.com:', 'https://github.com/');
    }
    return url;
  } catch {
    return null;
  }
}

function getGitBranch() {
  try {
    return execSync('git branch --show-current', {
      encoding: 'utf-8',
      cwd: rootDir,
    }).trim();
  } catch {
    return 'main';
  }
}

async function specGatherWizard(specName) {
  const seedPath = path.join(rootDir, '.ralph', 'spec_seed.md');
  const specPath = path.join(rootDir, '.ralph', 'specs', `${specName}.md`);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (prompt) => new Promise((resolve) => rl.question(prompt, resolve));

  const readMultiline = async (prompt) => {
    console.log(`  ${prompt}`);
    dim('  (Enter each item on its own line. Empty line to finish.)');
    const lines = [];
    while (true) {
      const line = await question('  > ');
      if (line.trim() === '') break;
      lines.push(line.trim());
    }
    return lines;
  };

  header('Spec Gather Wizard');

  // Check for references directory and remind user
  const referencesDir = path.join(rootDir, '.ralph', 'references');
  if (fs.existsSync(referencesDir)) {
    const refFiles = fs.readdirSync(referencesDir).filter(f => f !== 'README.md' && !f.startsWith('.'));
    if (refFiles.length > 0) {
      console.log(`${c('cyan', `  Reference files found (${refFiles.length}):`)}`);
      refFiles.slice(0, 5).forEach(f => console.log(`   • ${f}`));
      if (refFiles.length > 5) console.log(`   ... and ${refFiles.length - 5} more`);
      dim('   These will be analyzed during spec generation.');
      console.log('');
    } else {
      dim('  Tip: Add reference files to .ralph/references/ before continuing');
      dim('  (existing implementations, sample data, documentation, etc.)');
      console.log('');
    }
  } else {
    dim('  Tip: Create .ralph/references/ and add reference files');
    dim('  (existing implementations, sample data, documentation, etc.)');
    console.log('');
  }

  // Check for existing spec_seed.md
  if (fs.existsSync(seedPath)) {
    warn('Found existing spec_seed.md');
    const reuse = await question('Skip wizard and continue refinement? [Y/n]: ');
    if (reuse.trim().toLowerCase() !== 'n' && reuse.trim().toLowerCase() !== 'no') {
      success('Reusing existing spec_seed.md');
      console.log('');
      rl.close();
      return;
    }
    console.log('');
  }

  // Check for existing spec file
  if (fs.existsSync(specPath)) {
    warn(`specs/${specName}.md already exists.`);
    info('It will be overwritten during the draft phase.');
    console.log('');
  }

  // Step 1: Executive summary
  console.log(`${c('cyan', '[1/5] Executive Summary')}`);
  dim('  What is this feature? Describe it in 1-3 sentences.');
  const summaryLines = [];
  while (true) {
    const line = await question('  > ');
    if (line.trim() === '') {
      if (summaryLines.length > 0) break;
      error('Please enter at least one line.');
      continue;
    }
    summaryLines.push(line.trim());
  }
  const summary = summaryLines.join('\n');
  console.log('');

  // Step 2: Key requirements
  console.log(`${c('cyan', '[2/5] Key Requirements')}`);
  const requirements = await readMultiline('What are the key requirements?');
  console.log('');

  // Step 3: Preferences
  console.log(`${c('cyan', '[3/5] Developer Preferences')}`);
  dim('  Any patterns, libraries, or approaches you want to follow? (optional)');
  const preferences = await readMultiline('Preferences:');
  console.log('');

  // Step 4: Constraints
  console.log(`${c('cyan', '[4/5] Known Constraints')}`);
  dim('  Any limitations, deadlines, or technical constraints? (optional)');
  const constraints = await readMultiline('Constraints:');
  console.log('');

  // Step 5: Reference URLs
  console.log(`${c('cyan', '[5/5] Reference URLs')}`);
  dim('  Any reference links (docs, designs, APIs)? (optional)');
  const urls = await readMultiline('URLs:');

  rl.close();

  // Build spec_seed.md content
  let seed = `# Spec Seed: ${specName}\n\n`;
  seed += `## Feature Name\n${specName}\n\n`;
  seed += `## Summary\n${summary}\n\n`;

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
    constraints.forEach(ct => { seed += `- ${ct}\n`; });
    seed += '\n';
  }

  if (urls.length > 0) {
    seed += `## References\n`;
    urls.forEach(u => { seed += `- ${u}\n`; });
    seed += '\n';
  }

  // Write spec_seed.md
  fs.writeFileSync(seedPath, seed);
  success('Created .ralph/spec_seed.md');
  console.log('');
}

function runRalphBackground(spec, mode, iterations, verbose) {
  startupBanner({
    spec,
    mode,
    iterations,
    background: true,
    version: '0.0.0',
  });
  header('Background Mode');

  // Use spec-specific image name for background mode
  const specSuffix = spec.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const backgroundImageName = `${imageName}-${specSuffix}`;

  checkDockerImage(backgroundImageName);
  checkEnvFile();

  const repoUrl = getGitRemoteUrl();
  if (!repoUrl) {
    error('Could not get git remote URL. Is this a git repository?');
    process.exit(1);
  }

  // Check for uncommitted changes to .ralph directory
  try {
    const status = execSync('git status --porcelain .ralph/', {
      encoding: 'utf-8',
      cwd: rootDir,
    }).trim();
    if (status) {
      warn('You have uncommitted changes in .ralph/');
      info('Background mode uses committed code only.');
      console.log('');
    }
  } catch {
    // Ignore errors
  }

  const baseBranch = getGitBranch();
  const targetBranch = `ralph/${spec}`;
  const containerName = `ralph-${repoName}-${spec}`.replace(/[^a-z0-9-]/g, '-');

  info(`Repo:       ${repoUrl}`);
  info(`Base:       ${baseBranch}`);
  info(`Target:     ${targetBranch}`);
  info(`Image:      ${backgroundImageName}`);
  info(`Container:  ${containerName}`);
  console.log('');

  // Check if container already running
  try {
    const running = execSync(`docker ps --filter "name=${containerName}" --format "{{.Names}}"`, {
      encoding: 'utf-8',
      cwd: rootDir,
    }).trim();
    if (running) {
      warn(`Container ${containerName} is already running.`);
      console.log(`\n  To view logs:   docker logs -f ${containerName}`);
      console.log(`  To stop:        docker stop ${containerName}`);
      process.exit(0);
    }
  } catch {
    // Ignore errors
  }

  // Remove any stopped container with same name
  try {
    execSync(`docker rm ${containerName}`, { cwd: rootDir, stdio: 'ignore' });
  } catch {
    // Ignore if doesn't exist
  }

  const dockerArgs = [
    'run',
    '-d',
    '--name', containerName,
    '--env-file', '.ralph/.env',
    '-e', `RALPH_REPO_URL=${repoUrl}`,
    '-e', `RALPH_BRANCH=${targetBranch}`,
    '-e', `RALPH_BASE_BRANCH=${baseBranch}`,
    backgroundImageName,
    'bash', './.ralph/scripts/loop.sh',
    spec,
    mode,
    String(iterations),
  ];

  if (verbose) {
    dockerArgs.push('--verbose');
  }

  try {
    execSync(`docker ${dockerArgs.join(' ')}`, {
      encoding: 'utf-8',
      cwd: rootDir,
    });

    success('Ralph is running in the background!');
    console.log('');
    console.log('  Commands:');
    console.log(`    Check status:  docker ps --filter "name=${containerName}"`);
    console.log(`    Stop:          docker stop ${containerName}`);
    console.log(`    Pull changes:  git fetch origin && git checkout ${targetBranch}`);
    console.log('');
    hint('backgroundMode');
    console.log('');

    // Attach to logs
    const logsProcess = spawn('docker', ['logs', '-f', containerName], {
      stdio: 'inherit',
      cwd: rootDir,
    });

    const stopContainer = () => {
      console.log(`\n${c('yellow', '  Stopping Ralph...')}`);
      try {
        execSync(`docker stop ${containerName}`, { stdio: 'ignore' });
        success('Ralph stopped.');
        console.log(`  Pull changes:  git fetch origin && git checkout ${targetBranch}\n`);
      } catch {
        // Already stopped
      }
      process.exit(0);
    };

    process.on('SIGINT', stopContainer);
    process.on('SIGTERM', stopContainer);

    if (process.platform === 'win32') {
      const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
      });
      rl.on('SIGINT', stopContainer);
      rl.on('close', () => { });
    }

    logsProcess.on('close', (code) => {
      success('Ralph finished.');
      console.log(`  Pull changes:  git fetch origin && git checkout ${targetBranch}\n`);
      process.exit(0);
    });

  } catch (err) {
    error(`Failed to start background container: ${err.message}`);
    process.exit(1);
  }
}

function runRalph(spec, mode, iterations, verbose) {
  startupBanner({
    spec,
    mode,
    iterations,
    verbose,
    version: '0.0.0',
  });

  checkDockerImage();
  checkEnvFile();

  setupWindowsSignalHandler();

  const dockerRootDir = toDockerPath(rootDir);

  const dockerArgs = [
    'run',
    '-it',
    '--rm',
    '--env-file',
    '.ralph/.env',
    '-v',
    `${dockerRootDir}:/workspace`,
    '-w',
    '/workspace',
    imageName,
    'bash', './.ralph/scripts/loop.sh',
    spec,
    mode,
    String(iterations),
  ];

  if (verbose) {
    dockerArgs.push('--verbose');
  }

  dockerProcess = spawn('docker', dockerArgs, {
    stdio: 'inherit',
    cwd: rootDir,
    shell: true,
  });

  dockerProcess.on('close', (code) => {
    dockerProcess = null;
    if (signalRl) {
      signalRl.close();
    }
    process.exit(code || 0);
  });

  dockerProcess.on('error', (err) => {
    error(`Failed to start Docker: ${err.message}`);
    process.exit(1);
  });
}

async function interactivePrompt(preselectedMode = null) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (prompt) => new Promise((resolve) => rl.question(prompt, resolve));

  startupBanner({ cwd: rootDir, version: '0.0.0' });

  const availableSpecs = getAvailableSpecs();

  let spec = '';

  // Spec mode: always prompt for a name
  if (preselectedMode === 'spec') {
    if (availableSpecs.length > 0) {
      console.log('  Existing specs:');
      availableSpecs.forEach((s, i) => {
        console.log(`    ${i + 1}. ${s}`);
      });
      console.log('');
    }
    while (!spec) {
      const input = await question('  Enter spec name (new or existing): ');
      const trimmed = input.trim();
      const num = parseInt(trimmed);
      if (!isNaN(num) && num >= 1 && num <= availableSpecs.length) {
        spec = availableSpecs[num - 1];
      } else if (trimmed) {
        spec = trimmed.toLowerCase().replace(/[^a-z0-9-]/g, '-');
      }
    }
  } else if (availableSpecs.length === 1) {
    spec = availableSpecs[0];
    success(`Auto-selected spec: ${spec}`);
    console.log('');
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
          error(`Spec not found: .ralph/specs/${trimmed}.md`);
        }
      }
    }
  } else {
    warn('No specs found.');
    hint('noSpecs');
    console.log('');
    rl.close();
    process.exit(1);
  }

  let mode = preselectedMode || '';

  if (preselectedMode) {
    success(`Mode: ${preselectedMode}`);
    console.log('');
  } else {
    console.log('  Modes:');
    console.log('    1. plan       - Analyze codebase and create implementation plan');
    console.log('    2. build      - Implement tasks from the plan');
    console.log('    3. review     - Review implementation for bugs and issues');
    console.log('    4. review-fix - Fix issues identified during review');
    console.log('    5. debug      - Single iteration, verbose, no commits');
    console.log('    6. full       - Full cycle: plan → build → review → check (repeats until complete)');
    console.log('    7. decompose  - Break large spec into ordered sub-specs for full mode');
    console.log('    8. spec       - Create spec interactively: gather → research → draft → review');
    console.log('');

    while (!mode) {
      const input = await question('  Select mode [1-8 or name] (default: build): ');
      const trimmed = input.trim().toLowerCase();

      if (trimmed === '' || trimmed === '2' || trimmed === 'build') {
        mode = 'build';
      } else if (trimmed === '1' || trimmed === 'plan') {
        mode = 'plan';
      } else if (trimmed === '3' || trimmed === 'review') {
        mode = 'review';
      } else if (trimmed === '4' || trimmed === 'review-fix') {
        mode = 'review-fix';
      } else if (trimmed === '5' || trimmed === 'debug') {
        mode = 'debug';
      } else if (trimmed === '6' || trimmed === 'full' || trimmed === 'yolo') {
        mode = 'full';
      } else if (trimmed === '7' || trimmed === 'decompose') {
        mode = 'decompose';
      } else if (trimmed === '8' || trimmed === 'spec') {
        mode = 'spec';
      } else {
        error('Invalid selection. Enter 1-8 or mode name.');
      }
    }
  }

  const defaultIterations = mode === 'plan' ? 5 : (mode === 'debug' ? 1 : (mode === 'decompose' ? 1 : (mode === 'spec' ? 8 : (mode === 'review-fix' ? 5 : (mode === 'full' ? 10 : 10)))));
  const iterLabel = mode === 'full' ? 'max cycles' : 'iterations';

  if (mode === 'debug') {
    warn('Debug mode: 1 iteration, verbose, no commits');
    console.log('');
  }

  if (mode === 'decompose') {
    console.log(`${c('magenta', '  Decompose mode: breaking spec into sub-specs')}`);
    console.log('');
  }
  const iterInput = await question(`  Number of ${iterLabel} (default: ${defaultIterations}): `);
  const iterations = parseInt(iterInput.trim()) || defaultIterations;

  const verboseInput = await question('  Verbose output? (default: No) [y/N]: ');
  const verbose = verboseInput.trim().toLowerCase() === 'y' || verboseInput.trim().toLowerCase() === 'yes';

  let background = false;

  if (mode === 'debug' || mode === 'decompose') {
    info(`${mode.charAt(0).toUpperCase() + mode.slice(1)} mode always runs in foreground.`);
    console.log('');
    background = false;
  } else {
    const backgroundDefault = mode === 'full';
    const backgroundPrompt = backgroundDefault
      ? '  Run in background? (Ralph clones repo, you keep working) (default: Yes) [Y/n]: '
      : '  Run in background? (Ralph clones repo, you keep working) (default: No) [y/N]: ';
    const backgroundInput = await question(backgroundPrompt);
    const backgroundTrimmed = backgroundInput.trim().toLowerCase();

    if (backgroundDefault) {
      background = backgroundTrimmed !== 'n' && backgroundTrimmed !== 'no';
    } else {
      background = backgroundTrimmed === 'y' || backgroundTrimmed === 'yes';
    }
  }

  rl.close();

  if (mode === 'spec') {
    await specGatherWizard(spec);
  }

  if (background) {
    runRalphBackground(spec, mode, iterations, verbose);
  } else {
    runRalph(spec, mode, iterations, verbose);
  }
}

// Setup signal handlers first
setupSignalHandlers();

// Main execution
const args = process.argv.slice(2);
const isNumeric = (str) => !isNaN(parseInt(str)) && isFinite(str);

// Check for flags
const verbose = args.includes('--verbose') || args.includes('-v');
const background = args.includes('--background') || args.includes('-b');
const planFlag = args.includes('--plan');
const buildFlag = args.includes('--build');
const reviewFlag = args.includes('--review');
const reviewFixFlag = args.includes('--review-fix');
const debugFlag = args.includes('--debug');
const fullFlag = args.includes('--full') || args.includes('--yolo');
const decomposeFlag = args.includes('--decompose');
const specFlag = args.includes('--spec');
const filteredArgs = args.filter(a =>
  a !== '--verbose' && a !== '-v' &&
  a !== '--background' && a !== '-b' &&
  a !== '--no-background' && a !== '--foreground' && a !== '-f' &&
  a !== '--plan' && a !== '--build' && a !== '--review' && a !== '--review-fix' && a !== '--debug' && a !== '--full' && a !== '--yolo' && a !== '--decompose' && a !== '--spec'
);

// Determine preselected mode from flags
const preselectedMode = specFlag ? 'spec' : (decomposeFlag ? 'decompose' : (fullFlag ? 'full' : (debugFlag ? 'debug' : (reviewFixFlag ? 'review-fix' : (planFlag ? 'plan' : (buildFlag ? 'build' : (reviewFlag ? 'review' : null)))))));

// No arguments - interactive mode
if (filteredArgs.length === 0) {
  interactivePrompt(preselectedMode).catch((err) => {
    console.error(err);
    process.exit(1);
  });
} else {
  // Parse arguments
  const spec = filteredArgs[0];

  let mode = preselectedMode || 'build';

  if (filteredArgs[1] === 'spec') {
    mode = 'spec';
  }

  // Validate spec file exists (skip for spec mode)
  if (mode !== 'spec' && !validateSpec(spec)) {
    error(`Spec file not found: .ralph/specs/${spec}.md`);
    const availableSpecs = getAvailableSpecs();
    if (availableSpecs.length > 0) {
      console.error('\n  Available specs:');
      availableSpecs.forEach(s => console.error(`    - ${s}`));
    }
    process.exit(1);
  }

  let iterations = mode === 'plan' ? 5 : (mode === 'full' ? 10 : (mode === 'spec' ? 8 : 10));

  if (filteredArgs[1] === 'spec') {
    mode = 'spec';
    iterations = 8;
    if (filteredArgs[2] && isNumeric(filteredArgs[2])) {
      iterations = parseInt(filteredArgs[2]);
    }
  } else if (filteredArgs[1] === 'plan') {
    mode = 'plan';
    iterations = 5;
    if (filteredArgs[2] && isNumeric(filteredArgs[2])) {
      iterations = parseInt(filteredArgs[2]);
    }
  } else if (filteredArgs[1] === 'build') {
    mode = 'build';
    iterations = 10;
    if (filteredArgs[2] && isNumeric(filteredArgs[2])) {
      iterations = parseInt(filteredArgs[2]);
    }
  } else if (filteredArgs[1] === 'review') {
    mode = 'review';
    iterations = 10;
    if (filteredArgs[2] && isNumeric(filteredArgs[2])) {
      iterations = parseInt(filteredArgs[2]);
    }
  } else if (filteredArgs[1] === 'review-fix') {
    mode = 'review-fix';
    iterations = 5;
    if (filteredArgs[2] && isNumeric(filteredArgs[2])) {
      iterations = parseInt(filteredArgs[2]);
    }
  } else if (filteredArgs[1] === 'debug') {
    mode = 'debug';
    iterations = 1;
  } else if (filteredArgs[1] === 'full' || filteredArgs[1] === 'yolo') {
    mode = 'full';
    iterations = 10;
    if (filteredArgs[2] && isNumeric(filteredArgs[2])) {
      iterations = parseInt(filteredArgs[2]);
    }
  } else if (filteredArgs[1] === 'decompose') {
    mode = 'decompose';
    iterations = 1;
  } else if (filteredArgs[1] && isNumeric(filteredArgs[1])) {
    iterations = parseInt(filteredArgs[1]);
  }

  const noBackground = args.includes('--no-background') || args.includes('--foreground') || args.includes('-f');
  const useBackground = (mode === 'debug' || mode === 'decompose') ? false : (noBackground ? false : (background || mode === 'full'));

  if (mode === 'spec') {
    specGatherWizard(spec).then(() => {
      if (useBackground) {
        runRalphBackground(spec, mode, iterations, verbose);
      } else {
        setupWindowsSignalHandler();
        runRalph(spec, mode, iterations, verbose);
      }
    }).catch((err) => {
      console.error(err);
      process.exit(1);
    });
  } else if (useBackground) {
    runRalphBackground(spec, mode, iterations, verbose);
  } else {
    setupWindowsSignalHandler();
    runRalph(spec, mode, iterations, verbose);
  }
}
