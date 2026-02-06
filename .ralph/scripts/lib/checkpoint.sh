#!/bin/bash
# Ralph Wiggum - Checkpointing & State Management
# Sourced by loop.sh — do not run directly.

# Save current state to checkpoint file
save_state() {
    local phase=$1
    local iteration=$2
    local task=$3
    local last_commit=$(git rev-parse HEAD 2>/dev/null || echo "none")
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$STATE_FILE" << EOF
{
  "spec_name": "$SPEC_NAME",
  "current_phase": "$phase",
  "current_iteration": $iteration,
  "current_task": "$task",
  "last_successful_commit": "$last_commit",
  "session_start": "${SESSION_START:-$now}",
  "last_update": "$now",
  "consecutive_failures": $CONSECUTIVE_FAILURES,
  "total_iterations": $TOTAL_ITERATIONS,
  "error_count": ${ERROR_COUNT:-0},
  "is_decomposed": ${IS_DECOMPOSED:-false},
  "current_subspec": "${CURRENT_SUBSPEC:-}"
}
EOF
}

# Load state from checkpoint file (if exists and matches current spec)
load_state() {
    if [ -f "$STATE_FILE" ]; then
        local saved_spec=$(grep -o '"spec_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | head -1 | sed 's/"spec_name"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/')
        if [ "$saved_spec" = "$SPEC_NAME" ]; then
            echo -e "\033[1;33m📋 Found checkpoint for $SPEC_NAME\033[0m"
            cat "$STATE_FILE"
            echo ""
            return 0
        fi
    fi
    return 1
}

# Create paused state file when circuit breaker trips
create_paused_state() {
    local reason=$1
    cat > "./.ralph/paused.md" << EOF
# ⚠️ Ralph Paused - Human Intervention Required

**Spec**: $SPEC_NAME
**Branch**: $CURRENT_BRANCH
**Time**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Reason**: $reason

## Context

- **Consecutive failures**: $CONSECUTIVE_FAILURES
- **Last iteration**: $ITERATION
- **Mode**: $MODE

## What Happened

$reason

## Suggested Actions

1. Check the logs in the temp directory or verbose output
2. Review the latest changes: \`git diff HEAD~1\`
3. Check \`.ralph/implementation_plan.md\` for [BLOCKED] items
4. Fix the issue manually or update AGENTS.md with guidance
5. Delete this file and restart Ralph

## Resume Command

\`\`\`bash
rm .ralph/paused.md
node .ralph/run.js $SPEC_NAME $MODE
\`\`\`
EOF
    git add .ralph/paused.md
    git commit -m "Ralph paused: $reason"
    git push origin "$CURRENT_BRANCH" 2>/dev/null || true
}
