import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);

const libPath = process.env.RALPH_LIB_PATH || path.resolve(import.meta.dirname, '../../../lib');
const corePaths = require(path.join(libPath, 'utils', 'paths.js'));

export function setWorkdir(workdir) {
  process.env.RALPH_WORKDIR = workdir;
}

export const {
  repoDir, ralphDir, isInitialized, getPromptPath,
  getAvailableSpecs, validateSpec, getSpecDetails, toDockerPath,
  libDir, pkgDir
} = corePaths;
