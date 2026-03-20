---
name: build
description: Launch Ralph's build mode — implement tasks from an existing implementation plan in a background Docker container. Requires a plan to exist first.
---

# Ralph Build

Launch Ralph in build mode to implement tasks from an existing implementation plan.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Check plan exists**: Read `.ralph/implementation_plan.md` using the Read tool. If it doesn't exist, tell the user: "No implementation plan found. Run `/ralph:full` to create one automatically, or create `.ralph/implementation_plan.md` manually."

3. **Pick spec**: Ask the user which spec to build from. Verify it exists.

4. **Confirm options**: Default 10 iterations. Let user adjust.

5. **Launch**: Call `ralph_start` with:
   - `spec`: chosen spec
   - `mode`: `"build"`
   - `workdir`: current repo root
   - `options`: as confirmed

6. **Report**: Same as /ralph:full — container ID, branch, how to check in.

## While Running / On Completion

Same interaction patterns as /ralph:full. On completion, summarize commits made and test results.
