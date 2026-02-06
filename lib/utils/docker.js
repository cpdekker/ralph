const { execSync } = require('child_process');
const path = require('path');
const { libDir, repoDir } = require('./paths');

function getImageName() {
  const repoName = path.basename(repoDir()).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  return `ralph-wiggum-${repoName}`;
}

function imageExists(imageName) {
  try {
    const images = execSync('docker images --format "{{.Repository}}"', {
      encoding: 'utf-8',
    });
    return images.split('\n').includes(imageName || getImageName());
  } catch {
    return false;
  }
}

function buildImage(imageName) {
  const target = imageName || getImageName();
  const dockerDir = path.join(libDir, 'docker');
  console.log(`\x1b[36mBuilding ${target} image...\x1b[0m`);
  // Build with lib/docker/ as context so COPY entrypoint.sh works
  execSync(`docker build -t ${target} "${dockerDir}"`, {
    stdio: 'inherit',
    cwd: repoDir(),
  });
}

function ensureImage(imageName) {
  const target = imageName || getImageName();
  if (!imageExists(target)) {
    buildImage(target);
  }
}

function isDockerAvailable() {
  try {
    execSync('docker --version', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function isDockerRunning() {
  try {
    execSync('docker info', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

module.exports = { getImageName, imageExists, buildImage, ensureImage, isDockerAvailable, isDockerRunning };
