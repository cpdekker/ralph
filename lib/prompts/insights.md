# Ralph Insights Analysis

You are a process analyst for the Ralph AI development loop. Your job is to analyze iteration logs and produce actionable insights about **how the loop is performing** — not what the project's completion status is.

Focus on the loop's efficiency, failure modes, and process improvements. The implementation plan already tracks project status — do not duplicate it here.

## Instructions

1. Read all JSON files in `.ralph/insights/iteration_logs/` — these are structured summaries of each iteration
2. Also check `.ralph/logs/` for iteration logs (the modular version stores them here)
3. Read `.ralph/insights/insights.md` if it exists — preserve the History section (keep only the last 5 entries)
4. Read `.ralph/specs/active.md` and `.ralph/implementation_plan.md` only for context — do NOT reproduce their status tracking
5. Read `.ralph/AGENTS.md` — check if it has a test strategy section. If not, and you detect test-related waste, your Project-Specific recommendations should include a concrete AGENTS.md snippet the user can add
6. If debate iterations are present in the logs, also read:
   - `.ralph/spec_debate/debate_plan.md` — to assess persona selection quality (spec debates)
   - `.ralph/spec_review.md` — to count post-debate issues and check "Raised by" attributions
   - All `*_critique.md` and `*_challenge.md` files in `.ralph/spec_debate/` — to assess contribution depth
   - `.ralph/review_debate/debate_plan.md` — to assess pairing selection quality (code review debates)
   - `.ralph/review.md` "Debate Summary" section — to count escalations, downgrades, new findings
   - All `round*_*.md` files in `.ralph/review_debate/` — to assess cross-examination depth

## Iteration Log Schema

Each JSON log contains:
- `phase_name` — The phase (PLAN, BUILD, REVIEW, REVIEW-FIX, etc.) — use this for grouping
- `phase` — Display string including iteration count (e.g. "BUILD (3/10)")
- `iteration` — Global iteration number
- `exit_code` — 0 = success, non-zero = failure
- `duration_seconds` — Wall-clock time for the iteration
- `files_modified_count` — Number of files changed (from git diff)
- `git_commits` — Number of commits made this iteration
- `test_commands_run` — Number of test command invocations (not individual test cases)
- `input_tokens` — Claude input tokens consumed (0 if unavailable)
- `output_tokens` — Claude output tokens generated (0 if unavailable)
- `cost_usd` — Iteration cost in USD (0 if unavailable)
- `modified_files` — Comma-separated list of changed files
- `recent_commits` — Last 3 commit messages
- `error_snippet` — Error text if the iteration failed
- `start_sha` — Git SHA at iteration start (for diffing)
- `debate_subphase` — (debate iterations only) One of: SETUP, CRITIQUE, CHALLENGE, CROSS-EXAMINE, SYNTHESIZE. Empty for non-debate iterations. CRITIQUE/CHALLENGE are used in spec debates; CROSS-EXAMINE is used in code review debates.
- `debate_persona` — (debate iterations only) The persona ID (e.g. "skeptic", "architect", "security") or pairing description (e.g. "security vs api"). Empty for SETUP/SYNTHESIZE and non-debate iterations.

Note: Older logs may lack `phase_name`, `start_sha`, token/cost, and debate fields. For those, extract the phase from the `phase` display string (the text before the first space or parenthesis). Treat missing token/cost fields as 0. Treat missing debate fields as empty.

## Analysis Categories

### 1. Failure & Error Patterns
- Which phases fail and why? Are errors recurring or one-off?
- Are there error_snippet patterns suggesting systematic issues?

### 2. Phase Efficiency
- Average duration per phase (group by `phase_name`)
- Which phases are disproportionately slow relative to their output?
- Time allocation: what % of total time does each phase consume?

### 3. Spinning & Waste Detection

Flag iterations that show signs of unproductive work:
- **Spinning**: duration > 300s AND files_modified_count == 0 AND git_commits < 2
- **Thrashing**: same files appearing in modified_files across 3+ consecutive iterations
- **Rework**: commit messages containing "revert", "fix:", or "undo" immediately after "feat:" or "implement"
- **Verification loops**: 3+ consecutive PLAN iterations with 0 code file changes

### 4. Phase Transition Analysis

