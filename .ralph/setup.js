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
const ui = require('./lib/ui');
const { c, success, warn, error, info, step, header, separator, createSpinner, startupBanner, hint } = ui;

const rootDir = path.resolve(__dirname, '..');
const ralphDir = path.join(rootDir, '.ralph');

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
    const hintStr = defaultYes ? '[Y/n]' : '[y/N]';
    const answer = await question(rl, `${prompt} ${hintStr}`, defaultYes ? 'y' : 'n');
    return answer.toLowerCase() === 'y' || answer.toLowerCase() === 'yes';
}

// Step 1: Check prerequisites
function checkPrerequisites() {
    const issues = [];

    try {
        execSync('docker --version', { stdio: 'ignore' });
    } catch {
        issues.push('Docker is not installed or not in PATH');
    }

    try {
        execSync('docker info', { stdio: 'ignore' });
    } catch {
        issues.push('Docker daemon is not running');
    }

    const nodeVersion = process.version;
    const major = parseInt(nodeVersion.slice(1).split('.')[0]);
    if (major < 18) {
        issues.push(`Node.js 18+ required (current: ${nodeVersion})`);
    }

    try {
        execSync('git --version', { stdio: 'ignore' });
    } catch {
        issues.push('Git is not installed or not in PATH');
    }

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
        success('.env file already exists');
        const overwrite = await confirm(rl, 'Do you want to reconfigure it?', false);
        if (!overwrite) {
            return true;
        }
    }

    if (!fs.existsSync(envExamplePath)) {
        error('.env.example not found. Cannot create .env template.');
        return false;
    }

    console.log('');
    info('Select your Claude API provider:');
    console.log('');
    console.log(c('dim', '    1. Anthropic API (simplest — get key at console.anthropic.com)'));
    console.log(c('dim', '    2. AWS Bedrock'));
    console.log(c('dim', '    3. Google Cloud Vertex AI'));
    console.log('');

    const providerChoice = await question(rl, 'Provider [1-3]', '1');
    console.log('');

    let envLines = [];

    if (providerChoice === '2') {
        info('AWS Bedrock configuration:');
        console.log(c('dim', '    Docs: https://docs.anthropic.com/en/docs/claude-code/bedrock-vertex'));
        console.log('');
        console.log(c('dim', '    Choose auth method:'));
        console.log(c('dim', '    1. IAM credentials (AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY)'));
        console.log(c('dim', '    2. Bearer token (short-term API key from Bedrock console)'));
        console.log('');
        const bedrockAuth = await question(rl, 'Auth method [1-2]', '1');
        const awsRegion = await question(rl, 'AWS_REGION', 'us-west-2');
        console.log('');

        envLines.push('CLAUDE_CODE_USE_BEDROCK=1');
        envLines.push(`AWS_REGION=${awsRegion}`);

        if (bedrockAuth === '2') {
            const bearerToken = await question(rl, 'AWS_BEARER_TOKEN_BEDROCK', '');
            envLines.push(`AWS_BEARER_TOKEN_BEDROCK=${bearerToken}`);
            if (!bearerToken) {
                warn('No bearer token provided. You will need to edit .ralph/.env manually.');
            }
        } else {
            const accessKey = await question(rl, 'AWS_ACCESS_KEY_ID', '');
            const secretKey = await question(rl, 'AWS_SECRET_ACCESS_KEY', '');
            envLines.push(`AWS_ACCESS_KEY_ID=${accessKey}`);
            envLines.push(`AWS_SECRET_ACCESS_KEY=${secretKey}`);
            if (!accessKey || !secretKey) {
                warn('Incomplete AWS credentials. You will need to edit .ralph/.env manually.');
            }
        }
    } else if (providerChoice === '3') {
        info('Google Cloud Vertex AI configuration:');
        console.log(c('dim', '    Docs: https://docs.anthropic.com/en/docs/claude-code/bedrock-vertex'));
        console.log(c('dim', '    Ensure you have authenticated via: gcloud auth application-default login'));
        console.log('');
        const gcpProject = await question(rl, 'ANTHROPIC_VERTEX_PROJECT_ID', '');
        const gcpRegion = await question(rl, 'CLOUD_ML_REGION', 'us-east5');

        envLines.push('CLAUDE_CODE_USE_VERTEX=1');
        envLines.push(`ANTHROPIC_VERTEX_PROJECT_ID=${gcpProject}`);
        envLines.push(`CLOUD_ML_REGION=${gcpRegion}`);

        if (!gcpProject) {
            warn('No GCP project ID provided. You will need to edit .ralph/.env manually.');
        }
    } else {
        info('Anthropic API configuration:');
        console.log(c('dim', '    Get your key at: https://console.anthropic.com/settings/keys'));
        console.log('');
        const apiKey = await question(rl, 'ANTHROPIC_API_KEY', '');

        envLines.push(`ANTHROPIC_API_KEY=${apiKey}`);

        if (!apiKey) {
            warn('No API key provided. You will need to edit .ralph/.env manually.');
        }
    }

    console.log('');

    console.log(c('dim', '    Git credentials for pushing changes:'));
    console.log(c('dim', '    Token: https://github.com/settings/tokens (needs repo scope)'));

    let defaultGitUser = '';
    try {
        defaultGitUser = execSync('git config user.name', { encoding: 'utf-8', cwd: rootDir }).trim();
    } catch {
        // Ignore
    }

    const gitUser = await question(rl, 'GIT_USER (GitHub username)', defaultGitUser);
    const gitToken = await question(rl, 'GIT_TOKEN (Personal Access Token)', '');

    let envContent = '# Ralph Wiggum Environment Configuration\n';
    envContent += '# Generated by setup wizard\n\n';
    envContent += '# API Provider\n';
    envLines.forEach(line => { envContent += line + '\n'; });
    envContent += '\n# Git credentials\n';
    envContent += `GIT_USER=${gitUser}\n`;
    envContent += `GIT_TOKEN=${gitToken}\n`;

    fs.writeFileSync(envPath, envContent);
    success('.env file created');

    if (!gitToken) {
        warn('No Git token provided. Ralph won\'t be able to push changes.');
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

    const lines = content.split('\n').map(l => l.trim());
    if (lines.includes(entryToAdd) || lines.includes('.ralph/.env')) {
        success('.ralph/.env is already in .gitignore');
        return;
    }

    const newContent = content.trimEnd() + '\n\n# Ralph\n.ralph/.env\n';
    fs.writeFileSync(gitignorePath, newContent);
    success('Added .ralph/.env to .gitignore');
}

