const fs = require('fs');
const path = require('path');

// Directory where ralph CLI is installed (the package root)
const pkgDir = path.resolve(__dirname, '../..');

// Directory where lib assets live (prompts, docker, scripts, templates)
const libDir = path.join(pkgDir, 'lib');

// Current working directory (the user's repo)
function repoDir() {
  return process.cwd();
}

// The .ralph directory inside the user's repo
function ralphDir() {
  return path.join(repoDir(), '.ralph');
}

// Check if we're in an initialized ralph repo
function isInitialized() {
  return fs.existsSync(ralphDir());
}

// Get the path to a bundled prompt file, with local override support.
// If .ralph/prompts/<promptPath> exists in the repo, use that instead.
function getPromptPath(promptPath) {
  const localPath = path.join(ralphDir(), 'prompts', promptPath);
  if (fs.existsSync(localPath)) {
    return localPath;
  }
  return path.join(libDir, 'prompts', promptPath);
}

// Get available spec files from the user's .ralph/specs/ directory
function getAvailableSpecs() {
  const specsDir = path.join(ralphDir(), 'specs');
  if (!fs.existsSync(specsDir)) return [];
  return fs.readdirSync(specsDir)
    .filter(f => f.endsWith('.md') && f !== 'active.md' && f !== 'sample.md')
    .map(f => f.replace('.md', ''));
}

function validateSpec(spec) {
  const specPath = path.join(ralphDir(), 'specs', `${spec}.md`);
  return fs.existsSync(specPath);
}

function getSpecDetails(specName) {
  const manifestPath = path.join(ralphDir(), 'specs', specName, 'manifest.json');
  if (!fs.existsSync(manifestPath)) return null;
  try {
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
    return manifest.progress || null;
  } catch {
    return null;
  }
}

// Convert Windows paths to Docker-compatible format
function toDockerPath(windowsPath) {
  if (process.platform !== 'win32') return windowsPath;
  return windowsPath
    .replace(/\\/g, '/')
    .replace(/^([A-Za-z]):/, (_, letter) => `/${letter.toLowerCase()}`);
}

module.exports = {
  pkgDir,
  libDir,
  repoDir,
  ralphDir,
  isInitialized,
  getPromptPath,
  getAvailableSpecs,
  validateSpec,
  getSpecDetails,
  toDockerPath,
};
