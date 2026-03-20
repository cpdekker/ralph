import fs from 'node:fs';
import path from 'node:path';
import { ralphDir } from './paths-adapter.js';

const STATE_FILE = 'plugin-state.json';

function statePath() {
  return path.join(ralphDir(), STATE_FILE);
}

function readState() {
  try {
    return JSON.parse(fs.readFileSync(statePath(), 'utf-8'));
  } catch {
    return { containers: {} };
  }
}

function writeState(state) {
  const dir = ralphDir();
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(statePath(), JSON.stringify(state, null, 2));
}

export function registerContainer({ containerId, containerName, mode, spec, branch }) {
  const state = readState();
  state.containers[containerId] = {
    containerName, mode, spec, branch,
    startTime: new Date().toISOString(),
    lastStatus: 'running',
    lastLogOffset: null
  };
  writeState(state);
}

export function deregisterContainer(containerId) {
  const state = readState();
  delete state.containers[containerId];
  writeState(state);
}

export function updateContainer(containerId, updates) {
  const state = readState();
  if (state.containers[containerId]) {
    Object.assign(state.containers[containerId], updates);
    writeState(state);
  }
}

export function getContainer(containerId) {
  const state = readState();
  return state.containers[containerId] || null;
}

export function getAllContainers() {
  const state = readState();
  return state.containers;
}