// Step 4: Setup npm scripts
async function setupNpmScripts(rl) {
    const packageJsonPath = path.join(rootDir, 'package.json');

    if (!fs.existsSync(packageJsonPath)) {
        info('No package.json found, skipping npm scripts setup');
        return;
    }

    let packageJson;
    try {
        packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'));
    } catch (err) {
        warn('Could not parse package.json');
        return;
    }

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
        'ralph:decompose': 'node .ralph/run.js --decompose',
        'ralph:spec': 'node .ralph/run.js --spec',
        'ralph:docker': 'node .ralph/docker/build.js',
        'ralph:setup': 'node .ralph/setup.js',
    };

    const existingScripts = Object.keys(ralphScripts).filter(key => packageJson.scripts[key]);
    const missingScripts = Object.keys(ralphScripts).filter(key => !packageJson.scripts[key]);

    if (existingScripts.length === Object.keys(ralphScripts).length) {
        success('All Ralph npm scripts already configured');
        return;
    }

    if (existingScripts.length > 0) {
        success(`Found existing scripts: ${existingScripts.join(', ')}`);
    }

    if (missingScripts.length === 0) {
        return;
    }

    console.log('');
    info('Add npm scripts for easier Ralph usage:');
    console.log('');
    for (const script of missingScripts) {
        console.log(c('dim', `    "${script}": "${ralphScripts[script]}"`));
    }
    console.log('');

    const addScripts = await confirm(rl, 'Add these scripts to package.json?', true);

    if (!addScripts) {
        info('You can add them manually later.');
        return;
    }

    for (const script of missingScripts) {
        packageJson.scripts[script] = ralphScripts[script];
    }

    fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2) + '\n');
    success(`Added ${missingScripts.length} npm script(s) to package.json`);
    info('You can now run: npm run ralph');
}

