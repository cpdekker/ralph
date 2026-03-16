const { z } = require('zod');
const fs = require('fs');
const path = require('path');
const { getWorktreePath, worktreeExists } = require('../../utils/worktree');
const { getAvailableSpecs } = require('../../utils/paths');

/**
 * Register state reading and tweaking MCP tools.
 */
function registerStateTools(server) {
  // ralph_list_specs
  server.tool(
    'ralph_list_specs',
    'List available spec files in .ralph/specs/.',
    {},
    async () => {
      try {
        const specs = getAvailableSpecs();
        if (specs.length === 0) {
          return {
            content: [{ type: 'text', text: 'No specs found. Create one with `ralph spec <name>` or add a .md file to .ralph/specs/.' }],
          };
        }
        return {
          content: [{
            type: 'text',
            text: `Available specs:\n${specs.map(s => `  - ${s}`).join('\n')}`,
          }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error listing specs: ${err.message}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_read_spec
  server.tool(
    'ralph_read_spec',
    'Read a spec file from .ralph/specs/ in the main repo.',
    {
      name: z.string().describe('Spec name (without .md extension)'),
    },
    async ({ name }) => {
      try {
        const specPath = path.join(process.cwd(), '.ralph', 'specs', `${name}.md`);
        if (!fs.existsSync(specPath)) {
          return {
            content: [{ type: 'text', text: `Spec not found: ${name}.md` }],
            isError: true,
          };
        }
        return {
          content: [{ type: 'text', text: fs.readFileSync(specPath, 'utf-8') }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error reading spec: ${err.message}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_read_plan
  server.tool(
    'ralph_read_plan',
    'Read the implementation plan from a worktree.',
    {
      spec: z.string().describe('Spec name'),
    },
    async ({ spec }) => {
      try {
        const wtPath = getWorktreePath(spec);
        if (!worktreeExists(spec)) {
          return {
            content: [{ type: 'text', text: `No worktree found for "${spec}"` }],
            isError: true,
          };
        }

        // Try multiple common plan file locations
        const candidates = [
          path.join(wtPath, '.ralph', 'implementation_plan.md'),
          path.join(wtPath, 'implementation_plan.md'),
          path.join(wtPath, '.ralph', 'IMPLEMENTATION_PLAN.md'),
        ];

        for (const p of candidates) {
          if (fs.existsSync(p)) {
            return {
              content: [{ type: 'text', text: fs.readFileSync(p, 'utf-8') }],
            };
          }
        }

        return {
          content: [{ type: 'text', text: `No implementation plan found in worktree for "${spec}"` }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error reading plan: ${err.message}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_read_review
  server.tool(
    'ralph_read_review',
    'Read review output from a worktree.',
    {
      spec: z.string().describe('Spec name'),
    },
    async ({ spec }) => {
      try {
        const wtPath = getWorktreePath(spec);
        if (!worktreeExists(spec)) {
          return {
            content: [{ type: 'text', text: `No worktree found for "${spec}"` }],
            isError: true,
          };
        }

        const parts = [];

        const reviewPath = path.join(wtPath, '.ralph', 'review.md');
        if (fs.existsSync(reviewPath)) {
          parts.push('# Review\n' + fs.readFileSync(reviewPath, 'utf-8'));
        }

        const checklistPath = path.join(wtPath, '.ralph', 'review_checklist.md');
        if (fs.existsSync(checklistPath)) {
          parts.push('# Review Checklist\n' + fs.readFileSync(checklistPath, 'utf-8'));
        }

        if (parts.length === 0) {
          return {
            content: [{ type: 'text', text: `No review output found in worktree for "${spec}"` }],
          };
        }

        return {
          content: [{ type: 'text', text: parts.join('\n\n---\n\n') }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error reading review: ${err.message}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_read_state
  server.tool(
    'ralph_read_state',
    'Read the state.json checkpoint file from a worktree.',
    {
      spec: z.string().describe('Spec name'),
    },
    async ({ spec }) => {
      try {
        const wtPath = getWorktreePath(spec);
        if (!worktreeExists(spec)) {
          return {
            content: [{ type: 'text', text: `No worktree found for "${spec}"` }],
            isError: true,
          };
        }

        const statePath = path.join(wtPath, '.ralph', 'state.json');
        if (!fs.existsSync(statePath)) {
          return {
            content: [{ type: 'text', text: `No state.json found in worktree for "${spec}"` }],
          };
        }

        const state = JSON.parse(fs.readFileSync(statePath, 'utf-8'));
        return {
          content: [{
            type: 'text',
            text: JSON.stringify(state, null, 2),
          }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error reading state: ${err.message}` }],
          isError: true,
        };
      }
    }
  );

  // ralph_tweak
  server.tool(
    'ralph_tweak',
    'Write or append content to a file in a worktree. Use this to adjust guardrails, plans, or other files while a loop is running.',
    {
      spec: z.string().describe('Spec name'),
      file: z.string().describe('File path relative to the worktree (e.g., ".ralph/guardrails.md")'),
      content: z.string().describe('Content to write or append'),
      append: z.boolean().default(true).describe('Append to file instead of overwriting'),
    },
    async ({ spec, file, content, append }) => {
      try {
        const wtPath = getWorktreePath(spec);
        if (!worktreeExists(spec)) {
          return {
            content: [{ type: 'text', text: `No worktree found for "${spec}"` }],
            isError: true,
          };
        }

        const filePath = path.join(wtPath, file);

        // Ensure parent directory exists
        fs.mkdirSync(path.dirname(filePath), { recursive: true });

        if (append && fs.existsSync(filePath)) {
          const existing = fs.readFileSync(filePath, 'utf-8');
          fs.writeFileSync(filePath, existing.trimEnd() + '\n' + content + '\n');
        } else {
          fs.writeFileSync(filePath, content + '\n');
        }

        return {
          content: [{
            type: 'text',
            text: `${append ? 'Appended to' : 'Wrote'} ${file} in worktree for "${spec}". The loop will pick up changes on its next iteration.`,
          }],
        };
      } catch (err) {
        return {
          content: [{ type: 'text', text: `Error tweaking file: ${err.message}` }],
          isError: true,
        };
      }
    }
  );
}

module.exports = { registerStateTools };
