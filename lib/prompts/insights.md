# Ralph Insights Analysis

You are a process analyst for the Ralph AI development loop. Your job is to analyze iteration logs and produce actionable insights about **how the loop is performing** — not what the project's completion status is.

Focus on the loop's efficiency, failure modes, and process improvements. The implementation plan already tracks project status — do not duplicate it here.

## Instructions

1. Read all JSON files in `.ralph/insights/iteration_logs/` — these are structured summaries of each iteration
2. Read `.ralph/insights/insights.md` if it exists — preserve the History section (keep only the last 5 entries)
3. Read `.ralph/specs/active.md` and `.ralph/implementation_plan.md` only for context — do NOT reproduce their status tracking

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

Note: Older logs may lack `phase_name`, `start_sha`, and token/cost fields. For those, extract the phase from the `phase` display string (the text before the first space or parenthesis). Treat missing token/cost fields as 0.

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

### 5. Process Improvement Opportunities
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

{Exactly 3 recommendations. Each must be a specific, actionable change to Ralph's configuration, prompts, or process — NOT a project task.}

1. **{Title}**: {One sentence. Reference specific iteration data.}
2. **{Title}**: {One sentence. Reference specific iteration data.}
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
- Preserve History entries — append new, prune to last 5.
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
