const { execSync, spawn } = require('child_process');
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
  for (const spec of specs) {
    const name = spec.name || spec.id;
    graph[name] = {
      ...spec,
      name,
      deps: spec.dependencies || spec.deps || [],
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

function launchSubSpecContainer(specName, subSpecName, opts) {
  const root = repoDir();
  const imageName = getImageName();
  const repoName = path.basename(root).toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const specSuffix = specName.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const subSuffix = subSpecName.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  const backgroundImageName = `${imageName}-${specSuffix}`;

  ensureImage(backgroundImageName);

  const repoUrl = getRemoteUrl(root);
  if (!repoUrl) {
    throw new Error('Could not get git remote URL');
  }

  const baseBranch = opts.baseBranch || getBranch(root);
  const subSpecBranch = `ralph/${specName}/${subSpecName}`;
  const containerName = `ralph-${repoName}-${specSuffix}-${subSuffix}`.replace(/[^a-z0-9-]/g, '-');

  // Remove any existing stopped container
  try { execSync(`docker rm ${containerName}`, { stdio: 'ignore' }); } catch {}

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

  return { containerName, branch: subSpecBranch };
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

  while (completedSpecs < totalSpecs) {
    const eligible = getEligibleSpecs(graph);

    if (eligible.length === 0) {
      // Check if there are in-progress specs (shouldn't happen from a fresh start)
      const inProgress = Object.values(graph).filter(s => s.status === 'in_progress');
      if (inProgress.length > 0) {
        console.log(c('yellow', `Waiting for ${inProgress.length} in-progress sub-specs...`));
      } else {
        console.error(c('red', 'No eligible sub-specs and none in progress. Possible dependency cycle.'));
        break;
      }
    }

    // Launch up to `parallel` containers
    const batch = eligible.slice(0, parallel);
    const running = [];

    console.log(`\n${c('cyan', `Launching batch of ${batch.length} sub-specs:`)}`);

    for (const subSpecName of batch) {
      console.log(`  ${c('green', `-> ${subSpecName}`)}`);
      graph[subSpecName].status = 'in_progress';

      try {
        const { containerName, branch } = launchSubSpecContainer(spec, subSpecName, {
          baseBranch,
          verbose,
          iterations,
        });
        running.push({ name: subSpecName, containerName, branch });
        console.log(`    Container: ${containerName}`);
        console.log(`    Branch: ${branch}`);
      } catch (err) {
        console.error(c('red', `    Failed to launch: ${err.message}`));
        graph[subSpecName].status = 'failed';
      }
    }

    if (running.length === 0) {
      console.error(c('red', 'All launches failed'));
      break;
    }

    // Wait for all containers in this batch
    console.log(`\n${c('cyan', `Waiting for ${running.length} containers to complete...`)}`);

    // Attach log streaming for visibility
    for (const { containerName, name } of running) {
      const logsProcess = spawn('docker', ['logs', '-f', containerName], { stdio: 'ignore' });
      logsProcess.unref();
    }

    // Poll all containers
    const results = await Promise.all(
      running.map(async ({ name, containerName, branch }) => {
        const exitCode = await waitForContainer(containerName);
        return { name, containerName, branch, exitCode };
      })
    );

    // Process results
    for (const { name, containerName, branch, exitCode } of results) {
      if (exitCode === 0) {
        // Check for completion marker
        console.log(`  ${c('green', `${name} completed (exit 0)`)}`);

        // Merge sub-spec branch into main spec branch
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

      // Clean up container
      try { execSync(`docker rm ${containerName}`, { stdio: 'ignore' }); } catch {}
    }

    // Update manifest with progress
    const specs = manifest.sub_specs || manifest.subSpecs || [];
    for (const spec_entry of specs) {
      const name = spec_entry.name || spec_entry.id;
      if (graph[name]) {
        spec_entry.status = graph[name].status;
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
