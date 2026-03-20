---
name: research
description: Launch Ralph's deep research mode — parallel codebase and web research in a background Docker container. Use for investigating topics, understanding systems, or gathering context.
---

# Ralph Research

Launch Ralph in research mode for deep parallel investigation of a topic.

## Steps

1. **Pre-flight**: Call `ralph_setup` with the current workdir. If not ready, tell the user to run `/ralph:setup` first.

2. **Gather topic**: Ask the user what they want to research. Get:
   - Research question or topic
   - Any specific areas to focus on
   - Context they already have

3. **Create seed**: Compose the seed content as a markdown document:
   ```
   # Research: <topic>

   ## Question
   <user's research question>

   ## Focus Areas
   <specific areas>

   ## Known Context
   <what user already knows>
   ```

4. **Choose name**: Ask the user for a short name for this research (used as branch name).

5. **Launch**: Call `ralph_start` with:
   - `spec`: the chosen name
   - `mode`: `"research"`
   - `workdir`: current repo root
   - `options`: `{ iterations: 10, seedContent: <the seed markdown> }`

6. **Report**: Container ID, branch, how to check in.

## On Completion

1. Call `ralph_result` with `artifact: "research"` to pull research outputs from `.ralph/references/`
2. Present a summary of findings organized by topic
3. Offer to show full research documents
