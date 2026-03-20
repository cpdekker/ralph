import fs from 'node:fs';
import path from 'node:path';
import { repoDir, ralphDir, setWorkdir, isInitialized } from '../lib/paths-adapter.js';
import { isDockerAvailable, isDockerRunning, getImageName, imageExists, buildImage } from '../lib/docker-adapter.js';
import { isGitRepo } from '../lib/git-adapter.js';
import { errors } from '../lib/errors.js';

export const definition = {
  name: 'ralph_setup',
  description: 'Pre-flight checks and initialization for Ralph. Checks Docker, image, .env, and git repo. Can auto-build the Docker image.',
  inputSchema: {
    type: 'object',
    properties: {
      workdir: {
        type: 'string',
        description: 'Repository root path. Defaults to current working directory.'
      },
      autoBuild: {
        type: 'boolean',
        description: 'Automatically build the Docker image if missing. Default: true.'
      }
    }
  }
};

export async function handler({ workdir, autoBuild = true }) {
  const dir = workdir || process.cwd();
  setWorkdir(dir);

  const missing = [];

  if (!isGitRepo(dir)) return errors.noGitRepo();

  if (!isDockerAvailable()) {
    missing.push('docker_not_installed');
  } else if (!isDockerRunning()) {
    missing.push('docker_not_running');
  }

  if (!isInitialized()) {
    missing.push('ralph_not_initialized');
  }

  const envPath = path.join(ralphDir(), '.env');
  if (!fs.existsSync(envPath)) {
    missing.push('env_file_missing');
  }

  const imageName = getImageName(dir);
  if (missing.length === 0 || !missing.some(m => m.startsWith('docker'))) {
    if (!imageExists(dir, imageName)) {
      if (autoBuild && missing.length === 0) {
        await buildImage(dir, imageName);
      } else {
        missing.push('image_not_built');
      }
    }
  }

  const ready = missing.length === 0;
  return {
    content: [{
      type: 'text',
      text: JSON.stringify({ ready, missing, imageName, workdir: dir })
    }]
  };
}
