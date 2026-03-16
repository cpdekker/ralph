const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { c, error, info, success, startupBanner, header } = require('../utils/colors');
const { isInitialized, ralphDir, repoDir, getAvailableSpecs, libDir } = require('../utils/paths');
const { ensureWorktreesDir, listWorktrees } = require('../utils/worktree');
const { getLoopStatus } = require('../agent/loop-runner');

const RALPH_MARKER_START = '<!-- RALPH-AGENT-INSTRUCTIONS-START -->';
const RALPH_MARKER_END = '<!-- RALPH-AGENT-INSTRUCTIONS-END -->';

/**
 * Check if the claude CLI is available.
 */
function checkClaudeCli() {
  try {
    execSync('claude --version', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

/**
 * Build the system prompt for the agent session.
 */
function buildSystemPrompt() {
  const parts = [];

  // Read the agent system prompt template
  const systemPromptPath = path.join(libDir, 'prompts', 'agent-system.md');
  if (fs.existsSync(systemPromptPath)) {
    parts.push(fs.readFileSync(systemPromptPath, 'utf-8'));
  }

  // Include AGENTS.md content
  const agentsPath = path.join(ralphDir(), 'AGENTS.md');
  if (fs.existsSync(agentsPath)) {
    const agents = fs.readFileSync(agentsPath, 'utf-8');
    parts.push('## Project-Specific Instructions (AGENTS.md)\n\n' + agents);
  }

  // List available specs
  const specs = getAvailableSpecs();
  if (specs.length > 0) {
    parts.push('## Available Specs\n\n' + specs.map(s => `- ${s}`).join('\n'));
  } else {
    parts.push('## Available Specs\n\nNo specs found. The user can create one with `ralph spec <name>` or by adding a .md file to .ralph/specs/.');
  }

  // Report running loops
  try {
    const statuses = getLoopStatus(null);
    if (statuses.length > 0) {
      const loopSummary = statuses.map(s => {
        const running = s.running ? 'RUNNING' : 'stopped';
        return `- **${s.spec}**: ${running}${s.mode ? ` (${s.mode})` : ''}${s.pid ? ` PID ${s.pid}` : ''}`;
      }).join('\n');
      parts.push('## Currently Active Loops\n\n' + loopSummary);
    }
  } catch {}

  return parts.join('\n\n---\n\n');
}

/**
 * Inject the Ralph system prompt into CLAUDE.local.md.
 * Returns a cleanup function to restore the file on exit.
 */
function injectSystemPrompt(prompt) {
  const claudeDir = path.join(repoDir(), '.claude');
  fs.mkdirSync(claudeDir, { recursive: true });

  const localMdPath = path.join(claudeDir, 'CLAUDE.local.md');

  // Read existing content (if any)
  let existingContent = '';
  if (fs.existsSync(localMdPath)) {
    existingContent = fs.readFileSync(localMdPath, 'utf-8');
  }

  // Strip any previous Ralph instructions block
  const markerRegex = new RegExp(
    `\\n?${escapeRegex(RALPH_MARKER_START)}[\\s\\S]*?${escapeRegex(RALPH_MARKER_END)}\\n?`,
    'g'
  );
  const cleaned = existingContent.replace(markerRegex, '').trim();

  // Build new content with Ralph block appended
  const ralphBlock = `${RALPH_MARKER_START}\n${prompt}\n${RALPH_MARKER_END}`;
  const newContent = cleaned
    ? `${cleaned}\n\n${ralphBlock}\n`
    : `${ralphBlock}\n`;

  fs.writeFileSync(localMdPath, newContent);

  // Return cleanup function
  return () => {
    try {
      if (cleaned) {
        fs.writeFileSync(localMdPath, cleaned + '\n');
      } else {
        fs.unlinkSync(localMdPath);
      }
    } catch {}
  };
}

function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Write a temporary MCP config file.
 */
function writeMcpConfig() {
  const serverPath = path.join(libDir, 'mcp', 'server.js');
  const config = {
    mcpServers: {
      ralph: {
        command: 'node',
        args: [serverPath, '--repo-dir', repoDir()],
      },
    },
  };

  const configPath = path.join(os.tmpdir(), `ralph-mcp-${process.pid}.json`);
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  return configPath;
}

/**
 * Main agent entry point.
 */
async function run() {
  // Check prerequisites
  if (!isInitialized()) {
    error('.ralph directory not found. Run "ralph init" first.');
    process.exit(1);
  }

  if (!checkClaudeCli()) {
    error('Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-code');
    process.exit(1);
  }

  // Display banner
  startupBanner({ cwd: repoDir() });
  header('Agent Mode');

  // Ensure worktrees directory exists (sibling to project dir)
  ensureWorktreesDir();

  // Check for existing loops
  const worktrees = listWorktrees();
  if (worktrees.length > 0) {
    info('Existing worktrees:');
    for (const wt of worktrees) {
      const statuses = getLoopStatus(wt.spec);
      const running = statuses?.running ? c('green', 'RUNNING') : c('dim', 'idle');
      console.log(`    ${c('cyan', wt.spec)} [${running}] branch: ${wt.branch}`);
    }
    console.log('');
  }

  // Write MCP config
  const mcpConfigPath = writeMcpConfig();

  // Build system prompt and inject into CLAUDE.local.md
  // (avoids Windows command-line length limits)
  const systemPrompt = buildSystemPrompt();
  const cleanupPrompt = injectSystemPrompt(systemPrompt);

  info('Launching Claude Code with Ralph tools...');
  console.log('');

  // Launch Claude Code — system prompt is in CLAUDE.local.md, only MCP config on CLI
  const claudeArgs = ['--mcp-config', mcpConfigPath];

  const claude = spawn('claude', claudeArgs, {
    stdio: 'inherit',
    cwd: repoDir(),
    shell: true,
  });

  function cleanup() {
    try { fs.unlinkSync(mcpConfigPath); } catch {}
    cleanupPrompt();
  }

  claude.on('close', (code) => {
    cleanup();

    console.log('');
    success('Ralph agent session ended.');

    // Report any still-running loops
    try {
      const active = getLoopStatus(null).filter(s => s.running);
      if (active.length > 0) {
        info('Still running in background:');
        for (const s of active) {
          console.log(`    ${c('cyan', s.spec)} (PID ${s.pid})`);
        }
        info('These loops will continue running. Run "ralph" again to monitor them.');
      }
    } catch {}

    process.exit(code || 0);
  });

  claude.on('error', (err) => {
    cleanup();
    error(`Failed to launch Claude Code: ${err.message}`);
    process.exit(1);
  });

  // Also clean up on unexpected exit
  process.on('exit', cleanup);
  process.on('SIGINT', () => { cleanup(); process.exit(130); });
  process.on('SIGTERM', () => { cleanup(); process.exit(143); });
}

module.exports = { run };
