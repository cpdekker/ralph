#!/usr/bin/env node
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const rootDir = path.resolve(__dirname, '..');

// Derive image name from repo directory to avoid conflicts across multiple repos
const repoName = path.basename(rootDir).toLowerCase().replace(/[^a-z0-9-]/g, '-');
const imageName = `ralph-wiggum-${repoName}`;

// Track the running Docker process for cleanup
let dockerProcess = null;
let signalRl = null;

// Cleanup function for signal handlers
function cleanup(signal) {
  console.log(`\n\x1b[33mReceived ${signal}, shutting down...\x1b[0m`);

  if (dockerProcess) {
    // Kill the Docker container
    try {
      // First try graceful termination
      dockerProcess.kill('SIGTERM');

      // Force kill after 3 seconds if still running
      setTimeout(() => {
        if (dockerProcess && !dockerProcess.killed) {
          console.log('\x1b[33mForce killing Docker container...\x1b[0m');
          dockerProcess.kill('SIGKILL');
        }
      }, 3000);
    } catch (e) {
      // Process might already be dead
    }
  }

  // Close signal readline if it exists
  if (signalRl) {
    signalRl.close();
  }

  // Exit after a short delay to allow cleanup
  setTimeout(() => {
    process.exit(130); // 128 + SIGINT(2) = 130
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
    // Prevent the readline from interfering with normal output
    signalRl.on('line', () => { });
  }
}

// Convert Windows paths to Docker-compatible format
// Docker on Windows needs forward slashes and drive letters like /c/ instead of C:\
function toDockerPath(windowsPath) {
  if (process.platform !== 'win32') {
    return windowsPath;
  }
  // Convert C:\Users\... to /c/Users/...
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
      console.log(`Building ${targetImageName} image...`);
      execSync(`docker build -t ${targetImageName} -f .ralph/Dockerfile .`, {
        stdio: 'inherit',
        cwd: rootDir,
      });
    }
  } catch (error) {
    console.error('\x1b[31mFailed to check/build Docker image.\x1b[0m');
    process.exit(1);
  }
}

function checkEnvFile() {
  const envPath = path.join(rootDir, '.ralph', '.env');
  if (!fs.existsSync(envPath)) {
    console.error(
      '\x1b[31mError: .ralph/.env not found. Copy from .ralph/.env.example and add your credentials.\x1b[0m'
    );
    process.exit(1);
  }
}

