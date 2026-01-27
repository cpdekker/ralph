#!/usr/bin/env node
const { execSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const rootDir = path.resolve(__dirname, '..');

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

function runRalph(spec, mode, iterations) {
  console.log(`\n\x1b[36mSpec: ${spec}\x1b[0m`);
  console.log(`\x1b[36mMode: ${mode}\x1b[0m`);
  console.log(`\x1b[36mIterations: ${iterations}\x1b[0m\n`);

  checkDockerImage();
  checkEnvFile();

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

  const result = spawnSync('docker', dockerArgs, {
    stdio: 'inherit',
    cwd: rootDir,
    shell: true,
  });

  process.exit(result.status || 0);
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

  rl.close();

  runRalph(spec, mode, iterations);
}

// Main execution
const args = process.argv.slice(2);
const isNumeric = (str) => !isNaN(parseInt(str)) && isFinite(str);

// No arguments - interactive mode
if (args.length === 0) {
  interactivePrompt().catch((err) => {
    console.error(err);
    process.exit(1);
  });
} else {
  // Parse arguments
  // Usage: run.js <spec-name> [plan|build] [iterations]
  const spec = args[0];

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

  if (args[1] === 'plan') {
    mode = 'plan';
    iterations = 5;
    if (args[2] && isNumeric(args[2])) {
      iterations = parseInt(args[2]);
    }
  } else if (args[1] === 'build') {
    mode = 'build';
    iterations = 10;
    if (args[2] && isNumeric(args[2])) {
      iterations = parseInt(args[2]);
    }
  } else if (args[1] && isNumeric(args[1])) {
    iterations = parseInt(args[1]);
  }

  runRalph(spec, mode, iterations);
}
