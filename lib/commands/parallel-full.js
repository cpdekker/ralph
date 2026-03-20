const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { c, error, warn, startupBanner, header, separator, box } = require('../utils/colors');
const {
  isInitialized, ralphDir, repoDir, validateSpec,
  toDockerPath, libDir,
} = require('../utils/paths');
const { getRemoteUrl, getBranch } = require('../utils/git');
const { getImageName, ensureImage } = require('../utils/docker');
const { checkEnvFile } = require('./mode');

function loadManifest(specName) {
  const manifestPath = path.join(ralphDir(), 'specs', specName, 'manifest.json');
  if (!fs.existsSync(manifestPath)) return null;
  return JSON.parse(fs.readFileSync(manifestPath, 'utf-8'));
}

function saveManifest(specName, manifest) {
  const manifestPath = path.join(ralphDir(), 'specs', specName, 'manifest.json');
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
}

function buildDependencyGraph(manifest) {
  const specs = manifest.sub_specs || manifest.subSpecs || [];
  const graph = {};
  // Build id-to-name lookup so dependencies can reference either id or name
  const idToName = {};
  for (const spec of specs) {
    const name = spec.name || spec.id;
    if (spec.id) idToName[spec.id] = name;
    idToName[name] = name; // also allow name-based deps
  }
  for (const spec of specs) {
    const name = spec.name || spec.id;
    const rawDeps = spec.dependencies || spec.deps || [];
    // Resolve deps to graph keys (names), supporting both id and name references
    const resolvedDeps = rawDeps.map(dep => idToName[dep] || dep);
    graph[name] = {
      ...spec,
      name,
      deps: resolvedDeps,
      status: spec.status || 'pending',
    };
  }
  return graph;
}

function getEligibleSpecs(graph) {
  const eligible = [];
  for (const [name, spec] of Object.entries(graph)) {
    if (spec.status !== 'pending') continue;
    const allDepsSatisfied = spec.deps.every(dep => {
      const depSpec = graph[dep];
      return depSpec && depSpec.status === 'complete';
    });
    if (allDepsSatisfied) eligible.push(name);
  }
  return eligible;
}

function waitForContainer(containerName, pollInterval = 10000) {
  return new Promise((resolve) => {
    const check = () => {
      try {
        const state = execSync(
          `docker inspect --format "{{.State.Status}}" ${containerName}`,
          { encoding: 'utf-8' }
        ).trim();
        if (state === 'exited' || state === 'dead') {
          const exitCode = execSync(
            `docker inspect --format "{{.State.ExitCode}}" ${containerName}`,
            { encoding: 'utf-8' }
          ).trim();
          resolve(parseInt(exitCode, 10));
          return;
        }
      } catch {
        // Container removed or not found
        resolve(1);
        return;
      }
      setTimeout(check, pollInterval);
    };
    check();
  });
}

function getContainerName(specName, subSpecName) {
  const root = repoDir();
  const repoName = path.basename(root).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const specSuffix = specName.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const subSuffix = subSpecName.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  return `ralph-${repoName}-${specSuffix}-${subSuffix}`.replace(/[^a-z0-9-]/g, '-');
}

function getContainerState(containerName) {
  try {
    const state = execSync(
      `docker inspect --format "{{.State.Status}}" ${containerName}`,
      { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'ignore'] }
    ).trim();
    return state; // 'running', 'exited', 'dead', 'created', 'paused', etc.
  } catch {
    return null; // container doesn't exist
  }
}

function launchSubSpecContainer(specName, subSpecName, opts) {
  const root = repoDir();
  const imageName = getImageName();
  const specSuffix = specName.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const backgroundImageName = `${imageName}-${specSuffix}`;
  const subSpecBranch = `ralph/${specName}/${subSpecName}`;
  const containerName = getContainerName(specName, subSpecName);

  // Check if container already exists
  const existingState = getContainerState(containerName);
  if (existingState === 'running') {
    return { containerName, branch: subSpecBranch, reused: true };
  }

  // Remove any existing stopped/dead container
  if (existingState) {
    try { execSync(`docker rm -f ${containerName}`, { stdio: 'ignore' }); } catch {}
  }

  ensureImage(backgroundImageName);

  const repoUrl = getRemoteUrl(root);
  if (!repoUrl) {
    throw new Error('Could not get git remote URL');
  }

  const baseBranch = opts.baseBranch || getBranch(root);
  const libDockerPath = toDockerPath(libDir);

  const dockerArgs = [
    'run', '-d',
    '--name', containerName,
    '--env-file', path.join(ralphDir(), '.env'),
    '-v', `${libDockerPath}:/ralph-lib:ro`,
    '-e', `RALPH_REPO_URL=${repoUrl}`,
    '-e', `RALPH_BRANCH=${subSpecBranch}`,
    '-e', `RALPH_BASE_BRANCH=${baseBranch}`,
    '-e', `RALPH_SUBSPEC_NAME=${subSpecName}`,
    '-e', `RALPH_SUBSPEC_BRANCH=${subSpecBranch}`,
    backgroundImageName,
    'bash', '/ralph-lib/scripts/loop.sh',
    specName,
    'full',
    String(opts.iterations || 100),
  ];

  if (opts.verbose) dockerArgs.push('--verbose');

  execSync(`docker ${dockerArgs.join(' ')}`, { encoding: 'utf-8', cwd: root });

  return { containerName, branch: subSpecBranch, reused: false };
}