function getGitRemoteUrl() {
  try {
    const url = execSync('git remote get-url origin', {
      encoding: 'utf-8',
      cwd: rootDir,
    }).trim();
    // Convert GitHub SSH to HTTPS format for token auth
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

  // Helper: read multiline input (empty line to finish)
  const readMultiline = async (prompt) => {
    console.log(`  ${prompt}`);
    console.log('\x1b[2m  (Enter each item on its own line. Empty line to finish.)\x1b[0m');
    const lines = [];
    while (true) {
      const line = await question('  > ');
      if (line.trim() === '') break;
      lines.push(line.trim());
    }
    return lines;
  };

  console.log('\n\x1b[35m📋 Spec Gather Wizard\x1b[0m');
  console.log('\x1b[2m─────────────────────────────────\x1b[0m\n');

  // Check for existing spec_seed.md — offer to reuse
  if (fs.existsSync(seedPath)) {
    console.log('\x1b[33mFound existing spec_seed.md\x1b[0m');
    const reuse = await question('Skip wizard and continue refinement? [Y/n]: ');
    if (reuse.trim().toLowerCase() !== 'n' && reuse.trim().toLowerCase() !== 'no') {
      console.log('\x1b[32m✓ Reusing existing spec_seed.md\x1b[0m\n');
      rl.close();
      return;
    }
    console.log('');
  }

  // Check for existing spec file — warn if overwriting
  if (fs.existsSync(specPath)) {
    console.log(`\x1b[33m⚠️  Warning: specs/${specName}.md already exists.\x1b[0m`);
    console.log('\x1b[33m   It will be overwritten during the draft phase.\x1b[0m\n');
  }

  // Step 1: Executive summary
  console.log('\x1b[36m[1/5] Executive Summary\x1b[0m');
  console.log('\x1b[2m  What is this feature? Describe it in 1-3 sentences.\x1b[0m');
  const summaryLines = [];
  while (true) {
    const line = await question('  > ');
    if (line.trim() === '') {
      if (summaryLines.length > 0) break;
      console.log('  \x1b[31mPlease enter at least one line.\x1b[0m');
      continue;
    }
    summaryLines.push(line.trim());
  }
  const summary = summaryLines.join('\n');
  console.log('');

  // Step 2: Key requirements
  console.log('\x1b[36m[2/5] Key Requirements\x1b[0m');
  const requirements = await readMultiline('What are the key requirements?');
  console.log('');

  // Step 3: Preferences
  console.log('\x1b[36m[3/5] Developer Preferences\x1b[0m');
  console.log('\x1b[2m  Any patterns, libraries, or approaches you want to follow? (optional)\x1b[0m');
  const preferences = await readMultiline('Preferences:');
  console.log('');

  // Step 4: Constraints
  console.log('\x1b[36m[4/5] Known Constraints\x1b[0m');
  console.log('\x1b[2m  Any limitations, deadlines, or technical constraints? (optional)\x1b[0m');
  const constraints = await readMultiline('Constraints:');
  console.log('');

  // Step 5: Reference URLs
  console.log('\x1b[36m[5/5] Reference URLs\x1b[0m');
  console.log('\x1b[2m  Any reference links (docs, designs, APIs)? (optional)\x1b[0m');
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
    constraints.forEach(c => { seed += `- ${c}\n`; });
    seed += '\n';
  }

  if (urls.length > 0) {
    seed += `## References\n`;
    urls.forEach(u => { seed += `- ${u}\n`; });
    seed += '\n';
  }

  // Write spec_seed.md
  fs.writeFileSync(seedPath, seed);
  console.log(`\n\x1b[32m✓ Created .ralph/spec_seed.md\x1b[0m\n`);
}

