const { execSync } = require('child_process');

function getRemoteUrl(cwd) {
  try {
    const url = execSync('git remote get-url origin', { encoding: 'utf-8', cwd }).trim();
    if (url.startsWith('git@github.com:')) {
      return url.replace('git@github.com:', 'https://github.com/');
    }
    return url;
  } catch {
    return null;
  }
}

function getBranch(cwd) {
  try {
    return execSync('git branch --show-current', { encoding: 'utf-8', cwd }).trim();
  } catch {
    return 'main';
  }
}

function isGitRepo(cwd) {
  try {
    execSync('git rev-parse --git-dir', { cwd, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

module.exports = { getRemoteUrl, getBranch, isGitRepo };
