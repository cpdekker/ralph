// Ralph Wiggum - Interactive Log Viewer
// Streams Docker logs with a persistent command prompt for steering Ralph

const { execSync, spawn } = require('child_process');
const readline = require('readline');
const { c, separator, header, info } = require('./colors');

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const HELP_TEXT = `
  ${c('cyan', 'Available commands:')}
    ${c('bright', 'status')}          Show current phase, iteration, and progress
    ${c('bright', 'plan')}            Show the implementation plan
    ${c('bright', 'steer')} <msg>     Send a directive to Ralph (picked up next iteration)
    ${c('bright', 'ask')} <question>  Ask a question about Ralph's progress
    ${c('bright', 'pause')}           Pause Ralph after current iteration
    ${c('bright', 'resume')}          Resume a paused Ralph
    ${c('bright', 'log')}             Show recent iteration log
    ${c('bright', 'help')}            Show this help message
    ${c('bright', 'stop')}            Stop Ralph and exit

  ${c('dim', 'Type a command and press Enter. Logs continue streaming above.')}
`;

const PROMPT = `${c('dim', '[')}${c('magenta', 'ralph')}${c('dim', ']')} ${c('dim', 'status | steer | pause | help >')} `;

// ═══════════════════════════════════════════════════════════════════════════════
// COMMAND HANDLERS
// ═══════════════════════════════════════════════════════════════════════════════

function execInContainer(containerName, cmd) {
  try {
    return execSync(`docker exec ${containerName} ${cmd}`, {
      encoding: 'utf-8',
      timeout: 10000,
    });
  } catch (err) {
    if (err.killed || err.signal === 'SIGTERM') {
      return null;
    }
    const msg = err.stderr || err.message || '';
    if (msg.includes('No such container') || msg.includes('is not running')) {
      return null;
    }
    return null;
  }
}

function handleStatus(containerName, writeLine) {
  const output = execInContainer(containerName, 'cat .ralph/state.json');
  if (!output) {
    writeLine(c('yellow', '  Could not read state (Ralph may not have started yet).'));
    return;
  }
  try {
    const state = JSON.parse(output);
    writeLine('');
    writeLine(`  ${c('cyan', 'Ralph Status')}`);
    writeLine(`  ${c('dim', '─'.repeat(35))}`);
    writeLine(`    Spec:         ${state.spec_name || 'unknown'}`);
    writeLine(`    Phase:        ${state.current_phase || 'unknown'}`);
    writeLine(`    Iteration:    ${state.current_iteration || 0}`);
    writeLine(`    Total iters:  ${state.total_iterations || 0}`);
    writeLine(`    Failures:     ${state.consecutive_failures || 0}`);
    writeLine(`    Errors:       ${state.error_count || 0}`);
    writeLine(`    Last update:  ${state.last_update || 'unknown'}`);
    if (state.current_task) {
      writeLine(`    Task:         ${state.current_task}`);
    }
    if (state.is_decomposed) {
      writeLine(`    Sub-spec:     ${state.current_subspec || 'none'}`);
    }

    // Check plan progress
    const plan = execInContainer(containerName, 'cat .ralph/implementation_plan.md');
    if (plan) {
      const checked = (plan.match(/- \[x\]/gi) || []).length;
      const unchecked = (plan.match(/- \[ \]/g) || []).length;
      const total = checked + unchecked;
      if (total > 0) {
        const pct = Math.round((checked / total) * 100);
        const filled = Math.round(pct / 5);
        const bar = '[' + '#'.repeat(filled) + '-'.repeat(20 - filled) + ']';
        writeLine(`    Progress:     ${checked}/${total} tasks ${bar} ${pct}%`);
      }
    }

    // Check pause state
    const paused = execInContainer(containerName, 'test -f .ralph/pause && echo yes');
    if (paused && paused.trim() === 'yes') {
      writeLine(`\n  ${c('yellow', 'PAUSED')} — type 'resume' to continue`);
    }
    writeLine('');
  } catch {
    writeLine(output);
  }
}

