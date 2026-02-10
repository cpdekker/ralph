const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { execSync, spawn } = require('child_process');
const { c, success, warn, error, info, step, createSpinner } = require('../utils/colors');
const { repoDir, ralphDir, libDir } = require('../utils/paths');
const { isGitRepo } = require('../utils/git');
const { isDockerAvailable, isDockerRunning, ensureImage, getImageName } = require('../utils/docker');

async function question(rl, prompt, defaultValue = '') {
  const defaultHint = defaultValue ? c('dim', ` (${defaultValue})`) : '';
  return new Promise((resolve) => {
    rl.question(`  ${prompt}${defaultHint}: `, (answer) => {
      resolve(answer.trim() || defaultValue);
    });
  });
}

async function confirm(rl, prompt, defaultYes = true) {
  const hint = defaultYes ? '[Y/n]' : '[y/N]';
  const answer = await question(rl, `${prompt} ${hint}`, defaultYes ? 'y' : 'n');
  return answer.toLowerCase() === 'y' || answer.toLowerCase() === 'yes';
}

function checkPrerequisites() {
  const issues = [];

  if (!isDockerAvailable()) issues.push('Docker is not installed or not in PATH');
  else if (!isDockerRunning()) issues.push('Docker daemon is not running');

  const major = parseInt(process.version.slice(1).split('.')[0]);
  if (major < 18) issues.push(`Node.js 18+ required (current: ${process.version})`);

  try { execSync('git --version', { stdio: 'ignore' }); }
  catch { issues.push('Git is not installed or not in PATH'); }

  if (!isGitRepo(repoDir())) issues.push('Not inside a Git repository');

  return issues;
}

async function setupEnvFile(rl) {
  const rd = ralphDir();
  const envPath = path.join(rd, '.env');
  const envExampleSrc = path.join(libDir, 'templates', '.env.example');

  if (fs.existsSync(envPath)) {
    success('.env file already exists');
    const overwrite = await confirm(rl, 'Do you want to reconfigure it?', false);
    if (!overwrite) return true;
  }

  console.log('');
  info('Configure your API credentials:');
  console.log('');

  console.log(c('dim', '    AWS Bedrock Token (recommended):'));
  console.log(c('dim', '    Get from: https://us-west-2.console.aws.amazon.com/bedrock/home?region=us-west-2#/api-keys'));
  const awsToken = await question(rl, 'AWS_BEARER_TOKEN_BEDROCK', '');
  console.log('');

  console.log(c('dim', '    Git credentials for pushing changes:'));
  console.log(c('dim', '    Token: https://github.com/settings/tokens (needs repo scope)'));

  let defaultGitUser = '';
  try { defaultGitUser = execSync('git config user.name', { encoding: 'utf-8', cwd: repoDir() }).trim(); } catch {}

  const gitUser = await question(rl, 'GIT_USER (GitHub username)', defaultGitUser);
  const gitToken = await question(rl, 'GIT_TOKEN (Personal Access Token)', '');

  let envContent = fs.readFileSync(envExampleSrc, 'utf-8');
  envContent = envContent.replace(/^AWS_BEARER_TOKEN_BEDROCK=.*$/m, `AWS_BEARER_TOKEN_BEDROCK=${awsToken}`);
  envContent = envContent.replace(/^GIT_USER=.*$/m, `GIT_USER=${gitUser}`);
  envContent = envContent.replace(/^GIT_TOKEN=.*$/m, `GIT_TOKEN=${gitToken}`);

  fs.writeFileSync(envPath, envContent);
  success('.env file created');

  if (!awsToken) warn('No API token provided. You will need to edit .ralph/.env manually.');
  if (!gitToken) warn("No Git token provided. Ralph won't be able to push changes.");

  return true;
}

