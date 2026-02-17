#!/usr/bin/env node
const { execSync } = require('child_process');
const path = require('path');
const { c, success, error } = require('../lib/ui');

const rootDir = path.resolve(__dirname, '../..');

// Derive image name from repo directory to avoid conflicts across multiple repos
const repoName = path.basename(rootDir).toLowerCase().replace(/[^a-z0-9-]/g, '-');
const imageName = `ralph-wiggum-${repoName}`;

console.log(`${c('cyan', `  Building ${imageName} image...`)}`);

try {
  execSync(`docker build -t ${imageName} -f .ralph/docker/Dockerfile .`, {
    stdio: 'inherit',
    cwd: rootDir,
  });
  success('Build complete.');
} catch {
  error('Build failed.');
  process.exit(1);
}