function runRalphBackground(spec, mode, iterations, verbose) {
  console.log(`\n\x1b[35m🚀 BACKGROUND MODE\x1b[0m`);
  console.log(`\x1b[36mSpec: ${spec}\x1b[0m`);
  console.log(`\x1b[36mMode: ${mode}\x1b[0m`);
  console.log(`\x1b[36mIterations: ${iterations}\x1b[0m\n`);

  // Use spec-specific image name for background mode to allow parallel execution
  const specSuffix = spec.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const backgroundImageName = `${imageName}-${specSuffix}`;

  checkDockerImage(backgroundImageName);
  checkEnvFile();

  const repoUrl = getGitRemoteUrl();
  if (!repoUrl) {
    console.error('\x1b[31mError: Could not get git remote URL. Is this a git repository?\x1b[0m');
    process.exit(1);
  }

  // Check for uncommitted changes to .ralph directory
  try {
    const status = execSync('git status --porcelain .ralph/', {
      encoding: 'utf-8',
      cwd: rootDir,
    }).trim();
    if (status) {
      console.log('\x1b[33m⚠️  Warning: You have uncommitted changes in .ralph/\x1b[0m');
      console.log('\x1b[33m   Background mode uses committed code only.\x1b[0m');
      console.log('\x1b[33m   Consider committing your specs first.\x1b[0m\n');
    }
  } catch {
    // Ignore errors
  }

  const baseBranch = getGitBranch();
  const targetBranch = `ralph/${spec}`;
  const containerName = `ralph-${repoName}-${spec}`.replace(/[^a-z0-9-]/g, '-');

  console.log(`\x1b[36mRepo: ${repoUrl}\x1b[0m`);
  console.log(`\x1b[36mBase branch: ${baseBranch}\x1b[0m`);
  console.log(`\x1b[36mTarget branch: ${targetBranch}\x1b[0m`);
  console.log(`\x1b[36mImage: ${backgroundImageName}\x1b[0m`);
  console.log(`\x1b[36mContainer: ${containerName}\x1b[0m\n`);

  // Check if container already running
  try {
    const running = execSync(`docker ps --filter "name=${containerName}" --format "{{.Names}}"`, {
      encoding: 'utf-8',
      cwd: rootDir,
    }).trim();
    if (running) {
      console.log(`\x1b[33mContainer ${containerName} is already running.\x1b[0m`);
      console.log(`\nTo view logs:   docker logs -f ${containerName}`);
      console.log(`To stop:        docker stop ${containerName}`);
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

  // Build docker args for background mode
  // Note: Ralph clones the repo, so he works on committed code only
  // Local uncommitted changes to specs won't be included
  // Use 'bash' explicitly since cloned files may not have execute permission
  const dockerArgs = [
    'run',
    '-d',  // Detached mode
    '--name', containerName,
    '--env-file', '.ralph/.env',
    '-e', `RALPH_REPO_URL=${repoUrl}`,
    '-e', `RALPH_BRANCH=${targetBranch}`,
    '-e', `RALPH_BASE_BRANCH=${baseBranch}`,
    backgroundImageName,
    'bash', './.ralph/loop.sh',
    spec,
    mode,
    String(iterations),
  ];

  if (verbose) {
    dockerArgs.push('--verbose');
  }

  try {
    const containerId = execSync(`docker ${dockerArgs.join(' ')}`, {
      encoding: 'utf-8',
      cwd: rootDir,
    }).trim();

    console.log('\x1b[32m✓ Ralph is running in the background!\x1b[0m\n');
    console.log('Commands:');
    console.log(`  Check status:  docker ps --filter "name=${containerName}"`);
    console.log(`  Stop:          docker stop ${containerName}`);
    console.log(`  Pull changes:  git fetch origin && git checkout ${targetBranch}`);
    console.log('');
    console.log('\x1b[36mAttaching to logs (Ctrl+C to stop Ralph)...\x1b[0m\n');

    // Attach to logs
    const logsProcess = spawn('docker', ['logs', '-f', containerName], {
      stdio: 'inherit',
      cwd: rootDir,
    });

    // Handle Ctrl+C - stop the container
    const stopContainer = () => {
      console.log(`\n\x1b[33mStopping Ralph...\x1b[0m`);
      try {
        execSync(`docker stop ${containerName}`, { stdio: 'ignore' });
        console.log(`\x1b[32mRalph stopped.\x1b[0m`);
        console.log(`Pull changes:  git fetch origin && git checkout ${targetBranch}\n`);
      } catch {
        // Already stopped
      }
      process.exit(0);
    };

    process.on('SIGINT', stopContainer);
    process.on('SIGTERM', stopContainer);

    // Windows-specific Ctrl+C handling
    if (process.platform === 'win32') {
      const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
      });
      rl.on('SIGINT', stopContainer);
      rl.on('close', () => { }); // Prevent default close behavior
    }

    logsProcess.on('close', (code) => {
      console.log(`\n\x1b[32mRalph finished.\x1b[0m`);
      console.log(`Pull changes:  git fetch origin && git checkout ${targetBranch}\n`);
      process.exit(0);
    });

  } catch (error) {
    console.error('\x1b[31mFailed to start background container:\x1b[0m', error.message);
    process.exit(1);
  }
}

function runRalph(spec, mode, iterations, verbose) {
  console.log(`\n\x1b[36mSpec: ${spec}\x1b[0m`);
  console.log(`\x1b[36mMode: ${mode}\x1b[0m`);
  console.log(`\x1b[36mIterations: ${iterations}\x1b[0m`);
  console.log(`\x1b[36mVerbose: ${verbose}\x1b[0m\n`);

  checkDockerImage();
  checkEnvFile();

  // Setup Windows signal handler now that interactive prompts are done
  setupWindowsSignalHandler();

  // Convert rootDir to Docker-compatible path for volume mount
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
    'bash', './.ralph/loop.sh',
    spec,
    mode,
    String(iterations),
  ];

  // Add verbose flag if enabled
  if (verbose) {
    dockerArgs.push('--verbose');
  }

  // Use spawn instead of spawnSync for better signal handling
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
    console.error('\x1b[31mFailed to start Docker:\x1b[0m', err.message);
    process.exit(1);
  });
}