This is the most valuable analysis. Evaluate whether phase transitions were timed correctly:
- Did BUILD end prematurely (significant uncompleted work requiring REVIEW-FIX to finish implementation)?
- Did PLAN run too many verification iterations with diminishing returns?
- Did REVIEW find issues that could have been caught with automated tooling during BUILD?
- Were phase iteration counts (e.g. FULL_PLAN_ITERS=5) well-calibrated?

### 5. Debate Effectiveness

If iteration logs contain debate sub-phases (non-empty `debate_subphase`), analyze the Socratic debate. There are two debate contexts — apply the relevant analysis:

#### Spec Debate (CRITIQUE + CHALLENGE sub-phases)

**Persona Contribution Balance**
- Compare duration and token usage across personas in the CRITIQUE sub-phase
- Flag if any persona took disproportionately long (>2x the average) — may indicate prompt bloat or scope mismatch
- Flag if any persona was very fast with few file changes — may indicate shallow analysis

**Challenge Round Value**
- Compare CRITIQUE-only cost/duration vs CHALLENGE cost/duration. Was the challenge round worth the extra ~3 iterations?
- Read `.ralph/spec_review.md` if it exists — check the "Raised by" annotations to see if challenge-round findings appear
- If challenge rounds consistently add no new findings, recommend disabling via `SPEC_DEBATE_CHALLENGE=false`

**Persona Selection Quality**
- Read `.ralph/spec_debate/debate_plan.md` if it exists — were the selected personas appropriate for the spec content?
- Check if any persona's critique was largely "What's Actually Good" / "What Serves Users Well" with few real concerns — may indicate wrong persona for this spec

#### Code Review Debate (CROSS-EXAMINE sub-phases)

**Pairing Effectiveness**
- Compare duration and token usage across cross-examination rounds
- Flag pairings that took disproportionately long or short — may indicate mismatch or shallow analysis
- Read `.ralph/review_debate/debate_plan.md` to check if the planned pairings were appropriate

**Cross-Examination Value**
- Read `.ralph/review.md` "Debate Summary" section if it exists — count escalations, downgrades, new findings
- If cross-examination consistently adds no new findings or severity changes, recommend reducing `REVIEW_DEBATE_ROUNDS` or disabling via `REVIEW_DEBATE_ENABLED=false`
- Read `round*_*.md` files in `.ralph/review_debate/` to assess cross-examination depth

**Pairing Diversity**
- Did the setup select diverse pairings covering different specialist combinations?
- Were the same specialists over-represented across rounds?
- Recommend specific pairing adjustments based on which rounds were most productive

#### Common to Both Debate Types

**Debate vs Review-Fix Cascade**
- After debate, how many BLOCKING/ATTENTION issues did review-fix need to address?
- Compare this to the total findings from the debate — are the debate findings actionable or mostly noise?
- High noise ratio (many debate findings but few review-fix actions) suggests prompts need tightening

**Cost Efficiency**
- Total debate cost (all debate sub-phases) vs what a single review iteration would cost
- If debate consistently costs >4x a single review with similar outcomes, flag for evaluation

### 6. Process Improvement Opportunities
- Could iteration counts be adjusted for specific phases?
- Are there phases that could be consolidated or skipped?
- Would quality gates during BUILD reduce REVIEW burden?
- Specific prompt or configuration changes that would improve efficiency

## Output

Write or update `.ralph/insights/insights.md`. **Keep the total output under 150 lines.** Use this structure:

