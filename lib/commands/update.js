const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { c, success, error, info, warn, createSpinner } = require('../utils/colors');

function getInstallType() {
  // Check if we're running from a git repo (dev/clone install)
  const pkgRoot = path.resolve(__dirname, '../..');
  const gitDir = path.join(pkgRoot, '.git');
  if (fs.existsSync(gitDir)) {
    return { type: 'git', dir: pkgRoot };
  }
  return { type: 'npm' };
}

function getLatestNpmVersion() {
  try {
    return execSync('npm view ralphai version', {
      encoding: 'utf-8',
      timeout: 15000,
    }).trim();
  } catch {
    return null;
  }
}

function getLatestGitVersion(dir) {
  try {
    execSync('git fetch origin --tags', { cwd: dir, stdio: 'ignore', timeout: 15000 });
    const tag = execSync('git describe --tags --abbrev=0 origin/main', {
      encoding: 'utf-8',
      cwd: dir,
      timeout: 5000,
    }).trim();
    return tag.replace(/^v/, '');
  } catch {
    return null;
  }
}

async function run() {
  const pkg = require('../../package.json');
  const currentVersion = pkg.version;
  const install = getInstallType();

  console.log('');
  console.log(c('cyan', '  Ralph Update'));
  console.log(c('dim', '  ─────────────────────────────────'));
  console.log('');
  info(`Current version: ${currentVersion}`);
  info(`Install type:    ${install.type === 'git' ? 'git clone' : 'npm'}`);
  console.log('');

  if (install.type === 'git') {
    await updateFromGit(install.dir, currentVersion);
  } else {
    await updateFromNpm(currentVersion);
  }
}

async function updateFromNpm(currentVersion) {
  const spinner = createSpinner('Checking npm registry...');
  const latest = getLatestNpmVersion();
  spinner.stop(!!latest);

  if (!latest) {
    error('Could not reach npm registry.');
    info('Check your network connection and try again.');
    console.log('');
    return;
  }

  info(`Latest version:  ${latest}`);
  console.log('');

  if (latest === currentVersion) {
    success('Already on the latest version.');
    console.log('');
    return;
  }

  console.log(c('cyan', `  Updating ${currentVersion} → ${latest}...`));
  console.log('');

  try {
    execSync('npm install -g ralphai@latest', { stdio: 'inherit' });
    console.log('');
    success(`Updated to ${latest}.`);
    console.log('');
  } catch {
    console.log('');
    error('Update failed.');
    info('Try manually: npm install -g ralphai@latest');
    console.log('');
  }
}

async function updateFromGit(dir, currentVersion) {
  const spinner = createSpinner('Fetching latest from git...');
  const latest = getLatestGitVersion(dir);
  spinner.stop(true);

  if (latest) {
    info(`Latest release:  ${latest}`);
  }
  console.log('');

  if (latest && latest === currentVersion) {
    success('Already on the latest version.');
    console.log('');
    return;
  }

  try {
    // Check for local changes
    const status = execSync('git status --porcelain', {
      encoding: 'utf-8',
      cwd: dir,
    }).trim();

    if (status) {
      warn('You have local changes in the ralph repo.');
      info('Stash or commit them before updating.');
      console.log('');
      console.log(c('dim', `  cd ${dir}`));
      console.log(c('dim', '  git stash'));
      console.log(c('dim', '  ralph update'));
      console.log('');
      return;
    }

    console.log(c('cyan', '  Pulling latest changes...'));
    console.log('');
    execSync('git pull origin main', { stdio: 'inherit', cwd: dir });

    console.log('');
    console.log(c('cyan', '  Installing dependencies...'));
    execSync('npm install', { stdio: 'inherit', cwd: dir });

    console.log('');
    console.log(c('cyan', '  Re-linking global binary...'));
    execSync('npm install -g .', { stdio: 'inherit', cwd: dir });

    console.log('');
    const newPkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf-8'));
    success(`Updated to ${newPkg.version}.`);
    console.log('');
  } catch (err) {
    console.log('');
    error(`Update failed: ${err.message}`);
    console.log('');
    info('Try manually:');
    console.log(c('dim', `  cd ${dir}`));
    console.log(c('dim', '  git pull origin main'));
    console.log(c('dim', '  npm install'));
    console.log(c('dim', '  npm install -g .'));
    console.log('');
  }
}

module.exports = { run };