function handlePlan(containerName, writeLine) {
  const output = execInContainer(containerName, 'cat .ralph/implementation_plan.md');
  if (!output) {
    writeLine(c('yellow', '  No implementation plan found yet.'));
    return;
  }
  writeLine('');
  const lines = output.split('\n');
  const maxLines = (process.stdout.rows || 40) - 5;
  if (lines.length > maxLines) {
    lines.slice(0, maxLines).forEach(l => writeLine(l));
    writeLine(c('dim', `\n  ... (${lines.length - maxLines} more lines, showing first ${maxLines})`));
  } else {
    lines.forEach(l => writeLine(l));
  }
}

function handleSteer(containerName, message, mode, writeLine) {
  if (!message || !message.trim()) {
    writeLine(c('yellow', '  Usage: steer <message>'));
    return;
  }

  let iteration = '?';
  const stateOutput = execInContainer(containerName, 'cat .ralph/state.json');
  if (stateOutput) {
    try {
      const state = JSON.parse(stateOutput);
      if (state.current_iteration !== undefined) iteration = state.current_iteration;
    } catch {}
  }

  const timestamp = new Date().toISOString();
  const mailboxContent = [
    '# User Directive',
    `**Time**: ${timestamp}`,
    `**Context**: Iteration ${iteration}, ${mode} phase`,
    '',
    '## Directive',
    message.trim(),
    '',
    '## Instructions',
    'Please read this directive and take appropriate action. This may include:',
    '- Modifying the implementation plan',
    '- Adjusting your approach for upcoming iterations',
    '- Answering a question (write response to .ralph/mailbox-reply.md)',
    '- Updating the spec or review checklist',
    '',
    'After processing, continue with your normal work.',
  ].join('\n');

  try {
    execSync(
      `docker exec -i ${containerName} tee .ralph/mailbox.md > /dev/null`,
      { input: mailboxContent, encoding: 'utf-8', timeout: 10000 },
    );
    writeLine(c('green', '  ✓ Directive sent. Ralph will pick it up next iteration.'));
  } catch (err) {
    writeLine(c('red', `  Failed to send directive: ${err.message}`));
  }
}

function handleAsk(containerName, question, mode, writeLine) {
  if (!question || !question.trim()) {
    writeLine(c('yellow', '  Usage: ask <question>'));
    return;
  }
  handleSteer(containerName, `QUESTION: ${question.trim()}`, mode, writeLine);
}

function handlePause(containerName, writeLine) {
  execInContainer(containerName, 'touch .ralph/pause');
  writeLine(c('yellow', '  ⏸ Pause requested. Ralph will pause after the current iteration.'));
}

function handleResume(containerName, writeLine) {
  execInContainer(containerName, 'rm -f .ralph/pause');
  writeLine(c('green', '  ▶ Resume requested. Ralph will continue.'));
}

