#!/usr/bin/env node
/**
 * Ralph Wiggum - Interactive Setup Script
 * 
 * Helps users configure .ralph in their repository with guided prompts.
 * Run with: node .ralph/setup.js
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { execSync, spawn } = require('child_process');

const rootDir = path.resolve(__dirname, '..');
const ralphDir = path.join(rootDir, '.ralph');

// ANSI color codes
const colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    dim: '\x1b[2m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m',
};

const c = (color, text) => `${colors[color]}${text}${colors.reset}`;

function printBanner() {
    console.log('');
    console.log(c('yellow', '  🍩 Ralph Wiggum - Setup Wizard'));
    console.log(c('dim', '  ─────────────────────────────────'));
    console.log('');
}

function printStep(step, total, description) {
    console.log('');
    console.log(c('cyan', `  [${step}/${total}] ${description}`));
    console.log(c('dim', '  ' + '─'.repeat(40)));
}

function printSuccess(message) {
    console.log(c('green', `  ✓ ${message}`));
}

function printWarning(message) {
    console.log(c('yellow', `  ⚠ ${message}`));
}

function printError(message) {
    console.log(c('red', `  ✗ ${message}`));
}

function printInfo(message) {
    console.log(c('dim', `    ${message}`));
}

// Spinner for long-running operations
function createSpinner(message) {
    const frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
    let i = 0;
    let startTime = Date.now();

    const interval = setInterval(() => {
        const elapsed = Math.floor((Date.now() - startTime) / 1000);
        const minutes = Math.floor(elapsed / 60);
        const seconds = elapsed % 60;
        const timeStr = minutes > 0
            ? `${minutes}m ${seconds}s`
            : `${seconds}s`;

        process.stdout.write(`\r  ${c('cyan', frames[i])} ${message} ${c('dim', `(${timeStr})`)}`);
        i = (i + 1) % frames.length;
    }, 80);

    return {
        stop: (success = true) => {
            clearInterval(interval);
            const elapsed = Math.floor((Date.now() - startTime) / 1000);
            const minutes = Math.floor(elapsed / 60);
            const seconds = elapsed % 60;
            const timeStr = minutes > 0
                ? `${minutes}m ${seconds}s`
                : `${seconds}s`;

            // Clear the line and print final status
            process.stdout.write('\r' + ' '.repeat(80) + '\r');
            if (success) {
                console.log(`  ${c('green', '✓')} ${message} ${c('dim', `(${timeStr})`)}`);
            } else {
                console.log(`  ${c('red', '✗')} ${message} ${c('dim', `(${timeStr})`)}`);
            }
        }
    };
}

async function createReadlineInterface() {
    return readline.createInterface({
        input: process.stdin,
        output: process.stdout,
    });
}

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

// Step 1: Check prerequisites
function checkPrerequisites() {
    const issues = [];

    // Check Docker
    try {
        execSync('docker --version', { stdio: 'ignore' });
    } catch {
        issues.push('Docker is not installed or not in PATH');
    }

    // Check if Docker daemon is running
    try {
        execSync('docker info', { stdio: 'ignore' });
    } catch {
        issues.push('Docker daemon is not running');
    }

    // Check Node.js version
    const nodeVersion = process.version;
    const major = parseInt(nodeVersion.slice(1).split('.')[0]);
    if (major < 18) {
        issues.push(`Node.js 18+ required (current: ${nodeVersion})`);
    }

    // Check Git
    try {
        execSync('git --version', { stdio: 'ignore' });
    } catch {
        issues.push('Git is not installed or not in PATH');
    }

    // Check if we're in a git repo
    try {
        execSync('git rev-parse --git-dir', { cwd: rootDir, stdio: 'ignore' });
    } catch {
        issues.push('Not inside a Git repository');
    }

    return issues;
}

// Step 2: Setup .env file
async function setupEnvFile(rl) {
    const envPath = path.join(ralphDir, '.env');
    const envExamplePath = path.join(ralphDir, '.env.example');

    if (fs.existsSync(envPath)) {
        printSuccess('.env file already exists');
        const overwrite = await confirm(rl, 'Do you want to reconfigure it?', false);
        if (!overwrite) {
            return true;
        }
    }

    if (!fs.existsSync(envExamplePath)) {
        printError('.env.example not found. Cannot create .env template.');
        return false;
    }

    console.log('');
    printInfo('Configure your API credentials:');
    console.log('');

    // Get AWS Bedrock token
    console.log(c('dim', '    AWS Bedrock Token (recommended):'));
    console.log(c('dim', '    Get from: https://us-west-2.console.aws.amazon.com/bedrock/home?region=us-west-2#/api-keys'));
    const awsToken = await question(rl, 'AWS_BEARER_TOKEN_BEDROCK', '');

    console.log('');

    // Get Git credentials
    console.log(c('dim', '    Git credentials for pushing changes:'));
    console.log(c('dim', '    Token: https://github.com/settings/tokens (needs repo scope)'));

    // Try to get default git user from git config
    let defaultGitUser = '';
    try {
        defaultGitUser = execSync('git config user.name', { encoding: 'utf-8', cwd: rootDir }).trim();
    } catch {
        // Ignore
    }

    const gitUser = await question(rl, 'GIT_USER (GitHub username)', defaultGitUser);
    const gitToken = await question(rl, 'GIT_TOKEN (Personal Access Token)', '');

    // Read the example and create the .env
    let envContent = fs.readFileSync(envExamplePath, 'utf-8');

    // Replace placeholders with actual values
    envContent = envContent.replace(/^AWS_BEARER_TOKEN_BEDROCK=.*$/m, `AWS_BEARER_TOKEN_BEDROCK=${awsToken}`);
    envContent = envContent.replace(/^GIT_USER=.*$/m, `GIT_USER=${gitUser}`);
    envContent = envContent.replace(/^GIT_TOKEN=.*$/m, `GIT_TOKEN=${gitToken}`);

    fs.writeFileSync(envPath, envContent);
    printSuccess('.env file created');

    // Validate that at least API key is set
    if (!awsToken) {
        printWarning('No API token provided. You will need to edit .ralph/.env manually.');
    }
    if (!gitToken) {
        printWarning('No Git token provided. Ralph won\'t be able to push changes.');
    }

    return true;
}

// Step 3: Setup .gitignore
function setupGitignore() {
    const gitignorePath = path.join(rootDir, '.gitignore');
    const entryToAdd = '.ralph/.env';

    let content = '';
    if (fs.existsSync(gitignorePath)) {
        content = fs.readFileSync(gitignorePath, 'utf-8');
    }

    // Check if already in gitignore
    const lines = content.split('\n').map(l => l.trim());
    if (lines.includes(entryToAdd) || lines.includes('.ralph/.env')) {
        printSuccess('.ralph/.env is already in .gitignore');
        return;
    }

    // Add to gitignore
    const newContent = content.trimEnd() + '\n\n# Ralph\n.ralph/.env\n';
    fs.writeFileSync(gitignorePath, newContent);
    printSuccess('Added .ralph/.env to .gitignore');
}

// Step 4: Setup npm scripts (if package.json exists)
async function setupNpmScripts(rl) {
    const packageJsonPath = path.join(rootDir, 'package.json');

    if (!fs.existsSync(packageJsonPath)) {
        printInfo('No package.json found, skipping npm scripts setup');
        return;
    }

    let packageJson;
    try {
        packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'));
    } catch (error) {
        printWarning('Could not parse package.json');
        return;
    }

    // Initialize scripts object if it doesn't exist
    if (!packageJson.scripts) {
        packageJson.scripts = {};
    }

    const ralphScripts = {
        'ralph': 'node .ralph/run.js',
        'ralph:plan': 'node .ralph/run.js --plan',
        'ralph:build': 'node .ralph/run.js --build',
        'ralph:review': 'node .ralph/run.js --review',
        'ralph:full': 'node .ralph/run.js --full',
        'ralph:yolo': 'node .ralph/run.js --full',
        'ralph:docker': 'node .ralph/docker-build.js',
        'ralph:setup': 'node .ralph/setup.js',
    };

    // Check which scripts already exist
    const existingScripts = Object.keys(ralphScripts).filter(key => packageJson.scripts[key]);
    const missingScripts = Object.keys(ralphScripts).filter(key => !packageJson.scripts[key]);

    if (existingScripts.length === Object.keys(ralphScripts).length) {
        printSuccess('All Ralph npm scripts already configured');
        return;
    }

    if (existingScripts.length > 0) {
        printSuccess(`Found existing scripts: ${existingScripts.join(', ')}`);
    }

    if (missingScripts.length === 0) {
        return;
    }

    console.log('');
    printInfo('Add npm scripts for easier Ralph usage:');
    console.log('');
    for (const script of missingScripts) {
        console.log(c('dim', `    "${script}": "${ralphScripts[script]}"`));
    }
    console.log('');

    const addScripts = await confirm(rl, 'Add these scripts to package.json?', true);

    if (!addScripts) {
        printInfo('You can add them manually later.');
        return;
    }

    // Add missing scripts
    for (const script of missingScripts) {
        packageJson.scripts[script] = ralphScripts[script];
    }

    // Write back to package.json with proper formatting
    fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2) + '\n');
    printSuccess(`Added ${missingScripts.length} npm script(s) to package.json`);
    printInfo('You can now run: npm run ralph');
}

// Step 5: Setup AGENTS.md (uses Claude)
async function setupAgentsMd(rl) {
    const agentsPath = path.join(ralphDir, 'AGENTS.md');

    if (!fs.existsSync(agentsPath)) {
        printError('AGENTS.md not found');
        return;
    }

    const content = fs.readFileSync(agentsPath, 'utf-8');

    // Check if it's still the template (look for placeholder text)
    const isTemplate = content.includes('[Instructions for how Ralph can build and run tests in the project]');

    if (!isTemplate) {
        printSuccess('AGENTS.md appears to be configured');
        return;
    }

    printWarning('AGENTS.md contains template placeholders');
    console.log('');
    printInfo('AGENTS.md tells Ralph how to build and test your project.');
    printInfo('You need to customize it with your project\'s commands.');
    console.log('');

    const generateNow = await confirm(rl, 'Would you like to generate AGENTS.md using Claude?', true);

    if (!generateNow) {
        printInfo('You can edit .ralph/AGENTS.md manually later.');
        return;
    }

    // Check if claude CLI is available
    let claudeAvailable = false;
    try {
        execSync('claude --version', { stdio: 'ignore' });
        claudeAvailable = true;
    } catch {
        // Claude CLI not installed
    }

    if (!claudeAvailable) {
        printWarning('Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-code');
        console.log('');
        printInfo('Once installed, run this command to generate AGENTS.md:');
        console.log('');
        console.log(c('dim', '    claude -p --dangerously-skip-permissions "Analyze this codebase and create a .ralph/AGENTS.md file. Include:'));
        console.log(c('dim', '    1. Build & Validate - Commands to build, test, and lint the project'));
        console.log(c('dim', '    2. Critical Rules - Important patterns, conventions, or gotchas'));
        console.log(c('dim', '    3. Project Structure - Brief overview of where key code lives'));
        console.log(c('dim', '    4. Key Patterns - Architecture patterns used'));
        console.log(c('dim', '    5. Git - Any specific git workflows or branch naming conventions'));
        console.log(c('dim', '    Keep it brief and operational—this file is loaded into every AI iteration\'s context."'));
        console.log('');
        return;
    }

    console.log('');
    printInfo('Running Claude to analyze your codebase and generate AGENTS.md...');
    printInfo('This may take several minutes depending on the size of your codebase.');
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
            // Use --dangerously-skip-permissions to auto-approve file operations
            // Without this, Claude prompts for permission and hangs waiting for input
            // Pass prompt via stdin (like loop.sh does) using 'pipe' for stdin
            const claudeProcess = spawn('claude', [
                '-p',
                '--dangerously-skip-permissions',
            ], {
                cwd: rootDir,
                shell: true,
                stdio: ['pipe', 'pipe', 'pipe'],
            });

            let stdout = '';
            let stderr = '';

            claudeProcess.stdout.on('data', (data) => {
                stdout += data.toString();
            });

            claudeProcess.stderr.on('data', (data) => {
                stderr += data.toString();
            });

            claudeProcess.on('close', (code) => {
                if (code === 0) {
                    resolve(stdout);
                } else {
                    reject(new Error(stderr || stdout || `Claude exited with code ${code}`));
                }
            });

            claudeProcess.on('error', (err) => {
                reject(err);
            });

            // Write prompt to stdin and close it (like: echo "prompt" | claude -p)
            claudeProcess.stdin.write(claudePrompt);
            claudeProcess.stdin.end();
        });

        spinner.stop(true);
        console.log('');
        printSuccess('AGENTS.md generated by Claude');
        printInfo('Review and refine it at .ralph/AGENTS.md');
    } catch (error) {
        spinner.stop(false);
        console.log('');
        printError(`Claude failed to generate AGENTS.md: ${error.message}`);
        printInfo('You can edit .ralph/AGENTS.md manually or try running Claude again.');
    }
}

// Step 6: Build Docker image (optional)
async function buildDockerImage(rl) {
    const repoName = path.basename(rootDir).toLowerCase().replace(/[^a-z0-9-]/g, '-');
    const imageName = `ralph-wiggum-${repoName}`;

    // Check if image already exists
    try {
        const images = execSync('docker images --format "{{.Repository}}"', { encoding: 'utf-8' });
        if (images.split('\n').includes(imageName)) {
            printSuccess(`Docker image '${imageName}' already exists`);
            const rebuild = await confirm(rl, 'Would you like to rebuild it?', false);
            if (!rebuild) {
                return;
            }
        }
    } catch {
        printWarning('Could not check Docker images');
        return;
    }

    const build = await confirm(rl, 'Would you like to build the Docker image now?', true);

    if (!build) {
        printInfo('Run "node .ralph/docker-build.js" later to build.');
        return;
    }

    console.log('');
    printInfo('Building Docker image (this may take a few minutes)...');
    console.log('');

    try {
        execSync(`docker build -t ${imageName} -f .ralph/Dockerfile .`, {
            cwd: rootDir,
            stdio: 'inherit',
        });
        console.log('');
        printSuccess(`Docker image '${imageName}' built successfully`);
    } catch {
        printError('Docker build failed. Try running "node .ralph/docker-build.js" manually.');
    }
}

// Print final summary
function printSummary() {
    const packageJsonPath = path.join(rootDir, 'package.json');
    const hasPackageJson = fs.existsSync(packageJsonPath);

    console.log('');
    console.log(c('dim', '  ─────────────────────────────────────────'));
    console.log(c('green', '  🎉 Setup Complete!'));
    console.log(c('dim', '  ─────────────────────────────────────────'));
    console.log('');
    console.log('  Next steps:');
    console.log('');
    console.log(c('cyan', '  1.') + ' Review .ralph/AGENTS.md and refine if needed');
    console.log('');
    console.log(c('cyan', '  2.') + ' Create your feature spec:');
    console.log(c('dim', '     • Copy .ralph/specs/sample.md to .ralph/specs/<feature-name>.md'));
    console.log(c('dim', '     • Or use .ralph/prompts/requirements.md to gather requirements'));
    console.log('');
    console.log(c('cyan', '  3.') + ' Run Ralph:');
    if (hasPackageJson) {
        console.log(c('dim', '     npm run ralph              ') + '# Interactive mode');
        console.log(c('dim', '     npm run ralph:plan         ') + '# Interactive with plan mode');
        console.log(c('dim', '     npm run ralph:build        ') + '# Interactive with build mode');
        console.log(c('dim', '     npm run ralph:review       ') + '# Interactive with review mode');
        console.log(c('dim', '     npm run ralph:full         ') + '# Full cycle: plan→build→review→check');
    } else {
        console.log(c('dim', '     node .ralph/run.js              ') + '# Interactive mode');
        console.log(c('dim', '     node .ralph/run.js <spec> plan  ') + '# Create implementation plan');
        console.log(c('dim', '     node .ralph/run.js <spec> build ') + '# Start building');
        console.log(c('dim', '     node .ralph/run.js <spec> review') + '# Review implementation');
        console.log(c('dim', '     node .ralph/run.js <spec> full  ') + '# Full cycle: plan→build→review→check');
    }
    console.log('');
}

// Main setup flow
async function main() {
    printBanner();

    const totalSteps = 6;

    // Step 1: Prerequisites
    printStep(1, totalSteps, 'Checking prerequisites');
    const issues = checkPrerequisites();

    if (issues.length > 0) {
        for (const issue of issues) {
            printError(issue);
        }
        console.log('');
        printWarning('Please fix the above issues before continuing.');
        console.log('');
        process.exit(1);
    }
    printSuccess('All prerequisites met');

    const rl = await createReadlineInterface();

    try {
        // Step 2: .env file
        printStep(2, totalSteps, 'Configuring environment (.env)');
        await setupEnvFile(rl);

        // Step 3: .gitignore
        printStep(3, totalSteps, 'Updating .gitignore');
        setupGitignore();

        // Step 4: npm scripts
        printStep(4, totalSteps, 'Setting up npm scripts');
        await setupNpmScripts(rl);

        // Step 5: AGENTS.md
        printStep(5, totalSteps, 'Configuring AGENTS.md');
        await setupAgentsMd(rl);

        // Step 6: Docker image
        printStep(6, totalSteps, 'Docker image');
        await buildDockerImage(rl);

        // Done!
        printSummary();

    } finally {
        rl.close();
    }
}

// Run
main().catch((err) => {
    console.error('');
    printError(`Setup failed: ${err.message}`);
    console.error('');
    process.exit(1);
});