// Step 5: Setup AGENTS.md
async function setupAgentsMd(rl) {
    const agentsPath = path.join(ralphDir, 'AGENTS.md');

    if (!fs.existsSync(agentsPath)) {
        error('AGENTS.md not found');
        return;
    }

    const content = fs.readFileSync(agentsPath, 'utf-8');

    const isTemplate = content.includes('[Instructions for how Ralph can build and run tests in the project]');

    if (!isTemplate) {
        success('AGENTS.md appears to be configured');
        return;
    }

    warn('AGENTS.md contains template placeholders');
    console.log('');
    info('AGENTS.md tells Ralph how to build and test your project.');
    info('You need to customize it with your project\'s commands.');
    console.log('');

    const generateNow = await confirm(rl, 'Would you like to generate AGENTS.md using Claude?', true);

    if (!generateNow) {
        info('You can edit .ralph/AGENTS.md manually later.');
        return;
    }

    let claudeAvailable = false;
    try {
        execSync('claude --version', { stdio: 'ignore' });
        claudeAvailable = true;
    } catch {
        // Claude CLI not installed
    }

    if (!claudeAvailable) {
        warn('Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-code');
        console.log('');
        info('Once installed, run this command to generate AGENTS.md:');
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
    info('Running Claude to analyze your codebase and generate AGENTS.md...');
    info('This may take several minutes depending on the size of your codebase.');
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

// Step 6: Build Docker image
async function buildDockerImage(rl) {
    const repoNameLocal = path.basename(rootDir).toLowerCase().replace(/[^a-z0-9-]/g, '-');
    const imageNameLocal = `ralph-wiggum-${repoNameLocal}`;

    try {
        const images = execSync('docker images --format "{{.Repository}}"', { encoding: 'utf-8' });
        if (images.split('\n').includes(imageNameLocal)) {
            success(`Docker image '${imageNameLocal}' already exists`);
            const rebuild = await confirm(rl, 'Would you like to rebuild it?', false);
            if (!rebuild) {
                return;
            }
        }
    } catch {
        warn('Could not check Docker images');
        return;
    }

    const build = await confirm(rl, 'Would you like to build the Docker image now?', true);

    if (!build) {
        info('Run "node .ralph/docker/build.js" later to build.');
        return;
    }

    console.log('');
    info('Building Docker image (this may take a few minutes)...');
    console.log('');

    try {
        execSync(`docker build -t ${imageNameLocal} -f .ralph/docker/Dockerfile .`, {
            cwd: rootDir,
            stdio: 'inherit',
        });
        console.log('');
        success(`Docker image '${imageNameLocal}' built successfully`);
    } catch {
        error('Docker build failed. Try running "node .ralph/docker/build.js" manually.');
    }
}

// Print final summary
function printSummary() {
    const packageJsonPath = path.join(rootDir, 'package.json');
    const hasPackageJson = fs.existsSync(packageJsonPath);

    console.log('');
    separator();
    success('Setup Complete!');
    separator();
    console.log('');
    console.log('  Next steps:');
    console.log('');
    console.log(c('cyan', '  1.') + ' Review .ralph/AGENTS.md and refine if needed');
    console.log('');
    console.log(c('cyan', '  2.') + ' Create your feature spec:');
    console.log(c('dim', '     Option A: Use spec mode (recommended) — AI-assisted spec creation'));
    if (hasPackageJson) {
        console.log(c('dim', '       npm run ralph:spec'));
    } else {
        console.log(c('dim', '       node .ralph/run.js <feature-name> spec'));
    }
    console.log(c('dim', '     Option B: Copy .ralph/specs/sample.md to .ralph/specs/<feature-name>.md'));
    console.log(c('dim', '     Option C: Use .ralph/prompts/requirements.md to gather requirements'));
    console.log('');
    console.log(c('dim', '     Tip: Add reference files to .ralph/references/ before running spec mode:'));
    console.log(c('dim', '        existing implementations, sample data, documentation, etc.'));
    console.log('');
    console.log(c('cyan', '  3.') + ' Run Ralph:');
    if (hasPackageJson) {
        console.log(c('dim', '     npm run ralph              ') + '# Interactive mode');
        console.log(c('dim', '     npm run ralph:spec         ') + '# Create spec interactively with AI');
        console.log(c('dim', '     npm run ralph:plan         ') + '# Create implementation plan');
        console.log(c('dim', '     npm run ralph:build        ') + '# Start building');
        console.log(c('dim', '     npm run ralph:review       ') + '# Review implementation');
        console.log(c('dim', '     npm run ralph:full         ') + '# Full cycle: plan->build->review->check');
    } else {
        console.log(c('dim', '     node .ralph/run.js              ') + '# Interactive mode');
        console.log(c('dim', '     node .ralph/run.js <spec> spec  ') + '# Create spec with AI wizard');
        console.log(c('dim', '     node .ralph/run.js <spec> plan  ') + '# Create implementation plan');
        console.log(c('dim', '     node .ralph/run.js <spec> build ') + '# Start building');
        console.log(c('dim', '     node .ralph/run.js <spec> review') + '# Review implementation');
        console.log(c('dim', '     node .ralph/run.js <spec> full  ') + '# Full cycle: plan->build->review->check');
    }
    console.log('');
}

// Main setup flow
async function main() {
    startupBanner({ cwd: rootDir, version: '0.0.0' });
    header('Setup Wizard');

    const totalSteps = 6;

    // Step 1: Prerequisites
    step(1, totalSteps, 'Checking prerequisites');
    const issues = checkPrerequisites();

    if (issues.length > 0) {
        for (const issue of issues) {
            error(issue);
        }
        console.log('');
        warn('Please fix the above issues before continuing.');
        if (issues.some(i => i.includes('Docker'))) {
            hint('dockerMissing');
        }
        console.log('');
        process.exit(1);
    }
    success('All prerequisites met');

    const rl = await createReadlineInterface();

    try {
        // Step 2: .env file
        step(2, totalSteps, 'Configuring environment (.env)');
        await setupEnvFile(rl);

        // Step 3: .gitignore
        step(3, totalSteps, 'Updating .gitignore');
        setupGitignore();

        // Step 4: npm scripts
        step(4, totalSteps, 'Setting up npm scripts');
        await setupNpmScripts(rl);

        // Step 5: AGENTS.md
        step(5, totalSteps, 'Configuring AGENTS.md');
        await setupAgentsMd(rl);

        // Step 6: Docker image
        step(6, totalSteps, 'Docker image');
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
    error(`Setup failed: ${err.message}`);
    console.error('');
    process.exit(1);
});
