import { createRequire } from 'node:module';
import path from 'node:path';
import { setWorkdir } from './paths-adapter.js';

const require = createRequire(import.meta.url);
const libPath = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
const coreContainer = require(path.join(libPath, 'utils', 'container.js'));

export function findRalphContainers(workdir, spec) {
  setWorkdir(workdir);
  return coreContainer.findRalphContainers(spec);
}

export function resolveContainer(workdir, spec) {
  setWorkdir(workdir);
  return coreContainer.resolveContainer(spec);
}

export function containerReadFile(containerName, filePath) {
  return coreContainer.containerReadFile(containerName, filePath);
}

export function containerWriteFile(containerName, filePath, content) {
  return coreContainer.containerWriteFile(containerName, filePath, content);
}

export function containerExec(containerName, command) {
  return coreContainer.containerExec(containerName, command);
}
