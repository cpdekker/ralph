0a. Study `.ralph/specs/active.md` to understand the spec we are building towards
0b. Study `src/*` with up to 250 parallel Sonnet subagents to learn the application specifications.
0c. Study `.ralph/IMPLEMENTATION_PLAN.md` (if present) to understand the plan so far.

1. Study `.ralph/IMPLEMENTATION_PLAN.md` (if present; it may be incorrect) and use up to 500 Sonnet subagents to study existing source code and compare it against `.ralph/specs/active.md`. Use an Opus subagent to analyze findings, prioritize tasks, and create/update `.ralph/IMPLEMENTATION_PLAN.md` as a bullet point list sorted in priority of items yet to be implemented. Ultrathink. Consider searching for TODO, minimal implementations, placeholders, skipped/flaky tests, and inconsistent patterns. Study `.ralph/IMPLEMENTATION_PLAN.md` to determine starting point for research and keep it up to date with items considered complete/incomplete using subagents.

IMPORTANT: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first. Treat `src/*` as the project's standard library for shared utilities and components. Prefer consolidated, idiomatic implementations there over ad-hoc copies.

ULTIMATE GOAL: We want to achieve [project-specific goal]. Consider missing elements and plan accordingly. If an element is missing, search first to confirm it doesn't exist, then if needed author the specification at `.ralph/specs/active.md`. If you create a new element then document the plan to implement it in `.ralph/IMPLEMENTATION_PLAN.md` using a subagent.