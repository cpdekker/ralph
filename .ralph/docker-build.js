#!/usr/bin/env node
const { execSync } = require('child_process');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');

console.log('\x1b[36mBuilding ralph-wiggum image...\x1b[0m');

try {
  execSync('docker build -t ralph-wiggum -f .ralph/Dockerfile .', {
    stdio: 'inherit',
    cwd: rootDir,
  });
  console.log('\x1b[32mBuild complete.\x1b[0m');
} catch {
  console.error('\x1b[31mBuild failed.\x1b[0m');
  process.exit(1);
}
