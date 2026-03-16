const { z } = require('zod');
const { startLoop, stopLoop, getLoopStatus, getLoopLogs } = require('../../agent/loop-runner');

/**
 * Register loop management MCP tools.
 */
function registerLoopTools(server) {
  // ralph_start_loop
  server.tool(
    'ralph_start_loop',
    'Start a Ralph loop for a spec. Creates a git worktree and runs the loop in a sandboxed Docker container (or locally with local=true).',
    {
      spec: z.string().describe('Spec name (without .md extension)'),
      mode: z.enum(['plan', 'build', 'review', 'review-fix', 'debug', 'full', 'decompose', 'spec', 'insights'])
        .default('build')
        .describe('Loop mode'),
      iterations: z.number().optional().describe('Number of iterations (optional, uses mode default)'),
      verbose: z.boolean().default(false).describe('Enable verbose output'),
      local: z.boolean().default(false).describe('Run locally via bash instead of Docker (less secure)'),
    },
    async ({ spec, mode, iterations, verbose, local }) => {
      try {
        const opts = {};
        if (iterations) opts.iterations = iterations;
        if (verbose) opts.verbose = verbose;
        if (local) opts.local = true;

        const result = startLoop(spec, mode || 'build', opts);

        return {
          content: [{
            type: 'text',
            text: JSON.stringify({
              success: true,
              spec: result.spec,
              mode: result.mode,
              iterations: result.iterations,
              pid: result.pid,
              container: result.container || null,
              worktree: result.wtPath,
              branch: `ralph/${spec}`,
              logPath: result.logPath,
              message: result.container
                ? `Loop started for "${spec}" in ${result.mode} mode (container ${result.container})`
                : `Loop started for "${spec}" in ${result.mode} mode (PID ${result.pid})`,
            }, null, 2),
          }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error starting loop: ${err.message}\n${err.stack}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_stop_loop
  server.tool(
    'ralph_stop_loop',
    'Stop a running Ralph loop.',
    {
      spec: z.string().describe('Spec name'),
      remove_worktree: z.boolean().default(false).describe('Also remove the worktree'),
    },
    async ({ spec, remove_worktree }) => {
      try {
        const result = stopLoop(spec, { removeWt: remove_worktree });
        return {
          content: [{
            type: 'text',
            text: JSON.stringify({
              success: true,
              spec,
              stopped: true,
              pid: result.pid,
              container: result.container || null,
              worktreeRemoved: !!remove_worktree,
            }, null, 2),
          }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error stopping loop: ${err.message}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_loop_status
  server.tool(
    'ralph_loop_status',
    'Get status of running Ralph loops. If spec is omitted, returns status of all loops.',
    {
      spec: z.string().optional().describe('Spec name (optional, omit for all loops)'),
    },
    async ({ spec }) => {
      try {
        const status = getLoopStatus(spec || null);
        return {
          content: [{
            type: 'text',
            text: JSON.stringify(status, null, 2),
          }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error getting status: ${err.message}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_loop_logs
  server.tool(
    'ralph_loop_logs',
    'Get recent log output from a Ralph loop.',
    {
      spec: z.string().describe('Spec name'),
      lines: z.number().default(50).describe('Number of lines to return (default: 50)'),
    },
    async ({ spec, lines }) => {
      try {
        const logs = getLoopLogs(spec, lines || 50);
        return {
          content: [{ type: 'text', text: logs }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error reading logs: ${err.message}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_list_loops
  server.tool(
    'ralph_list_loops',
    'List all Ralph worktrees and their loop status.',
    {},
    async () => {
      try {
        const statuses = getLoopStatus(null);
        if (statuses.length === 0) {
          return {
            content: [{ type: 'text', text: 'No active worktrees or loops found.' }],
          };
        }
        return {
          content: [{
            type: 'text',
            text: JSON.stringify(statuses, null, 2),
          }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error listing loops: ${err.message}` }],
          isError: true,
        };
      }
    }
  );
}

module.exports = { registerLoopTools };