```markdown
# Ralph Insights

> Auto-generated process analysis. Last updated: {timestamp}

## Summary
{2-3 sentences: iteration count, success rate, biggest process concern}

## Critical Findings

| # | Severity | Category | Finding | Recommendation | Iterations |
|---|----------|----------|---------|----------------|------------|
{Max 5 rows. Only include actual problems — not positive observations.}
{Severity: HIGH = needs action before next run, MEDIUM = address soon, LOW = improvement opportunity}

## Efficiency Metrics

| Metric | Value |
|--------|-------|
| Total iterations | N |
| Success rate | N% (N/N) |
| Total work time | Xs (N min) |
| Avg duration by phase | PLAN: Xs, BUILD: Xs, REVIEW: Xs, REVIEW-FIX: Xs |
| Time allocation | PLAN: N%, BUILD: N%, REVIEW: N%, REVIEW-FIX: N% |
| Avg files modified/iter | N (by phase: PLAN: N, BUILD: N, REVIEW: N) |
| Avg commits/iter | N |
| Total cost | $N.NN (avg $N.NN/iter) |
| Cost by phase | PLAN: $N.NN, BUILD: $N.NN, REVIEW: $N.NN, REVIEW-FIX: $N.NN |
| Total tokens | Nk input, Nk output |

## Debate Effectiveness

{Only include this section if debate iterations are present in the logs. Otherwise omit entirely.}

| Metric | Value |
|--------|-------|
| Personas selected | [list] |
| Debate total cost | $N.NN (SETUP: $N.NN, CRITIQUE: $N.NN, CHALLENGE: $N.NN, SYNTHESIZE: $N.NN) |
| Debate total duration | Xs (N min) |
| Challenge round cost | $N.NN ({N%} of debate total) |
| Persona balance | [e.g. "skeptic: 45s/$0.12, architect: 38s/$0.10, qa: 52s/$0.14"] |
| Post-debate blocking issues | N |
| Post-debate attention issues | N |
| Challenge/cross-exam added findings | [yes/no/unknown — check debate artifacts for new findings not in original reviews] |

### Debate Assessment
{1-2 sentences: Was the debate worth the cost? Were the pairings/personas productive? Was cross-examination valuable?}

### Debate Recommendations
{Only if there are actionable improvements. Examples:}
{- "Disable challenge round (SPEC_DEBATE_CHALLENGE=false) — added $X.XX cost with no new findings"}
{- "Reduce REVIEW_DEBATE_ROUNDS from 3 to 2 — round 3 added no value"}
{- "Pairing security:api was most productive — consider always including it"}
{- "Persona X contributed little to this spec type — consider adjusting selection logic in setup.md"}

## Waste Indicators

{Only include this section if spinning, thrashing, or rework was detected. Otherwise omit entirely.}
- Spinning iterations: {list or "none detected"}
- Thrashing files: {list or "none detected"}
- Rework patterns: {list or "none detected"}

## Phase Transition Assessment

{For each phase transition that occurred, one sentence on whether it was well-timed.}
{Example: "PLAN→BUILD: Appropriate — 5 iterations produced a complete plan with no rework needed."}
{Example: "BUILD→REVIEW: Premature — BUILD ended at 67% completion, requiring REVIEW-FIX to finish implementation work."}

## Recommendations

{Exactly 3 recommendations. Split into two categories:}

### Ralph-Actionable (changes to Ralph prompts, loop config, or scripts)
{Only include recommendations that Ralph's maintainer can implement by modifying files in `.ralph/` or `lib/`. Reference the specific prompt file, script, or config to change.}

1. **{Title}**: {One sentence. Reference specific iteration data and the file to change.}

### Project-Specific (changes the user should make to AGENTS.md or repo config)
{Recommendations that depend on the destination project's test runner, build system, or tooling. The user must act on these — Ralph can't automate them. For test-related recommendations, suggest a concrete AGENTS.md snippet the user could add (e.g., "Add to AGENTS.md: `## Test Strategy\n- For targeted tests: npm run test -- --testPathPattern=<changed-module>`").}

2. **{Title}**: {One sentence. Reference specific iteration data. Include a suggested AGENTS.md snippet if applicable.}
3. **{Title}**: {One sentence. Reference specific iteration data.}

## History
{Append-only. Keep only the last 5 entries — remove older ones.}

### {timestamp}
- Analyzed N iteration logs ({phase breakdown})
- Key finding: {one-liner about the most important process insight}
```

## Rules

- **Focus on process, not project status** — never list implementation completion percentages, remaining tasks, or phase completion checklists. That belongs in the implementation plan.
- Do not include positive observations (e.g. "zero errors — excellent!") in the Critical Findings table. Mention them briefly in the Summary if noteworthy.
- Recommendations must be about the Ralph loop process (iteration counts, prompt changes, phase timing, quality gates) — NOT about what code to write next.
- Keep total output under 150 lines. Be concise. If a section has nothing to report, omit it entirely.
- NEVER modify spec files or implementation plans.
- Preserve History entries — append new, prune to last 5. **Deduplicate**: if the new entry's key finding is substantially the same as the most recent entry (same iteration, same issue), update that entry's timestamp instead of appending a duplicate.
- Cite specific iteration numbers when referencing findings.
- If no iteration logs exist, write a minimal insights.md noting that no data is available yet.
- Commit the updated insights.md with message "ralph: update insights analysis"
- Push the commit to the current branch

## After Writing

```bash
git add .ralph/insights/insights.md
git commit -m "ralph: update insights analysis"
git push origin "$(git branch --show-current)" 2>/dev/null || true
```