async function interactivePrompt(preselectedMode = null) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (prompt) => new Promise((resolve) => rl.question(prompt, resolve));

  console.log('\n\x1b[33m🍩 Ralph Wiggum - Interactive Mode\x1b[0m\n');

  const availableSpecs = getAvailableSpecs();

  let spec = '';

  // Spec mode: always prompt for a name (can be new or existing)
  if (preselectedMode === 'spec') {
    if (availableSpecs.length > 0) {
      console.log('Existing specs:');
      availableSpecs.forEach((s, i) => {
        console.log(`  ${i + 1}. ${s}`);
      });
      console.log('');
    }
    while (!spec) {
      const input = await question('Enter spec name (new or existing): ');
      const trimmed = input.trim();
      const num = parseInt(trimmed);
      if (!isNaN(num) && num >= 1 && num <= availableSpecs.length) {
        spec = availableSpecs[num - 1];
      } else if (trimmed) {
        spec = trimmed.toLowerCase().replace(/[^a-z0-9-]/g, '-');
      }
    }
  } else if (availableSpecs.length === 1) {
    // Auto-select if only one spec available
    spec = availableSpecs[0];
    console.log(`\x1b[32mAuto-selected spec: ${spec}\x1b[0m\n`);
  } else if (availableSpecs.length > 1) {
    console.log('Available specs:');
    availableSpecs.forEach((s, i) => {
      const details = getSpecDetails(s);
      const suffix = details ? ` \x1b[36m[${details.complete}/${details.total} sub-specs]\x1b[0m` : '';
      console.log(`  ${i + 1}. ${s}${suffix}`);
    });
    console.log('');

    while (!spec) {
      const input = await question('Enter spec name (or number): ');
      const trimmed = input.trim();

      // Check if it's a number selection
      const num = parseInt(trimmed);
      if (!isNaN(num) && num >= 1 && num <= availableSpecs.length) {
        spec = availableSpecs[num - 1];
      } else if (trimmed) {
        if (validateSpec(trimmed)) {
          spec = trimmed;
        } else {
          console.log(`\x1b[31mSpec not found: .ralph/specs/${trimmed}.md\x1b[0m`);
        }
      }
    }
  } else {
    console.log('\x1b[33mNo specs found. Create one at .ralph/specs/<name>.md or use spec mode.\x1b[0m\n');
    rl.close();
    process.exit(1);
  }

  let mode = preselectedMode || '';

  if (preselectedMode) {
    console.log(`\x1b[32mMode: ${preselectedMode}\x1b[0m\n`);
  } else {
    console.log('Modes:');
    console.log('  1. plan       - Analyze codebase and create implementation plan');
    console.log('  2. build      - Implement tasks from the plan');
    console.log('  3. review     - Review implementation for bugs and issues');
    console.log('  4. review-fix - Fix issues identified during review');
    console.log('  5. debug      - Single iteration, verbose, no commits');
    console.log('  6. full       - Full cycle: plan → build → review → check (repeats until complete)');
    console.log('  7. decompose  - Break large spec into ordered sub-specs for full mode');
    console.log('  8. spec       - Create spec interactively: gather → research → draft → review');
    console.log('');

    while (!mode) {
      const input = await question('Select mode [1-8 or name] (default: build): ');
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
        console.log('\x1b[31mInvalid selection. Enter 1-8 or mode name.\x1b[0m');
      }
    }
  }

  // If spec mode was selected from the menu (not preselected), the spec name might not exist yet
  // In that case, the spec name was auto-selected or selected from the list — it's fine to use it
  // as the feature name for the new spec

  const defaultIterations = mode === 'plan' ? 5 : (mode === 'debug' ? 1 : (mode === 'decompose' ? 1 : (mode === 'spec' ? 8 : (mode === 'review-fix' ? 5 : (mode === 'full' ? 10 : 10)))));
  const iterLabel = mode === 'full' ? 'max cycles' : 'iterations';

  // Debug mode doesn't need iteration prompt
  if (mode === 'debug') {
    console.log('\x1b[33m⚠️  Debug mode: 1 iteration, verbose, no commits\x1b[0m\n');
  }

  // Decompose mode runs once
  if (mode === 'decompose') {
    console.log('\x1b[35mDecompose mode: breaking spec into sub-specs\x1b[0m\n');
  }
  const iterInput = await question(`Number of ${iterLabel} (default: ${defaultIterations}): `);
  const iterations = parseInt(iterInput.trim()) || defaultIterations;

  const verboseInput = await question('Verbose output? (default: No) [y/N]: ');
  const verbose = verboseInput.trim().toLowerCase() === 'y' || verboseInput.trim().toLowerCase() === 'yes';

  // Debug and decompose modes never run in background
  // Full mode defaults to background since it can run for hours
  let background = false;

  if (mode === 'debug' || mode === 'decompose' || mode === 'spec') {
    console.log(`\x1b[33m${mode.charAt(0).toUpperCase() + mode.slice(1)} mode always runs in foreground.\x1b[0m\n`);
    background = false;
  } else {
    const backgroundDefault = mode === 'full';
    const backgroundPrompt = backgroundDefault
      ? 'Run in background? (Ralph clones repo, you keep working) (default: Yes) [Y/n]: '
      : 'Run in background? (Ralph clones repo, you keep working) (default: No) [y/N]: ';
    const backgroundInput = await question(backgroundPrompt);
    const backgroundTrimmed = backgroundInput.trim().toLowerCase();

    if (backgroundDefault) {
      // For full mode, default is yes - only 'n' or 'no' turns it off
      background = backgroundTrimmed !== 'n' && backgroundTrimmed !== 'no';
    } else {
      // For other modes, default is no - only 'y' or 'yes' turns it on
      background = backgroundTrimmed === 'y' || backgroundTrimmed === 'yes';
    }
  }

  rl.close();

  // Spec mode: run gather wizard before launching Docker
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
  // Usage: run.js <spec-name> [plan|build|spec|...] [iterations] [--verbose] [--background]
  const spec = filteredArgs[0];

  // Determine mode first (needed for validation skip)
  let mode = preselectedMode || 'build';

  // Quick check: if positional arg is 'spec', set mode before validation
  if (filteredArgs[1] === 'spec') {
    mode = 'spec';
  }

  // Validate spec file exists (skip for spec mode — spec doesn't exist yet)
  if (mode !== 'spec' && !validateSpec(spec)) {
    console.error(`\x1b[31mError: Spec file not found: .ralph/specs/${spec}.md\x1b[0m`);
    const availableSpecs = getAvailableSpecs();
    if (availableSpecs.length > 0) {
      console.error('\nAvailable specs:');
      availableSpecs.forEach(s => console.error(`  - ${s}`));
    }
    process.exit(1);
  }

  // Parse mode and iterations (for full mode, iterations = cycles)
  // Priority: positional arg > --plan/--build/--review/--full/--spec flag > default (build)
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
    iterations = 1;  // Debug mode: single iteration, verbose, no commit
  } else if (filteredArgs[1] === 'full' || filteredArgs[1] === 'yolo') {
    mode = 'full';
    iterations = 10;  // 10 cycles by default (each cycle = plan + build + review + check)
    if (filteredArgs[2] && isNumeric(filteredArgs[2])) {
      iterations = parseInt(filteredArgs[2]);
    }
  } else if (filteredArgs[1] === 'decompose') {
    mode = 'decompose';
    iterations = 1;  // Decompose mode: single iteration
  } else if (filteredArgs[1] && isNumeric(filteredArgs[1])) {
    iterations = parseInt(filteredArgs[1]);
  }

  // Full mode defaults to background since it can run for hours
  // Debug mode never runs in background
  // Use --no-background or --foreground to override
  const noBackground = args.includes('--no-background') || args.includes('--foreground') || args.includes('-f');
  const useBackground = (mode === 'debug' || mode === 'decompose' || mode === 'spec') ? false : (noBackground ? false : (background || mode === 'full'));

  // Spec mode: run gather wizard before launching Docker (async wrapper)
  if (mode === 'spec') {
    specGatherWizard(spec).then(() => {
      setupWindowsSignalHandler();
      runRalph(spec, mode, iterations, verbose);
    }).catch((err) => {
      console.error(err);
      process.exit(1);
    });
  } else if (useBackground) {
    // Background mode - Ralph clones and works on his own copy
    runRalphBackground(spec, mode, iterations, verbose);
  } else {
    // Foreground mode - Ralph works on mounted local repo
    setupWindowsSignalHandler();
    runRalph(spec, mode, iterations, verbose);
  }
}
