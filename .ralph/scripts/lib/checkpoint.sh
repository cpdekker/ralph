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
            echo -e "${C_WARNING}📋 Found checkpoint for $SPEC_NAME${C_RESET}"
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

# ═══════════════════════════════════════════════════════════════════════════════
# CROSS-ITERATION MEMORY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# append_progress() — Appends a timestamped entry to progress.txt
append_progress() {
    local event_type=$1  # e.g., session_start, iteration_success, phase_start, error, circuit_breaker
    local message=$2
    local progress_file="./.ralph/progress.txt"
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create with header if missing
    if [ ! -f "$progress_file" ]; then
        cat > "$progress_file" << 'HEADER'
# Ralph Progress Log
<!-- This file is append-only cross-iteration memory. Claude reads this at the start of each iteration to understand prior context. -->
HEADER
    fi

    echo "[$now] [$event_type] $message" >> "$progress_file"
}

# init_guardrails() — Creates guardrails.md template if missing
init_guardrails() {
    local guardrails_file="./.ralph/guardrails.md"
    if [ ! -f "$guardrails_file" ]; then
        cat > "$guardrails_file" << 'EOF'
# Ralph Guardrails
<!-- Accumulated lessons learned across iterations. Claude reads this before making decisions. Add new guardrails when you discover patterns that future iterations should know about. -->

## Anti-Patterns
<!-- Things that have been tried and failed. Don't repeat these. -->

## Environment Quirks
<!-- Project-specific gotchas discovered during implementation. -->

## Architectural Constraints
<!-- Decisions that were made and should not be revisited. -->

## Known Issues
<!-- Problems discovered but not yet resolved. Include context for future iterations. -->
EOF
    fi
}

# append_guardrail() — Adds a new entry to a guardrails section
append_guardrail() {
    local section=$1  # e.g., "Anti-Patterns", "Known Issues"
    local entry=$2
    local guardrails_file="./.ralph/guardrails.md"
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    init_guardrails

    # Append under the matching section header using sed
    sed -i "/^## $section$/a\\- [$now] $entry" "$guardrails_file"
}

# stage_ralph_memory() — Stages cross-iteration memory files for git
stage_ralph_memory() {
    git add .ralph/progress.txt .ralph/guardrails.md .ralph/AGENTS.md 2>/dev/null || true
}

# persist_iteration_log() — Persist minimal iteration log to .ralph/logs/ (always, regardless of insights)
persist_iteration_log() {
    local log_file=$1
    local iteration_num=$2
    local phase_display=$3
    local exit_code=$4
    local turn_start=$5
    local start_sha=${6:-""}

    local now=$(date +%s)
    local duration=$((now - turn_start))
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local phase_name=$(echo "$phase_display" | sed 's/ (.*//' | tr '[:lower:]' '[:upper:]')

    # Git-based metrics
    local files_changed=0
    local commits=0
    local code_files=0
    local ralph_files=0
    local modified_files=""
    if [ -n "$start_sha" ]; then
        modified_files=$(git diff --name-only "$start_sha" HEAD 2>/dev/null || echo "")
        files_changed=$(echo "$modified_files" | grep -c '.' 2>/dev/null || echo 0)
        commits=$(git log --oneline "$start_sha"..HEAD 2>/dev/null | wc -l | tr -d ' ')
        code_files=$(echo "$modified_files" | grep -v '^\\.ralph/' | grep -c '.' 2>/dev/null || echo 0)
        ralph_files=$(echo "$modified_files" | grep '^\\.ralph/' | grep -c '.' 2>/dev/null || echo 0)
    fi

    # Token/cost from stream-json result line
    local result_line=$(grep '"type":"result"' "$log_file" 2>/dev/null | tail -1)
    local input_tokens=0 output_tokens=0 cost_usd=0
    if [ -n "$result_line" ]; then
        input_tokens=$(echo "$result_line" | sed -n 's/.*"input_tokens":\([0-9]*\).*/\1/p')
        output_tokens=$(echo "$result_line" | sed -n 's/.*"output_tokens":\([0-9]*\).*/\1/p')
        cost_usd=$(echo "$result_line" | sed -n 's/.*"total_cost_usd":\([0-9.]*\).*/\1/p')
        input_tokens=${input_tokens:-0}; output_tokens=${output_tokens:-0}; cost_usd=${cost_usd:-0}
    fi

    local PERSISTENT_LOG_DIR="./.ralph/logs"
    mkdir -p "$PERSISTENT_LOG_DIR"

    local output_file="$PERSISTENT_LOG_DIR/${SPEC_NAME}_iter_${iteration_num}.json"
    cat > "$output_file" << EOF
{
  "timestamp": "$timestamp",
  "spec_name": "$SPEC_NAME",
  "phase": "$phase_name",
  "iteration": $iteration_num,
  "exit_code": ${exit_code:-0},
  "duration_seconds": $duration,
  "files_modified": $files_changed,
  "code_files_modified": $code_files,
  "ralph_files_modified": $ralph_files,
  "git_commits": $commits,
  "input_tokens": $input_tokens,
  "output_tokens": $output_tokens,
  "cost_usd": $cost_usd
}
EOF
    # Stage for git
    git add "$output_file" 2>/dev/null || true
}
