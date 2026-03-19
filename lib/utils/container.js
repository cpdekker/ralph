const { execSync } = require('child_process');
const path = require('path');
const { repoDir } = require('./paths');

// Find running Ralph containers for this repo
function findRalphContainers(spec) {
  const root = repoDir();
  const repoName = path.basename(root).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const prefix = spec
    ? `ralph-${repoName}-${spec}`.replace(/[^a-z0-9-]/g, '-')
    : `ralph-${repoName}-`;

  try {
    const output = execSync(
      `docker ps --filter "name=${prefix}" --format "{{.Names}}"`,
      { encoding: 'utf-8', cwd: root }
    ).trim();
    if (!output) return [];
    return output.split('\n').filter(Boolean);
  } catch {
    return [];
  }
}

// Get a single running container, or exit with error if ambiguous
function resolveContainer(spec) {
  const containers = findRalphContainers(spec);
  if (containers.length === 0) {
    return null;
  }
  if (containers.length === 1) {
    return containers[0];
  }
  // Multiple containers — need spec to disambiguate
  return containers;
}

// Read a file from inside a running container
function containerReadFile(containerName, filePath) {
  try {
    return execSync(`docker exec ${containerName} cat ${filePath}`, {
      encoding: 'utf-8',
      timeout: 5000,
    });
  } catch {
    return null;
  }
}

// Write a file inside a running container
function containerWriteFile(containerName, filePath, content) {
  try {
    execSync(`docker exec -i ${containerName} tee ${filePath} > /dev/null`, {
      input: content,
      encoding: 'utf-8',
      timeout: 5000,
    });
    return true;
  } catch {
    return false;
  }
}

// Execute a command inside a running container
function containerExec(containerName, command) {
  try {
    return execSync(`docker exec ${containerName} ${command}`, {
      encoding: 'utf-8',
      timeout: 10000,
    });
  } catch {
    return null;
  }
}

module.exports = {
  findRalphContainers,
  resolveContainer,
  containerReadFile,
  containerWriteFile,
  containerExec,
};