function setupGitignore() {
  const gitignorePath = path.join(repoDir(), '.gitignore');
  const entriesToAdd = ['.ralph/.env', '.ralph/state.json'];

  let content = '';
  if (fs.existsSync(gitignorePath)) {
    content = fs.readFileSync(gitignorePath, 'utf-8');
  }

  const lines = content.split('\n').map(l => l.trim());
  const missing = entriesToAdd.filter(e => !lines.includes(e));

  if (missing.length === 0) {
    success('.ralph/.env is already in .gitignore');
    return;
  }

  const newContent = content.trimEnd() + '\n\n# Ralph\n' + missing.join('\n') + '\n';
  fs.writeFileSync(gitignorePath, newContent);
  success('Added Ralph entries to .gitignore');
}

async function setupAgentsMd(rl) {
  const rd = ralphDir();
  const agentsPath = path.join(rd, 'AGENTS.md');
  const content = fs.readFileSync(agentsPath, 'utf-8');

  const isTemplate = content.includes('[Instructions for how Ralph can build and run tests in the project]');

  if (!isTemplate) {
    success('AGENTS.md appears to be configured');
    return;
  }

  warn('AGENTS.md contains template placeholders');
  console.log('');
  info('AGENTS.md tells Ralph how to build and test your project.');
  info("You need to customize it with your project's commands.");
  console.log('');

  const generateNow = await confirm(rl, 'Would you like to generate AGENTS.md using Claude?', true);

  if (!generateNow) {
    info('You can edit .ralph/AGENTS.md manually later.');
    return;
  }

  let claudeAvailable = false;
  try { execSync('claude --version', { stdio: 'ignore' }); claudeAvailable = true; } catch {}

  if (!claudeAvailable) {
    warn('Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-code');
    console.log('');
    info('Once installed, run `ralph init` again to generate AGENTS.md.');
    return;
  }

  console.log('');
  info('Running Claude to analyze your codebase and generate AGENTS.md...');
  console.log('');

  const claudePrompt = `Analyze this codebase and create a .ralph/AGENTS.md file. Include:
1. **Build & Validate** - Commands to build, test, and lint the project
2. **Critical Rules** - Important patterns, conventions, or gotchas specific to this codebase
3. **Project Structure** - Brief overview of where key code lives
4. **Key Patterns** - Architecture patterns used (e.g., repository pattern, dependency injection)
5. **Git** - Any specific git workflows or branch naming conventions

Keep it brief and operational—this file is loaded into every AI iteration's context.`;

  const spinner = createSpinner('Claude is analyzing your codebase...');

  try {
    await new Promise((resolve, reject) => {
      const claudeProcess = spawn('claude', ['-p', '--dangerously-skip-permissions'], {
        cwd: repoDir(),
        shell: true,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      let stdout = '';
      let stderr = '';
      claudeProcess.stdout.on('data', (data) => { stdout += data.toString(); });
      claudeProcess.stderr.on('data', (data) => { stderr += data.toString(); });
      claudeProcess.on('close', (code) => {
        if (code === 0) resolve(stdout);
        else reject(new Error(stderr || stdout || `Claude exited with code ${code}`));
      });
      claudeProcess.on('error', reject);
      claudeProcess.stdin.write(claudePrompt);
      claudeProcess.stdin.end();
    });

    spinner.stop(true);
    console.log('');
    success('AGENTS.md generated by Claude');
    info('Review and refine it at .ralph/AGENTS.md');
  } catch (err) {
    spinner.stop(false);
    console.log('');
    error(`Claude failed to generate AGENTS.md: ${err.message}`);
    info('You can edit .ralph/AGENTS.md manually or try running Claude again.');
  }
}

async function buildDockerImageStep(rl) {
  const imageName = getImageName();

  try {
    const images = execSync('docker images --format "{{.Repository}}"', { encoding: 'utf-8' });
    if (images.split('\n').includes(imageName)) {
      success(`Docker image '${imageName}' already exists`);
      const rebuild = await confirm(rl, 'Would you like to rebuild it?', false);
      if (!rebuild) return;
    }
  } catch {
    warn('Could not check Docker images');
    return;
  }

  const build = await confirm(rl, 'Would you like to build the Docker image now?', true);
  if (!build) {
    info('Run "ralph build" later and the image will be built automatically.');
    return;
  }

  console.log('');
  info('Building Docker image (this may take a few minutes)...');
  console.log('');

  try {
    ensureImage(imageName);
    console.log('');
    success(`Docker image '${imageName}' built successfully`);
  } catch {
    error('Docker build failed. Try running "ralph init" again.');
  }
}

function scaffoldRalphDir() {
  const rd = ralphDir();
  const templatesDir = path.join(libDir, 'templates');

  // Create directories
  fs.mkdirSync(path.join(rd, 'specs'), { recursive: true });
  fs.mkdirSync(path.join(rd, 'insights', 'iteration_logs'), { recursive: true });

  // Copy template files
  const filesToCopy = [
    { src: 'AGENTS.md', dest: 'AGENTS.md' },
    { src: 'IMPLEMENTATION_PLAN.md', dest: 'IMPLEMENTATION_PLAN.md' },
    { src: 'user-review.md', dest: 'user-review.md' },
    { src: '.env.example', dest: '.env.example' },
    { src: 'sample.md', dest: path.join('specs', 'sample.md') },
    { src: 'README.md', dest: 'README.md' },
  ];

  for (const { src, dest } of filesToCopy) {
    const destPath = path.join(rd, dest);
    if (!fs.existsSync(destPath)) {
      fs.copyFileSync(path.join(templatesDir, src), destPath);
    }
  }
}

async function run() {
  console.log('');
  console.log(c('yellow', '  Ralph Wiggum - Setup'));
  console.log(c('dim', '  ─────────────────────────────────'));
  console.log('');

  const totalSteps = 6;

  // Step 1: Prerequisites
  step(1, totalSteps, 'Checking prerequisites');
  const issues = checkPrerequisites();
  if (issues.length > 0) {
    for (const issue of issues) error(issue);
    console.log('');
    warn('Please fix the above issues before continuing.');
    console.log('');
    process.exit(1);
  }
  success('All prerequisites met');

  // Step 2: Scaffold .ralph directory
  step(2, totalSteps, 'Creating .ralph directory');
  const rd = ralphDir();
  if (fs.existsSync(rd)) {
    success('.ralph directory already exists');
  } else {
    scaffoldRalphDir();
    success('.ralph directory created');
  }
  // Always ensure all template files exist (for upgrades)
  scaffoldRalphDir();

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

  try {
    // Step 3: .env file
    step(3, totalSteps, 'Configuring environment (.env)');
    await setupEnvFile(rl);

    // Step 4: .gitignore
    step(4, totalSteps, 'Updating .gitignore');
    setupGitignore();

    // Step 5: AGENTS.md
    step(5, totalSteps, 'Configuring AGENTS.md');
    await setupAgentsMd(rl);

    // Step 6: Docker image
    step(6, totalSteps, 'Docker image');
    await buildDockerImageStep(rl);

    // Summary
    console.log('');
    console.log(c('dim', '  ─────────────────────────────────────────'));
    console.log(c('green', '  Setup Complete!'));
    console.log(c('dim', '  ─────────────────────────────────────────'));
    console.log('');
    console.log('  Next steps:');
    console.log('');
    console.log(c('cyan', '  1.') + ' Review .ralph/AGENTS.md and refine if needed');
    console.log('');
    console.log(c('cyan', '  2.') + ' Create your feature spec:');
    console.log(c('dim', '     Copy .ralph/specs/sample.md to .ralph/specs/<feature-name>.md'));
    console.log(c('dim', '     Or run: ralph spec <feature-name>'));
    console.log('');
    console.log(c('cyan', '  3.') + ' Run Ralph:');
    console.log(c('dim', '     ralph plan <spec>         ') + '# Create implementation plan');
    console.log(c('dim', '     ralph build <spec>        ') + '# Start building');
    console.log(c('dim', '     ralph review <spec>       ') + '# Review implementation');
    console.log(c('dim', '     ralph full <spec>         ') + '# Full cycle: plan→build→review→check');
    console.log(c('dim', '     ralph                     ') + '# Interactive mode');
    console.log('');
    console.log(c('cyan', '  4.') + ' Read .ralph/README.md for full usage guide');
    console.log('');
  } finally {
    rl.close();
  }
}

module.exports = { run };