function mergeSubSpecBranch(specName, subSpecBranch) {
  const root = repoDir();
  const mainBranch = `ralph/${specName}`;
  try {
    execSync(`git fetch origin`, { cwd: root, stdio: 'ignore' });
    execSync(`git checkout ${mainBranch}`, { cwd: root, stdio: 'ignore' });
    execSync(`git pull origin ${mainBranch}`, { cwd: root, stdio: 'ignore' });
    execSync(`git merge --no-ff origin/${subSpecBranch} -m "Merge sub-spec ${subSpecBranch}"`, {
      cwd: root, encoding: 'utf-8',
    });
    execSync(`git push origin ${mainBranch}`, { cwd: root, stdio: 'ignore' });
    return true;
  } catch (err) {
    console.error(c('red', `Merge conflict merging ${subSpecBranch} into ${mainBranch}`));
    console.error(c('yellow', 'Creating paused.md for manual resolution'));
    try {
      execSync('git merge --abort', { cwd: root, stdio: 'ignore' });
    } catch {}
    const pausedPath = path.join(ralphDir(), 'paused.md');
    fs.writeFileSync(pausedPath, `# Merge Conflict\n\nFailed to merge \`${subSpecBranch}\` into \`${mainBranch}\`.\n\nResolve manually:\n\`\`\`bash\ngit checkout ${mainBranch}\ngit merge origin/${subSpecBranch}\n# resolve conflicts\ngit add . && git commit\ngit push\n\`\`\`\n`);
    return false;
  }
}

