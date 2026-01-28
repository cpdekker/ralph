#!/usr/bin/env node
const { execSync } = require('child_process');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');

// Derive image name from repo directory to avoid conflicts across multiple repos
const repoName = path.basename(rootDir).toLowerCase().replace(/[^a-z0-9-]/g, '-');
const imageName = `ralph-wiggum-${repoName}`;

console.log(`\x1b[36mBuilding ${imageName} image...\x1b[0m`);

try {
  execSync(`docker build -t ${imageName} -f .ralph/Dockerfile .`, {
    stdio: 'inherit',
    cwd: rootDir,
  });
  console.log('\x1b[32mBuild complete.\x1b[0m');
} catch {
  console.error('\x1b[31mBuild failed.\x1b[0m');
  process.exit(1);
}
