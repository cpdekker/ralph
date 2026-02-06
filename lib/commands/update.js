const { execSync } = require('child_process');
const { c, success, error, info } = require('../utils/colors');

async function run() {
  console.log('');
  console.log(c('cyan', '  Checking for updates...'));
  console.log('');

  try {
    // Check current version
    const pkg = require('../../package.json');
    info(`Current version: ${pkg.version}`);
    console.log('');

    // Try npm update
    console.log(c('dim', '  Running: npm update -g ralph-cli'));
    console.log('');

    execSync('npm update -g ralph-cli', { stdio: 'inherit' });

    console.log('');
    success('Ralph has been updated to the latest version.');
    console.log('');
    info('If you installed Ralph from a git clone, pull the latest changes instead:');
    info('  cd <ralph-repo> && git pull && npm install -g .');
    console.log('');
  } catch (err) {
    console.log('');
    error('Failed to update via npm.');
    console.log('');
    info('If you installed Ralph from a git clone, update manually:');
    info('  cd <ralph-repo> && git pull && npm install -g .');
    console.log('');
    info('Or reinstall from npm:');
    info('  npm install -g ralph-cli');
    console.log('');
  }
}

module.exports = { run };