function handleLog(containerName, writeLine) {
  const listing = execInContainer(containerName, "bash -c 'ls -t .ralph/logs/ 2>/dev/null | head -1'");
  if (!listing || !listing.trim()) {
    writeLine(c('yellow', '  No iteration logs found yet.'));
    return;
  }
  const latestLog = listing.trim();
  const output = execInContainer(containerName, `bash -c 'tail -50 ".ralph/logs/${latestLog}"'`);
  if (output) {
    writeLine('');
    writeLine(c('dim', `  ── ${latestLog} (last 50 lines) ──`));
    output.split('\n').forEach(l => writeLine(l));
  } else {
    writeLine(c('yellow', '  Could not read log file.'));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERACTIVE LOG VIEWER
// ═══════════════════════════════════════════════════════════════════════════════

function createInteractiveLogViewer(options) {
  const { containerName, targetBranch, spec, mode, cwd, onStop, onFinish } = options;

  let logsProcess = null;
  let rl = null;
  let stopped = false;

  // Write a line above the prompt — clears the prompt line, writes content,
  // then re-displays the prompt
  function writeAbovePrompt(text) {
    if (!rl) {
      process.stdout.write(text + '\n');
      return;
    }
    // Move to start of line, clear it, write the text, then re-show prompt
    readline.clearLine(process.stdout, 0);
    readline.cursorTo(process.stdout, 0);
    process.stdout.write(text + '\n');
    rl.prompt(true);
  }

  function handleCommand(input) {
    const trimmed = (input || '').trim();
    if (!trimmed) return;

    const parts = trimmed.split(/\s+/);
    const cmd = parts[0].toLowerCase();
    const args = parts.slice(1).join(' ');

    switch (cmd) {
      case 'help':
      case '?':
        HELP_TEXT.split('\n').forEach(l => writeAbovePrompt(l));
        break;
      case 'status':
      case 's':
        handleStatus(containerName, writeAbovePrompt);
        break;
      case 'plan':
      case 'p':
        handlePlan(containerName, writeAbovePrompt);
        break;
      case 'steer':
        handleSteer(containerName, args, mode, writeAbovePrompt);
        break;
      case 'ask':
        handleAsk(containerName, args, mode, writeAbovePrompt);
        break;
      case 'pause':
        handlePause(containerName, writeAbovePrompt);
        break;
      case 'resume':
        handleResume(containerName, writeAbovePrompt);
        break;
      case 'log':
      case 'logs':
        handleLog(containerName, writeAbovePrompt);
        break;
      case 'stop':
      case 'quit':
      case 'exit':
        if (onStop) onStop();
        return;
      default:
        writeAbovePrompt(c('yellow', `  Unknown command: '${cmd}'. Type 'help' for available commands.`));
        break;
    }
  }

  function startLogStream() {
    logsProcess = spawn('docker', ['logs', '-f', containerName], {
      stdio: ['ignore', 'pipe', 'pipe'],
      cwd: cwd,
    });

    logsProcess.stdout.on('data', (data) => {
      const text = data.toString();
      // Write each line above the prompt
      text.split('\n').forEach((line, i, arr) => {
        // Don't write empty trailing line from split
        if (i === arr.length - 1 && line === '') return;
        writeAbovePrompt(line);
      });
    });

    logsProcess.stderr.on('data', (data) => {
      const text = data.toString();
      text.split('\n').forEach((line, i, arr) => {
        if (i === arr.length - 1 && line === '') return;
        writeAbovePrompt(line);
      });
    });

    logsProcess.on('close', (code) => {
      logsProcess = null;
      if (!stopped) {
        writeAbovePrompt('');
        writeAbovePrompt(c('green', '  Ralph has finished.'));
        writeAbovePrompt(`  Pull changes:  git fetch origin && git checkout ${targetBranch}`);
        writeAbovePrompt('');
        stop();
        if (onFinish) onFinish();
      }
    });

    logsProcess.on('error', (err) => {
      writeAbovePrompt(c('red', `  Failed to stream logs: ${err.message}`));
    });
  }

  function start() {
    if (!process.stdin.isTTY) {
      // Non-TTY fallback: just pipe logs through
      logsProcess = spawn('docker', ['logs', '-f', containerName], {
        stdio: 'inherit',
        cwd: cwd,
      });

      logsProcess.on('close', () => {
        logsProcess = null;
        console.log(`\n${c('green', '  Ralph has finished.')}`);
        if (onFinish) onFinish();
      });

      return;
    }

    // Create persistent readline interface
    rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      prompt: PROMPT,
      terminal: true,
    });

    // Handle each command
    rl.on('line', (input) => {
      handleCommand(input);
      if (!stopped) {
        rl.prompt();
      }
    });

    // Handle Ctrl+C
    rl.on('SIGINT', () => {
      if (onStop) onStop();
    });

    rl.on('close', () => {
      if (!stopped) {
        stop();
      }
    });

    // Start streaming logs
    startLogStream();

    // Show the prompt immediately
    console.log('');
    console.log(c('dim', `  Logs streaming above. Type commands below. 'help' for options. Ctrl+C to stop.`));
    console.log('');
    rl.prompt();
  }

  function stop() {
    stopped = true;

    if (logsProcess) {
      try {
        logsProcess.kill('SIGTERM');
      } catch {}
      logsProcess = null;
    }

    if (rl) {
      try {
        rl.close();
      } catch {}
      rl = null;
    }
  }

  return { start, stop };
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════════════════════════

module.exports = { createInteractiveLogViewer };
