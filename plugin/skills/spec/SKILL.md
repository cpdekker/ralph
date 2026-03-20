---
name: spec
description: Launch Ralph's interactive spec creation — gather requirements, research, draft, debate, and refine a specification in a background Docker container.
---

# Ralph Spec

Launch Ralph in spec mode to create a detailed specification through an iterative process.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Gather requirements**: Ask the user about what they want to build:
   - What is the feature or system?
   - What problem does it solve?
   - Any constraints or requirements?
   - Success criteria?

3. **Create seed**: Compose seed content:
   ```
   # Spec: <feature name>

   ## What
   <description of feature/system>

   ## Problem
   <what problem it solves>

   ## Constraints
   <any constraints>

   ## Success Criteria
   <how to know it's done>
   ```

4. **Choose name**: Ask for a short name for the spec.

5. **Launch**: Call `ralph_start` with:
   - `spec`: chosen name
   - `mode`: `"spec"`
   - `workdir`: current repo root
   - `options`: `{ iterations: 8, seedContent: <the seed markdown> }`

6. **Report**: Container ID, branch, how to check in.

## On Completion

1. Call `ralph_result` with `artifact: "spec"` to pull the generated spec
2. Present the full spec for user review
3. Ask if they want to proceed with implementation: "Ready to build this? Run `/ralph:full` with this spec"
