#!/usr/bin/env node
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const rootDir = path.resolve(__dirname, '..');

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

function validateSpec(spec) {
  const specPath = path.join(rootDir, '.ralph', 'specs', `${spec}.md`);
  return fs.existsSync(specPath);
}

function checkDockerImage() {
  try {
    const images = execSync('docker images --format "{{.Repository}}"', {
      encoding: 'utf-8',
      cwd: rootDir,
    });
    if (!images.split('\n').includes('ralph-wiggum')) {
      console.log('Building ralph-wiggum image...');
      execSync('docker build -t ralph-wiggum -f .ralph/Dockerfile .', {
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
    'ralph-wiggum',
    './.ralph/loop.sh',
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

async function interactivePrompt() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (prompt) => new Promise((resolve) => rl.question(prompt, resolve));

  console.log('\n\x1b[33m🍩 Ralph Wiggum - Interactive Mode\x1b[0m\n');

  const availableSpecs = getAvailableSpecs();

  if (availableSpecs.length > 0) {
    console.log('Available specs:');
    availableSpecs.forEach((s, i) => console.log(`  ${i + 1}. ${s}`));
    console.log('');
  } else {
    console.log('\x1b[33mNo specs found. Create one at .ralph/specs/<name>.md\x1b[0m\n');
  }

  let spec = '';
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

  console.log('');
  console.log('Modes:');
  console.log('  1. plan  - Analyze codebase and create implementation plan');
  console.log('  2. build - Implement tasks from the plan');
  console.log('');

  let mode = '';
  while (!mode) {
    const input = await question('Select mode [1/2 or plan/build] (default: build): ');
    const trimmed = input.trim().toLowerCase();

    if (trimmed === '' || trimmed === '2' || trimmed === 'build') {
      mode = 'build';
    } else if (trimmed === '1' || trimmed === 'plan') {
      mode = 'plan';
    } else {
      console.log('\x1b[31mInvalid selection. Enter 1, 2, plan, or build.\x1b[0m');
    }
  }

  const defaultIterations = mode === 'plan' ? 5 : 10;
  const iterInput = await question(`Number of iterations (default: ${defaultIterations}): `);
  const iterations = parseInt(iterInput.trim()) || defaultIterations;

  const verboseInput = await question('Verbose output? [y/N]: ');
  const verbose = verboseInput.trim().toLowerCase() === 'y' || verboseInput.trim().toLowerCase() === 'yes';

  rl.close();

  runRalph(spec, mode, iterations, verbose);
}

// Setup signal handlers first
setupSignalHandlers();

// Main execution
const args = process.argv.slice(2);
const isNumeric = (str) => !isNaN(parseInt(str)) && isFinite(str);

// Check for verbose flag
const verbose = args.includes('--verbose') || args.includes('-v');
const filteredArgs = args.filter(a => a !== '--verbose' && a !== '-v');

// No arguments - interactive mode
if (filteredArgs.length === 0) {
  interactivePrompt().catch((err) => {
    console.error(err);
    process.exit(1);
  });
} else {
  // Parse arguments
  // Usage: run.js <spec-name> [plan|build] [iterations] [--verbose]
  const spec = filteredArgs[0];

  if (!validateSpec(spec)) {
    console.error(`\x1b[31mError: Spec file not found: .ralph/specs/${spec}.md\x1b[0m`);
    const availableSpecs = getAvailableSpecs();
    if (availableSpecs.length > 0) {
      console.error('\nAvailable specs:');
      availableSpecs.forEach(s => console.error(`  - ${s}`));
    }
    process.exit(1);
  }

  // Parse mode and iterations
  let mode = 'build';
  let iterations = 10;

  if (filteredArgs[1] === 'plan') {
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
  } else if (filteredArgs[1] && isNumeric(filteredArgs[1])) {
    iterations = parseInt(filteredArgs[1]);
  }

  // Setup Windows signal handler for non-interactive mode
  setupWindowsSignalHandler();

  runRalph(spec, mode, iterations, verbose);
}