async function run(spec, opts = {}) {
  if (!isInitialized()) {
    console.error(c('red', '\n  Error: .ralph directory not found. Run "ralph init" first.\n'));
    process.exit(1);
  }

  if (!spec) {
    console.error(c('red', '\n  Error: Spec name required. Usage: ralph parallel-full <spec> [-j N]\n'));
    process.exit(1);
  }

  if (!validateSpec(spec)) {
    console.error(c('red', `\n  Error: Spec file not found: .ralph/specs/${spec}.md\n`));
    process.exit(1);
  }

  const manifest = loadManifest(spec);
  if (!manifest) {
    console.error(c('red', `\n  Error: No manifest found at .ralph/specs/${spec}/manifest.json`));
    console.error(c('yellow', '  Run "ralph decompose" first to split the spec into sub-specs.\n'));
    process.exit(1);
  }

  const parallel = parseInt(opts.parallel) || 3;
  const verbose = !!opts.verbose;
  const iterations = parseInt(opts.iterations) || 100;

  checkEnvFile();
  ensureImage();

  const graph = buildDependencyGraph(manifest);
  const totalSpecs = Object.keys(graph).length;
  let completedSpecs = Object.values(graph).filter(s => s.status === 'complete').length;

  startupBanner({
    cwd: repoDir(),
    spec,
    mode: 'parallel-full',
  });
  header('Parallel Full Mode');
  console.log(`  Sub-specs: ${totalSpecs} (${completedSpecs} complete)`);
  console.log(`  Max parallel: ${parallel}`);
  console.log('');

  const baseBranch = getBranch(repoDir());

  // --- Rolling pool: launch new sub-specs as soon as any slot opens ---

  // Track currently running containers: Map<subSpecName, { containerName, branch, promise }>
  const pool = new Map();

  // Re-attach to any containers already running from a previous invocation
  for (const [name, spec_entry] of Object.entries(graph)) {
    if (spec_entry.status === 'in_progress') {
      const containerName = getContainerName(spec, name);
      const state = getContainerState(containerName);
      if (state === 'running') {
        const branch = `ralph/${spec}/${name}`;
        console.log(`  ${c('yellow', `Reattaching to running container: ${name}`)} (${containerName})`);
        const promise = waitForContainer(containerName).then(exitCode => ({ name, containerName, branch, exitCode }));
        pool.set(name, { containerName, branch, promise });
      } else {
        // Was in_progress but container is gone — reset to pending for retry
        graph[name].status = 'pending';
      }
    }
  }

  function launchEligible() {
    const eligible = getEligibleSpecs(graph);
    const slotsAvailable = parallel - pool.size;
    const toLaunch = eligible.slice(0, slotsAvailable);

    for (const subSpecName of toLaunch) {
      console.log(`  ${c('green', `-> Launching ${subSpecName}`)}`);
      graph[subSpecName].status = 'in_progress';

      try {
        const { containerName, branch, reused } = launchSubSpecContainer(spec, subSpecName, {
          baseBranch,
          verbose,
          iterations,
        });
        if (reused) {
          console.log(`    ${c('yellow', 'Reusing existing container:')} ${containerName}`);
        } else {
          console.log(`    Container: ${containerName}`);
        }
        console.log(`    Branch: ${branch}`);

        const promise = waitForContainer(containerName).then(exitCode => ({ name: subSpecName, containerName, branch, exitCode }));
        pool.set(subSpecName, { containerName, branch, promise });
      } catch (err) {
        console.error(c('red', `    Failed to launch: ${err.message}`));
        graph[subSpecName].status = 'failed';
      }
    }
  }

  function processResult({ name, containerName, branch, exitCode }) {
    pool.delete(name);

    if (exitCode === 0) {
      console.log(`  ${c('green', `${name} completed (exit 0)`)}`);
      const merged = mergeSubSpecBranch(spec, branch);
      if (merged) {
        graph[name].status = 'complete';
        completedSpecs++;
        console.log(`  ${c('green', `${name} merged successfully`)}`);
      } else {
        graph[name].status = 'merge_conflict';
        console.log(`  ${c('red', `${name} has merge conflicts - needs manual resolution`)}`);
      }
    } else {
      console.log(`  ${c('red', `${name} failed (exit ${exitCode})`)}`);
      graph[name].status = 'failed';
    }

    // Clean up container (keep failed containers for debugging)
    if (graph[name].status === 'complete') {
      try { execSync(`docker rm ${containerName}`, { stdio: 'ignore' }); } catch {}
    } else {
      console.log(`  ${c('yellow', `Container ${containerName} preserved for debugging. Run: docker logs ${containerName}`)}`);
    }

    // Update manifest with progress
    const specs = manifest.sub_specs || manifest.subSpecs || [];
    for (const spec_entry of specs) {
      const sName = spec_entry.name || spec_entry.id;
      if (graph[sName]) {
        spec_entry.status = graph[sName].status;
      }
    }
    saveManifest(spec, manifest);

    // Commit updated manifest
    try {
      const root = repoDir();
      execSync(`git add .ralph/specs/${spec}/manifest.json`, { cwd: root });
      execSync(`git commit -m "Update manifest: ${completedSpecs}/${totalSpecs} sub-specs complete"`, { cwd: root });
      execSync(`git push origin ralph/${spec}`, { cwd: root, stdio: 'ignore' });
    } catch {}

    console.log(`\n${c('cyan', `Progress: ${completedSpecs}/${totalSpecs} sub-specs complete`)}\n`);
  }

  // Main loop: fill slots, wait for any one to finish, repeat
  while (completedSpecs < totalSpecs) {
    launchEligible();

    if (pool.size === 0) {
      const inProgress = Object.values(graph).filter(s => s.status === 'in_progress');
      if (inProgress.length === 0) {
        // No running containers and nothing eligible — check for stuck state
        const pending = Object.values(graph).filter(s => s.status === 'pending');
        if (pending.length > 0) {
          console.error(c('red', 'No eligible sub-specs and none running. Possible dependency cycle or all dependencies failed.'));
        }
        break;
      }
    }

    // Wait for ANY one container to finish (race)
    const result = await Promise.race(
      Array.from(pool.values()).map(entry => entry.promise)
    );

    processResult(result);
  }

  // Final summary
  console.log('');
  if (completedSpecs === totalSpecs) {
    box([
      c('green', 'All sub-specs completed successfully!'),
      '',
      `Run "ralph full ${spec}" for master completion check`,
    ]);
  } else {
    const summaryLines = [`${completedSpecs}/${totalSpecs} sub-specs completed`];
    const failed = Object.entries(graph).filter(([_, s]) => s.status === 'failed' || s.status === 'merge_conflict');
    if (failed.length > 0) {
      summaryLines.push('');
      summaryLines.push(c('red', 'Failed sub-specs:'));
      for (const [name, s] of failed) {
        summaryLines.push(c('red', `  - ${name} (${s.status})`));
      }
    }
    box(summaryLines);
  }
  console.log('');
}

module.exports = { run };
