---
name: full
description: Launch Ralph's full autonomous cycle — plan, build, review, fix, and check — in a background Docker container. Use for end-to-end feature implementation from a spec.
---

# Ralph Full Cycle

Launch an autonomous Ralph container that runs: plan -> build -> review -> fix -> distill -> completion check, repeating until done.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Pick spec**: Ask the user which spec to run. If they provide a name, verify it exists as `.ralph/specs/<name>.md`. If they're unsure, list available specs from the `.ralph/specs/` directory using the Glob tool.

3. **Confirm options**: Ask the user to confirm:
   - Iterations (default: 10 cycles)
   - Whether to enable insights collection
   Show defaults and let user press enter to accept.

4. **Launch**: Call `ralph_start` with:
   - `spec`: the chosen spec name
   - `mode`: `"full"`
   - `workdir`: current repo root
   - `options`: `{ iterations, insights }` as confirmed

5. **Report**: Tell the user:
   - Container ID and name
   - Branch being worked on (`ralph/<spec>`)
   - How to check in: "Ask me for status anytime", "Say 'show Ralph logs' for recent output", "Say 'tell Ralph to...' to steer it"

## While Running

The user can interact naturally:
- "What's Ralph doing?" → call `ralph_status` then `ralph_logs`
- "Tell Ralph to skip tests" → call `ralph_steer` with the directive
- "Pause Ralph" → call `ralph_control` with `action: "pause"`
- "Resume Ralph" → call `ralph_control` with `action: "resume"`

## On Completion

When the user asks for results or status shows the container stopped:
1. Call `ralph_result` with `artifact: "all"` to pull everything
2. Summarize: what was built (plan), what was reviewed (review findings), branch name
3. Suggest: "Check out the `ralph/<spec>` branch to see the changes, or I can show you specific artifacts"
4. Offer cleanup: "Want me to remove the container?"
