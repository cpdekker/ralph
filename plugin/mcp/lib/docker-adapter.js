import { createRequire } from 'node:module';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { setWorkdir, repoDir } from './paths-adapter.js';

const execFileAsync = promisify(execFile);
const require = createRequire(import.meta.url);
const libPath = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
const coreDocker = require(path.join(libPath, 'utils', 'docker.js'));

export function getImageName(workdir) {
  setWorkdir(workdir);
  return coreDocker.getImageName();
}

export function imageExists(workdir, imageName) {
  setWorkdir(workdir);
  return coreDocker.imageExists(imageName);
}

export async function buildImage(workdir, imageName) {
  setWorkdir(workdir);
  const target = imageName || getImageName(workdir);
  const dockerDir = path.join(libPath, 'docker');
  await execFileAsync('docker', ['build', '-t', target, dockerDir], {
    cwd: repoDir()
  });
}

export function isDockerAvailable() {
  return coreDocker.isDockerAvailable();
}

export function isDockerRunning() {
  return coreDocker.isDockerRunning();
}
