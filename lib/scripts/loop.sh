#!/bin/bash
# Usage: ./loop.sh <spec-name> [plan|build|review|review-fix|debug|full|decompose|spec|insights] [max_iterations] [--verbose]
# Examples:
#   ./loop.sh my-feature                    # Build mode, 10 iterations, quiet
#   ./loop.sh my-feature plan               # Plan mode, 5 iterations, quiet
#   ./loop.sh my-feature build 20           # Build mode, 20 iterations, quiet
#   ./loop.sh my-feature review             # Review mode, 10 iterations, quiet
#   ./loop.sh my-feature review-fix         # Review-fix mode, 5 iterations, quiet
#   ./loop.sh my-feature debug              # Debug mode, 1 iteration, verbose, no commit
#   ./loop.sh my-feature plan 10 --verbose  # Plan mode, 10 iterations, verbose
#   ./loop.sh my-feature full               # Full mode: plan→build→review→check cycles
#   ./loop.sh my-feature full 100           # Full mode with max 100 total iterations
#   ./loop.sh my-feature decompose          # Decompose large spec into sub-specs
#   ./loop.sh my-feature spec               # Spec mode: research→draft→refine→review→signoff
#
# Full mode options (via environment variables):
#   FULL_PLAN_ITERS=5       # Plan iterations per cycle (default: 5)
#   FULL_BUILD_ITERS=10     # Build iterations per cycle (default: 10)
#   FULL_REVIEW_ITERS=25    # Review iterations per cycle (default: 25)
#   FULL_REVIEWFIX_ITERS=5  # Review-fix iterations per cycle (default: 5)
#   FULL_DISTILL_ITERS=1    # Distill iterations per cycle (default: 1)
#
# Parallel review settings (via environment variables):
#   PARALLEL_REVIEW=true        # Enable parallel review specialists (default: true)
#   PARALLEL_REVIEW_MAX=4       # Max concurrent Claude review processes (default: 4)
#
# Circuit breaker settings (via environment variables):
#   MAX_CONSECUTIVE_FAILURES=3  # Stop after N consecutive failures (default: 3)

# Resolve prompt directory: /ralph-lib/prompts when run via CLI, or ./.ralph/prompts as fallback
# When ralph CLI mounts lib/ at /ralph-lib, prompts live there.
# For local overrides, check ./.ralph/prompts/ first.
if [ -d "/ralph-lib/prompts" ]; then
    PROMPTS_DIR="/ralph-lib/prompts"
else
    PROMPTS_DIR="./.ralph/prompts"
fi

# Helper: resolve a prompt path with local override support
# Usage: resolve_prompt "plan.md" or resolve_prompt "review/security.md"
resolve_prompt() {
    local rel_path="$1"
    local local_path="./.ralph/prompts/$rel_path"
    if [ -f "$local_path" ]; then
        echo "$local_path"
    else
        echo "$PROMPTS_DIR/$rel_path"
    fi
}

# Parse arguments
SPEC_NAME=""
MODE=""
MAX_ITERATIONS=""
VERBOSE=false

for arg in "$@"; do
    if [ "$arg" = "--verbose" ] || [ "$arg" = "-v" ]; then
        VERBOSE=true
    elif [ -z "$SPEC_NAME" ]; then
        SPEC_NAME="$arg"
    elif [ -z "$MODE" ] && ([ "$arg" = "plan" ] || [ "$arg" = "build" ] || [ "$arg" = "review" ] || [ "$arg" = "review-fix" ] || [ "$arg" = "debug" ] || [ "$arg" = "full" ] || [ "$arg" = "decompose" ] || [ "$arg" = "spec" ] || [ "$arg" = "insights" ]); then
        MODE="$arg"
    elif [ -z "$MAX_ITERATIONS" ] && [[ "$arg" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$arg"
    fi
done

# First argument is required: spec name
if [ -z "$SPEC_NAME" ]; then
    echo "Error: Spec name is required"
    echo "Usage: ./loop.sh <spec-name> [plan|build|review|review-fix|debug|full|decompose|spec] [max_iterations] [--verbose]"
    exit 1
fi

# Insights configuration (opt-in via environment variables)
INSIGHTS_ENABLED=${RALPH_INSIGHTS:-false}
INSIGHTS_GITHUB=${RALPH_INSIGHTS_GITHUB:-false}
INSIGHTS_DIR="./.ralph/insights"
INSIGHTS_LOGS_DIR="$INSIGHTS_DIR/iteration_logs"

if [ "$INSIGHTS_ENABLED" = "true" ]; then
    mkdir -p "$INSIGHTS_LOGS_DIR"
fi

# Verify spec file exists (skip for spec mode — spec doesn't exist yet)
SPEC_FILE="./.ralph/specs/${SPEC_NAME}.md"
if [ "$MODE" != "spec" ] && [ "$MODE" != "insights" ]; then
    if [ ! -f "$SPEC_FILE" ]; then
        echo "Error: Spec file not found: $SPEC_FILE"
        echo "Available specs:"
        ls -1 ./.ralph/specs/*.md 2>/dev/null | grep -v active.md | xargs -I {} basename {} .md | sed 's/^/  - /'
        exit 1
    fi

    # Copy spec to active.md (skip for decomposed specs in full mode — spec_select handles it)
    ACTIVE_SPEC="./.ralph/specs/active.md"
    if [ "$MODE" = "full" ] && [ -f "./.ralph/specs/${SPEC_NAME}/manifest.json" ]; then
        echo "Decomposed spec detected — spec_select will manage active.md"
    else
        echo "Copying $SPEC_FILE to $ACTIVE_SPEC"
        cp "$SPEC_FILE" "$ACTIVE_SPEC"
    fi
else
    ACTIVE_SPEC="./.ralph/specs/active.md"
    echo "Spec mode — spec will be created during the draft phase"
fi

# Circuit breaker settings
MAX_CONSECUTIVE_FAILURES=${MAX_CONSECUTIVE_FAILURES:-3}
CONSECUTIVE_FAILURES=0

# State file for checkpointing
STATE_FILE="./.ralph/state.json"

# Set defaults based on mode
if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="$(resolve_prompt plan.md)"
    MAX_ITERATIONS=${MAX_ITERATIONS:-5}
elif [ "$MODE" = "review" ]; then
    SETUP_PROMPT_FILE="$(resolve_prompt review/setup.md)"
    PROMPT_FILE="$(resolve_prompt review/general.md)"
    MAX_ITERATIONS=${MAX_ITERATIONS:-10}
elif [ "$MODE" = "review-fix" ]; then
    PROMPT_FILE="$(resolve_prompt review/fix.md)"
    MAX_ITERATIONS=${MAX_ITERATIONS:-5}
elif [ "$MODE" = "debug" ]; then
    # Debug mode: single iteration, verbose, no commit/push
    PROMPT_FILE="$(resolve_prompt build.md)"
    MAX_ITERATIONS=1
    VERBOSE=true
    NO_COMMIT=true
elif [ "$MODE" = "decompose" ]; then
    # Decompose mode: single iteration to break spec into sub-specs
    PROMPT_FILE="$(resolve_prompt decompose.md)"
    MAX_ITERATIONS=1
    VERBOSE=true
elif [ "$MODE" = "spec" ]; then
    # Spec mode: research → draft → refine → review → review-fix → signoff
    MAX_ITERATIONS=${MAX_ITERATIONS:-8}
    SPEC_RESEARCH_ITERS=1
    SPEC_DRAFT_ITERS=1
    SPEC_REFINE_ITERS=${SPEC_REFINE_ITERS:-3}
    SPEC_REVIEW_ITERS=${SPEC_REVIEW_ITERS:-1}
    SPEC_REVIEWFIX_ITERS=${SPEC_REVIEWFIX_ITERS:-1}
elif [ "$MODE" = "insights" ]; then
    # Insights mode: run analysis on existing iteration logs
    MAX_ITERATIONS=1
    VERBOSE=true
    INSIGHTS_ENABLED=true
elif [ "$MODE" = "full" ]; then
    # Full mode: cycles of plan → build → review → completion check
    MAX_ITERATIONS=${MAX_ITERATIONS:-100}
    FULL_PLAN_ITERS=${FULL_PLAN_ITERS:-5}
    FULL_BUILD_ITERS=${FULL_BUILD_ITERS:-10}
    FULL_REVIEW_ITERS=${FULL_REVIEW_ITERS:-25}  # More iterations to cover all review items including antagonist
    FULL_REVIEWFIX_ITERS=${FULL_REVIEWFIX_ITERS:-5}  # Review-fix iterations per cycle
    FULL_DISTILL_ITERS=${FULL_DISTILL_ITERS:-1}  # Distill iterations per cycle
else
    MODE="build"
    PROMPT_FILE="$(resolve_prompt build.md)"
    MAX_ITERATIONS=${MAX_ITERATIONS:-10}
fi

ITERATION=0

# Set up branch based on spec name
TARGET_BRANCH="ralph/$SPEC_NAME"
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]; then
    echo "Current branch '$CURRENT_BRANCH' does not match target '$TARGET_BRANCH'"

    # Check if target branch exists locally
    if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
        echo "Switching to existing branch: $TARGET_BRANCH"
        git checkout "$TARGET_BRANCH"
    else
        # Check if it exists on remote
        if git ls-remote --exit-code --heads origin "$TARGET_BRANCH" >/dev/null 2>&1; then
            echo "Checking out remote branch: $TARGET_BRANCH"
            git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH"
        else
            echo "Creating new branch: $TARGET_BRANCH"
            git checkout -b "$TARGET_BRANCH"
        fi
    fi

    CURRENT_BRANCH=$(git branch --show-current)
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Spec:    $SPEC_NAME"
echo "Mode:    $MODE"
if [ "$MODE" = "spec" ]; then
    echo "Phases:  research($SPEC_RESEARCH_ITERS) → draft($SPEC_DRAFT_ITERS) → refine($SPEC_REFINE_ITERS) → review($SPEC_REVIEW_ITERS) → fix($SPEC_REVIEWFIX_ITERS) → signoff"
elif [ "$MODE" = "decompose" ]; then
    echo "Action:  Decompose spec into sub-specs"
elif [ "$MODE" = "full" ]; then
    echo "Cycle:   plan($FULL_PLAN_ITERS) → build($FULL_BUILD_ITERS) → review($FULL_REVIEW_ITERS) → fix($FULL_REVIEWFIX_ITERS) → distill($FULL_DISTILL_ITERS) → check"
    [ $MAX_ITERATIONS -gt 0 ] && echo "Max:     $MAX_ITERATIONS cycles"
elif [ "$MODE" = "insights" ]; then
    echo "Action:  Analyze iteration logs"
elif [ "$MODE" = "debug" ]; then
    echo "⚠️  DEBUG MODE - No commits will be made"
else
    [ -n "$SETUP_PROMPT_FILE" ] && echo "Setup:   $SETUP_PROMPT_FILE"
    echo "Prompt:  $PROMPT_FILE"
    [ $MAX_ITERATIONS -gt 0 ] && echo "Max:     $MAX_ITERATIONS iterations"
fi
echo "Branch:  $CURRENT_BRANCH"
echo "Verbose: $VERBOSE"
[ "$INSIGHTS_ENABLED" = "true" ] && echo "Insights: enabled$([ "$INSIGHTS_GITHUB" = "true" ] && echo " (+ GitHub issues)")"
echo "Circuit Breaker: $MAX_CONSECUTIVE_FAILURES consecutive failures"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify prompt file(s) exist
if [ "$MODE" = "spec" ]; then
    # Spec mode uses its own set of prompt files
    for pf in "$(resolve_prompt spec/research.md)" "$(resolve_prompt spec/draft.md)" "$(resolve_prompt spec/refine.md)" "$(resolve_prompt spec/review.md)" "$(resolve_prompt spec/review_fix.md)" "$(resolve_prompt spec/signoff.md)"; do
        if [ ! -f "$pf" ]; then
            echo "Error: $pf not found (required for spec mode)"
            exit 1
        fi
    done
    # Verify spec_seed.md exists
    if [ ! -f "./.ralph/spec_seed.md" ]; then
        echo "Error: .ralph/spec_seed.md not found. Run the spec wizard first (ralph spec <name>)"
        exit 1
    fi
elif [ "$MODE" = "insights" ]; then
    # Insights mode uses the insights prompt
    if [ ! -f "$(resolve_prompt insights.md)" ]; then
        echo "Error: insights.md not found (required for insights mode)"
        exit 1
    fi
elif [ "$MODE" = "full" ]; then
    # Full mode uses multiple prompt files
    for pf in "$(resolve_prompt plan.md)" "$(resolve_prompt build.md)" "$(resolve_prompt review/setup.md)" "$(resolve_prompt distill.md)" "$(resolve_prompt completion_check.md)"; do
        if [ ! -f "$pf" ]; then
            echo "Error: $pf not found (required for full mode)"
            exit 1
        fi
    done
    # Check decomposition-specific prompts if manifest exists
    if [ -f "./.ralph/specs/${SPEC_NAME}/manifest.json" ]; then
        for pf in "$(resolve_prompt spec_select.md)" "$(resolve_prompt master_completion_check.md)"; do
            if [ ! -f "$pf" ]; then
                echo "Error: $pf not found (required for decomposed full mode)"
                exit 1
            fi
        done
    fi
    # Check for at least one review prompt (specialist or generic)
    if [ ! -f "$(resolve_prompt review/qa.md)" ] && [ ! -f "$(resolve_prompt review/general.md)" ]; then
        echo "Error: No review prompt found (need review/qa.md or review/general.md)"
        exit 1
    fi
    # Show which specialist prompts are available
    echo ""
    echo "Review specialists available:"
    [ -f "$(resolve_prompt review/ux.md)" ] && echo -e "  \033[1;35m✓\033[0m UX Expert (review/ux.md)"
    [ -f "$(resolve_prompt review/db.md)" ] && echo -e "  \033[1;36m✓\033[0m DB Expert (review/db.md)"
    [ -f "$(resolve_prompt review/qa.md)" ] && echo -e "  \033[1;33m✓\033[0m QA Expert (review/qa.md)"
    [ -f "$(resolve_prompt review/security.md)" ] && echo -e "  \033[1;31m✓\033[0m Security Expert (review/security.md)"
    [ -f "$(resolve_prompt review/perf.md)" ] && echo -e "  \033[1;32m✓\033[0m Performance Expert (review/perf.md)"
    [ -f "$(resolve_prompt review/api.md)" ] && echo -e "  \033[1;34m✓\033[0m API Expert (review/api.md)"
    [ -f "$(resolve_prompt review/antagonist.md)" ] && echo -e "  \033[0;91m✓\033[0m Antagonist (review/antagonist.md)"
    [ -f "$(resolve_prompt review/general.md)" ] && echo -e "  \033[1;37m✓\033[0m General (review/general.md - fallback)"
    echo ""
else
    if [ ! -f "$PROMPT_FILE" ]; then
        echo "Error: $PROMPT_FILE not found"
        exit 1
    fi

    if [ -n "$SETUP_PROMPT_FILE" ] && [ ! -f "$SETUP_PROMPT_FILE" ]; then
        echo "Error: $SETUP_PROMPT_FILE not found"
        exit 1
    fi
fi

# Verify Claude CLI authentication before starting
echo ""
echo "Verifying Claude CLI authentication..."
if ! claude -p --output-format json <<< "Reply with only the word 'ok'" > /dev/null 2>&1; then
    echo ""
    echo -e "\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;31m  ERROR: Claude CLI authentication failed\033[0m"
    echo -e "\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    echo "  Possible causes:"
    echo "    • AWS_BEARER_TOKEN_BEDROCK is missing or expired"
    echo "    • Network connectivity issues"
    echo ""
    echo "  Check your .ralph/.env file and try again."
    echo ""
    exit 1
fi
echo -e "\033[1;32m✓ Claude CLI authenticated successfully\033[0m"
echo ""

# Create temp directory for output logs
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Record start time for total elapsed tracking
LOOP_START_TIME=$(date +%s)

# ═══════════════════════════════════════════════════════════════════════════════
# CHECKPOINTING FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

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
3. Check `.ralph/implementation_plan.md` for [BLOCKED] items
4. Fix the issue manually or update AGENTS.md with guidance
5. Delete this file and restart Ralph

## Resume Command

\`\`\`bash
rm .ralph/paused.md
ralph $MODE $SPEC_NAME
\`\`\`
EOF
    git add .ralph/paused.md
    git commit -m "Ralph paused: $reason"
    git push origin "$CURRENT_BRANCH" 2>/dev/null || true
}

# Initialize session
SESSION_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TOTAL_ITERATIONS=0
ERROR_COUNT=0

# Check for existing checkpoint
if load_state; then
    echo -e "\033[1;36mℹ️  Previous session state found. Continuing from checkpoint.\033[0m"
    echo ""
fi

# Run setup prompt if defined (for review mode)
if [ -n "$SETUP_PROMPT_FILE" ]; then
    echo ""
    echo -e "\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;35m  SETUP PHASE: Running $SETUP_PROMPT_FILE\033[0m"
    echo -e "\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    
    SETUP_LOG_FILE="$TEMP_DIR/setup.log"
    
    if [ "$VERBOSE" = true ]; then
        cat "$SETUP_PROMPT_FILE" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose 2>&1 | tee "$SETUP_LOG_FILE"
    else
        echo -e "  \033[1;36m⏳\033[0m Running setup phase..."
        echo ""
        
        cat "$SETUP_PROMPT_FILE" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose > "$SETUP_LOG_FILE" 2>&1 &
        
        SETUP_PID=$!
        spin $SETUP_PID
        wait $SETUP_PID
        SETUP_EXIT=$?
        
        if [ $SETUP_EXIT -ne 0 ]; then
            echo -e "  \033[1;31m✗\033[0m Setup phase failed with code $SETUP_EXIT"
            echo "  Check log: $SETUP_LOG_FILE"
            exit 1
        else
            echo -e "  \033[1;32m✓\033[0m Setup phase completed"
        fi
    fi
    
    # Push setup changes
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }
    
    echo ""
    echo -e "\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;35m  SETUP COMPLETE - Starting review loop\033[0m"
    echo -e "\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
fi

# ASCII art digits for turn display
print_turn_banner() {
    local num=$1
    
    # Define each digit as an array of lines (8 lines tall)
    local d0=(
        "  ██████  "
        " ██    ██ "
        " ██    ██ "
        " ██    ██ "
        " ██    ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d1=(
        "    ██    "
        "   ███    "
        "    ██    "
        "    ██    "
        "    ██    "
        "    ██    "
        "  ██████  "
        "          "
    )
    local d2=(
        "  ██████  "
        " ██    ██ "
        "       ██ "
        "   █████  "
        "  ██      "
        " ██       "
        " ████████ "
        "          "
    )
    local d3=(
        "  ██████  "
        " ██    ██ "
        "       ██ "
        "   █████  "
        "       ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d4=(
        " ██    ██ "
        " ██    ██ "
        " ██    ██ "
        " ████████ "
        "       ██ "
        "       ██ "
        "       ██ "
        "          "
    )
    local d5=(
        " ████████ "
        " ██       "
        " ██       "
        " ███████  "
        "       ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d6=(
        "  ██████  "
        " ██       "
        " ██       "
        " ███████  "
        " ██    ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d7=(
        " ████████ "
        "       ██ "
        "      ██  "
        "     ██   "
        "    ██    "
        "    ██    "
        "    ██    "
        "          "
    )
    local d8=(
        "  ██████  "
        " ██    ██ "
        " ██    ██ "
        "  ██████  "
        " ██    ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d9=(
        "  ██████  "
        " ██    ██ "
        " ██    ██ "
        "  ███████ "
        "       ██ "
        "       ██ "
        "  ██████  "
        "          "
    )

    # TURN text (8 lines tall)
    local turn=(
        " ████████ ██    ██ ██████  ███    ██ "
        "    ██    ██    ██ ██   ██ ████   ██ "
        "    ██    ██    ██ ██   ██ ██ ██  ██ "
        "    ██    ██    ██ ██████  ██  ██ ██ "
        "    ██    ██    ██ ██   ██ ██   ████ "
        "    ██    ██    ██ ██   ██ ██    ███ "
        "    ██     ██████  ██   ██ ██     ██ "
        "                                     "
    )

    # Colon (8 lines tall)
    local colon=(
        "    "
        " ██ "
        " ██ "
        "    "
        " ██ "
        " ██ "
        "    "
        "    "
    )

    # Get digits of the number
    local digits=()
    local temp_num=$num
    if [ $temp_num -eq 0 ]; then
        digits=(0)
    else
        while [ $temp_num -gt 0 ]; do
            digits=($((temp_num % 10)) "${digits[@]}")
            temp_num=$((temp_num / 10))
        done
    fi

    echo ""
    echo ""
    echo -e "\033[1;33m" # Bold yellow

    # Print each line
    for line in 0 1 2 3 4 5 6 7; do
        local output="${turn[$line]}${colon[$line]}"
        
        # Add each digit
        for digit in "${digits[@]}"; do
            case $digit in
                0) output+="${d0[$line]}" ;;
                1) output+="${d1[$line]}" ;;
                2) output+="${d2[$line]}" ;;
                3) output+="${d3[$line]}" ;;
                4) output+="${d4[$line]}" ;;
                5) output+="${d5[$line]}" ;;
                6) output+="${d6[$line]}" ;;
                7) output+="${d7[$line]}" ;;
                8) output+="${d8[$line]}" ;;
                9) output+="${d9[$line]}" ;;
            esac
        done
        
        echo "    $output"
    done

    echo -e "\033[0m" # Reset color
    echo ""
    echo ""
}

# Function to print a spinner while waiting
spin() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while ps -p $pid > /dev/null 2>&1; do
        for i in $(seq 0 9); do
            printf "\r  \033[1;36m${spinstr:$i:1}\033[0m Working... "
            sleep $delay
        done
    done
    printf "\r                      \r"
}

# Function to format seconds into human-readable time
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# Function to generate iteration summary
generate_summary() {
    local log_file=$1
    local iteration=$2
    local turn_start=$3
    
    # Calculate timing
    local now=$(date +%s)
    local turn_duration=$((now - turn_start))
    local total_elapsed=$((now - LOOP_START_TIME))
    local turn_formatted=$(format_duration $turn_duration)
    local total_formatted=$(format_duration $total_elapsed)
    
    echo ""
    echo -e "\033[1;36m┌────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;36m│  TURN $iteration SUMMARY                                            │\033[0m"
    echo -e "\033[1;36m└────────────────────────────────────────────────────────────┘\033[0m"
    echo ""
    
    echo -e "  \033[1;35m⏱\033[0m  Turn duration:  $turn_formatted"
    echo -e "  \033[1;35m⏱\033[0m  Total elapsed:  $total_formatted"
    echo ""
    
    # Extract key information from the JSON log
    # Look for file changes, commits, and key actions
    
    # Count files modified (look for write/edit operations)
    local files_changed=$(grep -o '"tool":"write"\|"tool":"str_replace_editor"\|"tool":"create"\|"tool":"edit"' "$log_file" 2>/dev/null | wc -l)
    
    # Look for git commits
    local commits=$(grep -o 'git commit' "$log_file" 2>/dev/null | wc -l)
    
    # Look for test runs
    local tests=$(grep -o 'npm test\|npm run test\|npx nx test\|jest\|vitest' "$log_file" 2>/dev/null | wc -l)
    
    # Get the last assistant message as a summary (simplified extraction)
    local last_message=$(grep -o '"type":"assistant"[^}]*"text":"[^"]*"' "$log_file" 2>/dev/null | tail -1 | sed 's/.*"text":"\([^"]*\)".*/\1/' | head -c 500)
    
    echo -e "  \033[1;32m✓\033[0m Files touched: ~$files_changed"
    echo -e "  \033[1;32m✓\033[0m Git commits: $commits"
    echo -e "  \033[1;32m✓\033[0m Test runs: $tests"
    echo ""
    
    # Show recent git log if there were commits
    if [ $commits -gt 0 ]; then
        echo -e "  \033[1;33mRecent commits:\033[0m"
        git log --oneline -3 2>/dev/null | sed 's/^/    /'
        echo ""
    fi
    
    # Show changed files from git status
    local changed_files=$(git diff --name-only HEAD~1 2>/dev/null | head -10)
    if [ -n "$changed_files" ]; then
        echo -e "  \033[1;33mChanged files:\033[0m"
        echo "$changed_files" | sed 's/^/    /'
        echo ""
    fi
    
    echo -e "\033[1;36m────────────────────────────────────────────────────────────\033[0m"
    echo ""
}

# Capture structured iteration summary as JSON (for insights)
capture_iteration_summary() {
    if [ "$INSIGHTS_ENABLED" != "true" ]; then
        return 0
    fi

    local log_file=$1
    local iteration_num=$2
    local phase_display=$3  # e.g. "BUILD (3/10)" or "review"
    local exit_code=$4
    local turn_start=$5
    local start_sha=${6:-""}

    local now=$(date +%s)
    local duration=$((now - turn_start))
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Extract the phase name from the display string (e.g. "BUILD (3/10)" -> "BUILD", "REVIEW-QA (5/25)" -> "REVIEW-QA")
    local phase_name=$(echo "$phase_display" | sed 's/ (.*//' | tr '[:lower:]' '[:upper:]')

    # Use git to get accurate metrics based on start SHA
    local files_changed=0
    local commits=0
    local modified_files=""
    if [ -n "$start_sha" ]; then
        files_changed=$(git diff --name-only "$start_sha" HEAD 2>/dev/null | wc -l | tr -d ' ')
        commits=$(git log --oneline "$start_sha"..HEAD 2>/dev/null | wc -l | tr -d ' ')
        modified_files=$(git diff --name-only "$start_sha" HEAD 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
    else
        # Fallback: estimate from recent commits
        files_changed=$(git diff --name-only HEAD~1 2>/dev/null | wc -l | tr -d ' ')
        commits=$(git log --oneline -1 2>/dev/null | wc -l | tr -d ' ')
        modified_files=$(git diff --name-only HEAD~1 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
    fi

    # Count test invocations from the log (best-effort — counts command runs, not individual tests)
    local tests=$(grep -o 'npm test\|npm run test\|npx nx test\|jest\|vitest' "$log_file" 2>/dev/null | wc -l | tr -d ' ')

    # Extract token usage and cost from the stream-json result line
    local result_line=$(grep '"type":"result"' "$log_file" 2>/dev/null | tail -1)
    local input_tokens=0
    local output_tokens=0
    local cost_usd=0
    if [ -n "$result_line" ]; then
        input_tokens=$(echo "$result_line" | sed -n 's/.*"input_tokens":\([0-9]*\).*/\1/p')
        output_tokens=$(echo "$result_line" | sed -n 's/.*"output_tokens":\([0-9]*\).*/\1/p')
        cost_usd=$(echo "$result_line" | sed -n 's/.*"total_cost_usd":\([0-9.]*\).*/\1/p')
        input_tokens=${input_tokens:-0}
        output_tokens=${output_tokens:-0}
        cost_usd=${cost_usd:-0}
    fi

    # Recent commits (for human context)
    local recent_commits=$(git log --oneline -3 2>/dev/null | tr '\n' '|' | sed 's/|$//')

    # Extract error snippet if exit code was non-zero
    local error_snippet=""
    if [ "$exit_code" -ne 0 ]; then
        error_snippet=$(tail -5 "$log_file" 2>/dev/null | tr '\n' ' ' | head -c 200)
        error_snippet=$(echo "$error_snippet" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
    fi

    local branch=$(git branch --show-current 2>/dev/null)

    # Escape JSON special characters in dynamic fields
    modified_files=$(echo "$modified_files" | sed 's/\\/\\\\/g; s/"/\\"/g')
    recent_commits=$(echo "$recent_commits" | sed 's/\\/\\\\/g; s/"/\\"/g')

    local output_file="$INSIGHTS_LOGS_DIR/${SPEC_NAME}_iter_${iteration_num}.json"

    cat > "$output_file" << INSIGHTS_EOF
{
  "timestamp": "$timestamp",
  "spec_name": "$SPEC_NAME",
  "mode": "$MODE",
  "phase_name": "$phase_name",
  "phase": "$phase_display",
  "iteration": $iteration_num,
  "exit_code": $exit_code,
  "duration_seconds": $duration,
  "files_modified_count": $files_changed,
  "git_commits": $commits,
  "test_commands_run": $tests,
  "input_tokens": $input_tokens,
  "output_tokens": $output_tokens,
  "cost_usd": $cost_usd,
  "modified_files": "$modified_files",
  "recent_commits": "$recent_commits",
  "error_snippet": "$error_snippet",
  "start_sha": "$start_sha",
  "branch": "$branch"
}
INSIGHTS_EOF
}

# Run insights analysis (called at phase boundaries)
run_insights_analysis() {
    if [ "$INSIGHTS_ENABLED" != "true" ]; then
        return 0
    fi

    local phase_name=${1:-""}

    # Guard: skip if no iteration logs exist
    local log_count=$(ls -1 "$INSIGHTS_LOGS_DIR"/*.json 2>/dev/null | wc -l)
    if [ "$log_count" -eq 0 ]; then
        echo -e "  \033[1;34mℹ\033[0m  Insights: no iteration logs to analyze"
        return 0
    fi

    echo ""
    echo -e "\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;35m  📊 INSIGHTS ANALYSIS${phase_name:+ (after $phase_name phase)}\033[0m"
    echo -e "\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    local insights_log="$TEMP_DIR/insights_analysis.log"

    if [ "$VERBOSE" = true ]; then
        cat "$(resolve_prompt insights.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose 2>&1 | tee "$insights_log"
    else
        echo -e "  \033[1;36m⏳\033[0m Running insights analysis on $log_count iteration logs..."

        cat "$(resolve_prompt insights.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose > "$insights_log" 2>&1 &

        local INSIGHTS_PID=$!
        spin $INSIGHTS_PID
        wait $INSIGHTS_PID
        local INSIGHTS_EXIT=$?

        if [ $INSIGHTS_EXIT -ne 0 ]; then
            echo -e "  \033[1;33m⚠\033[0m Insights analysis failed (non-fatal, continuing)"
            return 0
        fi
    fi

    echo -e "  \033[1;32m✓\033[0m Insights analysis complete"

    # Commit insights artifacts
    if [ -f "$INSIGHTS_DIR/insights.md" ]; then
        git add "$INSIGHTS_DIR/" 2>/dev/null || true
        git commit -m "ralph: update insights analysis${phase_name:+ (after $phase_name)}" 2>/dev/null || true
        git push origin "$CURRENT_BRANCH" 2>/dev/null || true
    fi

    # Optionally create GitHub issues
    if [ "$INSIGHTS_GITHUB" = "true" ]; then
        run_insights_github_issues
    fi

    return 0
}

# Create GitHub issues for HIGH/CRITICAL findings
run_insights_github_issues() {
    # Guard: need GIT_TOKEN
    if [ -z "${GIT_TOKEN:-}" ]; then
        echo -e "  \033[1;33m⚠\033[0m Insights GitHub: GIT_TOKEN not set, skipping issue creation"
        return 0
    fi

    # Guard: need a github.com remote
    local remote_url=$(git remote get-url origin 2>/dev/null)
    if ! echo "$remote_url" | grep -q 'github.com'; then
        echo -e "  \033[1;33m⚠\033[0m Insights GitHub: not a GitHub remote, skipping issue creation"
        return 0
    fi

    # Guard: need insights.md to exist
    if [ ! -f "$INSIGHTS_DIR/insights.md" ]; then
        echo -e "  \033[1;33m⚠\033[0m Insights GitHub: no insights.md found, skipping"
        return 0
    fi

    # Extract owner/repo from remote URL
    local owner_repo=$(echo "$remote_url" | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$|\1|')

    echo -e "  \033[1;36m⏳\033[0m Generating GitHub issues for critical findings..."

    local issues_log="$TEMP_DIR/insights_github.log"
    local issues_result

    issues_result=$(cat "$(resolve_prompt insights_github.md)" | claude -p \
        --dangerously-skip-permissions \
        --output-format=json 2>"$issues_log")

    # Parse Claude's JSON response
    local json_text
    json_text=$(echo "$issues_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$issues_result"
    fi
    # Strip markdown code fences
    json_text=$(echo "$json_text" | sed '/^```/d')

    # Extract issues array
    local issue_count=$(echo "$json_text" | jq -r '.issues | length' 2>/dev/null)

    if [ -z "$issue_count" ] || [ "$issue_count" = "0" ] || [ "$issue_count" = "null" ]; then
        echo -e "  \033[1;32m✓\033[0m No HIGH/CRITICAL findings to report"
        return 0
    fi

    echo -e "  \033[1;34mℹ\033[0m  Creating $issue_count GitHub issue(s)..."

    local i=0
    while [ $i -lt $issue_count ]; do
        local title=$(echo "$json_text" | jq -r ".issues[$i].title" 2>/dev/null)
        local body=$(echo "$json_text" | jq -r ".issues[$i].body" 2>/dev/null)
        local severity=$(echo "$json_text" | jq -r ".issues[$i].severity" 2>/dev/null)

        # Create label list
        local labels="ralph-insight,$severity"

        # Create issue via GitHub API
        local response
        response=$(curl -s -w "\n%{http_code}" -X POST \
            "https://api.github.com/repos/$owner_repo/issues" \
            -H "Authorization: token $GIT_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "$(jq -n --arg title "$title" --arg body "$body" --argjson labels "[\"ralph-insight\", \"$severity\"]" \
                '{title: $title, body: $body, labels: $labels}')")

        local http_code=$(echo "$response" | tail -1)
        local response_body=$(echo "$response" | head -n -1)

        if [ "$http_code" = "201" ]; then
            local issue_url=$(echo "$response_body" | jq -r '.html_url' 2>/dev/null)
            echo -e "  \033[1;32m✓\033[0m Created: $issue_url"
        else
            echo -e "  \033[1;31m✗\033[0m Failed to create issue: HTTP $http_code"
        fi

        i=$((i + 1))
    done

    return 0
}

# Helper function to run a single iteration with a given prompt
run_single_iteration() {
    local prompt_file=$1
    local iteration_num=$2
    local phase_name=$3

    TURN_START_TIME=$(date +%s)
    TURN_START_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
    
    # Display turn banner
    print_turn_banner $iteration_num
    echo -e "  \033[1;35mPhase:\033[0m $phase_name"
    echo ""
    
    # Save checkpoint
    save_state "$phase_name" "$iteration_num" "Starting iteration"
    
    # Prepare log file for this iteration
    LOG_FILE="$TEMP_DIR/iteration_${iteration_num}.log"
    
    if [ "$VERBOSE" = true ]; then
        cat "$prompt_file" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose 2>&1 | tee "$LOG_FILE"
        CLAUDE_EXIT=${PIPESTATUS[1]}
        
        if [ $CLAUDE_EXIT -ne 0 ]; then
            echo -e "  \033[1;31m✗\033[0m Claude exited with code $CLAUDE_EXIT"
            echo "  Check log: $LOG_FILE"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            ERROR_COUNT=$((ERROR_COUNT + 1))
            return 1
        fi
    else
        echo -e "  \033[1;36m⏳\033[0m Running Claude iteration $iteration_num..."
        echo ""
        
        cat "$prompt_file" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose > "$LOG_FILE" 2>&1 &
        
        CLAUDE_PID=$!
        spin $CLAUDE_PID
        wait $CLAUDE_PID
        CLAUDE_EXIT=$?
        
        if [ $CLAUDE_EXIT -ne 0 ]; then
            echo -e "  \033[1;31m✗\033[0m Claude exited with code $CLAUDE_EXIT"
            echo "  Check log: $LOG_FILE"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            ERROR_COUNT=$((ERROR_COUNT + 1))
            return 1
        else
            echo -e "  \033[1;32m✓\033[0m Claude iteration completed"
            CONSECUTIVE_FAILURES=0  # Reset on success
        fi
    fi
    
    # Generate and display summary
    generate_summary "$LOG_FILE" "$iteration_num" "$TURN_START_TIME"

    # Capture iteration summary for insights
    capture_iteration_summary "$LOG_FILE" "$iteration_num" "$phase_name" "$CLAUDE_EXIT" "$TURN_START_TIME" "$TURN_START_SHA"

    # Skip commit/push in debug mode
    if [ "${NO_COMMIT:-false}" = true ]; then
        echo -e "  \033[1;33m⚠️  DEBUG MODE - Skipping commit and push\033[0m"
        return 0
    fi

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }

    # Update checkpoint after successful iteration
    save_state "$phase_name" "$iteration_num" "Completed successfully"

    return 0
}

# Helper function to determine which review specialist to use
# Returns: ux, db, qa, security, perf, api, or antagonist
get_next_review_specialist() {
    local checklist_file="./.ralph/review_checklist.md"

    if [ ! -f "$checklist_file" ]; then
        echo "qa"
        return
    fi

    # Find the first unchecked item and check its tag
    local next_item=$(grep -m1 '^\- \[ \]' "$checklist_file" 2>/dev/null || echo "")

    if echo "$next_item" | grep -qi '\[SEC'; then
        echo "security"
    elif echo "$next_item" | grep -qi '\[UX\]'; then
        echo "ux"
    elif echo "$next_item" | grep -qi '\[DB\]'; then
        echo "db"
    elif echo "$next_item" | grep -qi '\[PERF\]'; then
        echo "perf"
    elif echo "$next_item" | grep -qi '\[API\]'; then
        echo "api"
    elif echo "$next_item" | grep -qi '\[ANTAG'; then
        echo "antagonist"
    else
        echo "qa"
    fi
}

# Helper function to get ALL remaining distinct specialist types
# Returns space-separated list of specialist types with unchecked items
get_all_remaining_specialists() {
    local checklist_file="./.ralph/review_checklist.md"
    local specialists=""

    if [ ! -f "$checklist_file" ]; then
        echo "qa"
        return
    fi

    # Check each specialist type for unchecked items
    if grep -q '^\- \[ \].*\[SEC' "$checklist_file" 2>/dev/null; then
        specialists="$specialists security"
    fi
    if grep -q '^\- \[ \].*\[UX\]' "$checklist_file" 2>/dev/null; then
        specialists="$specialists ux"
    fi
    if grep -q '^\- \[ \].*\[DB\]' "$checklist_file" 2>/dev/null; then
        specialists="$specialists db"
    fi
    if grep -q '^\- \[ \].*\[PERF\]' "$checklist_file" 2>/dev/null; then
        specialists="$specialists perf"
    fi
    if grep -q '^\- \[ \].*\[API\]' "$checklist_file" 2>/dev/null; then
        specialists="$specialists api"
    fi
    if grep -q '^\- \[ \].*\[ANTAG' "$checklist_file" 2>/dev/null; then
        specialists="$specialists antagonist"
    fi
    # QA covers untagged items — check for unchecked items that don't match any known tag
    local total_unchecked=$(grep -c '^\- \[ \]' "$checklist_file" 2>/dev/null) || total_unchecked=0
    local tagged_unchecked=0
    tagged_unchecked=$((tagged_unchecked + $(grep -c '^\- \[ \].*\[SEC' "$checklist_file" 2>/dev/null || echo 0)))
    tagged_unchecked=$((tagged_unchecked + $(grep -c '^\- \[ \].*\[UX\]' "$checklist_file" 2>/dev/null || echo 0)))
    tagged_unchecked=$((tagged_unchecked + $(grep -c '^\- \[ \].*\[DB\]' "$checklist_file" 2>/dev/null || echo 0)))
    tagged_unchecked=$((tagged_unchecked + $(grep -c '^\- \[ \].*\[PERF\]' "$checklist_file" 2>/dev/null || echo 0)))
    tagged_unchecked=$((tagged_unchecked + $(grep -c '^\- \[ \].*\[API\]' "$checklist_file" 2>/dev/null || echo 0)))
    tagged_unchecked=$((tagged_unchecked + $(grep -c '^\- \[ \].*\[ANTAG' "$checklist_file" 2>/dev/null || echo 0)))
    if [ $((total_unchecked - tagged_unchecked)) -gt 0 ]; then
        specialists="$specialists qa"
    fi

    # Trim leading space
    echo "$specialists" | sed 's/^ *//'
}

# Merge parallel review outputs back into main files
merge_parallel_reviews() {
    local parallel_dir="./.ralph/parallel_reviews"
    local review_file="./.ralph/review.md"
    local checklist_file="./.ralph/review_checklist.md"

    if [ ! -d "$parallel_dir" ]; then
        echo -e "  \033[1;33m⚠\033[0m  No parallel review output directory found"
        return 1
    fi

    # Merge review findings: append each specialist's review to the main review.md
    local merged_count=0
    for review_output in "$parallel_dir"/review_*.md; do
        [ -f "$review_output" ] || continue
        local specialist_name=$(basename "$review_output" .md | sed 's/^review_//')
        echo "" >> "$review_file"
        echo "<!-- Parallel review: $specialist_name -->" >> "$review_file"
        cat "$review_output" >> "$review_file"
        merged_count=$((merged_count + 1))
        echo -e "  \033[1;32m✓\033[0m Merged findings from $specialist_name"
    done

    # Merge checked items: match against checklist and mark complete
    for checked_output in "$parallel_dir"/checked_*.md; do
        [ -f "$checked_output" ] || continue
        local specialist_name=$(basename "$checked_output" .md | sed 's/^checked_//')
        local items_checked=0

        while IFS= read -r line; do
            # Skip empty lines
            [ -z "$line" ] && continue
            # Extract the item text after "- [x] " prefix
            local item_text=$(echo "$line" | sed 's/^- \[x\] //')
            [ -z "$item_text" ] && continue

            # Escape special regex characters for sed matching
            local escaped_text=$(echo "$item_text" | sed 's/[[\.*^$()+?{|\\]/\\&/g')

            # Replace unchecked with checked in the checklist
            if grep -qF "$item_text" "$checklist_file" 2>/dev/null; then
                sed -i "s|^\- \[ \] ${escaped_text}|- [x] ${item_text}|" "$checklist_file" 2>/dev/null
                items_checked=$((items_checked + 1))
            fi
        done < "$checked_output"

        if [ $items_checked -gt 0 ]; then
            echo -e "  \033[1;32m✓\033[0m Marked $items_checked items complete from $specialist_name"
        fi
    done

    # Clean up parallel reviews directory
    rm -rf "$parallel_dir"

    if [ $merged_count -eq 0 ]; then
        echo -e "  \033[1;33m⚠\033[0m  No specialist outputs to merge"
        return 1
    fi

    return 0
}

# Run review specialists in parallel
# Returns 0 if any succeeded, 1 if all failed
run_parallel_review() {
    local parallel_max=${PARALLEL_REVIEW_MAX:-4}
    local parallel_dir="./.ralph/parallel_reviews"
    local wrapper_prompt="$(resolve_prompt review/parallel_wrapper.md)"

    # Get all remaining specialist types
    local specialists=$(get_all_remaining_specialists)

    if [ -z "$specialists" ]; then
        echo -e "  \033[1;32m✓\033[0m No remaining review items"
        return 0
    fi

    echo ""
    echo -e "\033[1;35m┌────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;35m│  PARALLEL REVIEW - Launching specialists simultaneously   │\033[0m"
    echo -e "\033[1;35m└────────────────────────────────────────────────────────────┘\033[0m"
    echo ""

    # Create output directory
    mkdir -p "$parallel_dir"

    # Build array of specialists (cap at parallel_max)
    local spec_array=()
    local count=0
    for spec_type in $specialists; do
        if [ $count -ge $parallel_max ]; then
            echo -e "  \033[1;33m⚠\033[0m  Capping at $parallel_max parallel specialists (remaining: $(echo $specialists | wc -w))"
            break
        fi
        spec_array+=("$spec_type")
        count=$((count + 1))
    done

    # Launch each specialist in parallel
    local pids=()
    local specialist_names=()
    local specialist_colors=()
    local PARALLEL_START_TIME=$(date +%s)

    for spec_type in "${spec_array[@]}"; do
        local specialist_prompt=""
        local specialist_color=""
        local specialist_label=""

        case $spec_type in
            security)
                specialist_prompt="$(resolve_prompt review/security.md)"
                specialist_label="Security"
                specialist_color="\033[1;31m"
                ;;
            ux)
                specialist_prompt="$(resolve_prompt review/ux.md)"
                specialist_label="UX"
                specialist_color="\033[1;35m"
                ;;
            db)
                specialist_prompt="$(resolve_prompt review/db.md)"
                specialist_label="DB"
                specialist_color="\033[1;36m"
                ;;
            perf)
                specialist_prompt="$(resolve_prompt review/perf.md)"
                specialist_label="Performance"
                specialist_color="\033[1;32m"
                ;;
            api)
                specialist_prompt="$(resolve_prompt review/api.md)"
                specialist_label="API"
                specialist_color="\033[1;34m"
                ;;
            antagonist)
                specialist_prompt="$(resolve_prompt review/antagonist.md)"
                specialist_label="Antagonist"
                specialist_color="\033[0;91m"
                ;;
            *)
                specialist_prompt="$(resolve_prompt review/qa.md)"
                specialist_label="QA"
                specialist_color="\033[1;33m"
                ;;
        esac

        # Fallback to general review if specialist prompt doesn't exist
        if [ ! -f "$specialist_prompt" ]; then
            specialist_prompt="$(resolve_prompt review/general.md)"
            specialist_label="General"
            specialist_color="\033[1;37m"
        fi

        # Check if wrapper exists — fall back to sequential if not
        if [ ! -f "$wrapper_prompt" ]; then
            echo -e "  \033[1;33m⚠\033[0m  Parallel wrapper prompt not found, falling back to sequential"
            return 2  # Signal caller to use sequential fallback
        fi

        # Create combined prompt: wrapper + specialist
        local temp_prompt="$TEMP_DIR/parallel_${spec_type}.md"
        # Replace SPECIALIST placeholder in wrapper with actual type name
        sed "s/SPECIALIST/${spec_type}/g" "$wrapper_prompt" > "$temp_prompt"
        cat "$specialist_prompt" >> "$temp_prompt"

        local log_file="$TEMP_DIR/parallel_${spec_type}.log"

        echo -e "  ${specialist_color}🚀 Launching: $specialist_label\033[0m"

        # Launch claude in background
        cat "$temp_prompt" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose > "$log_file" 2>&1 &

        pids+=($!)
        specialist_names+=("$specialist_label")
        specialist_colors+=("$specialist_color")
    done

    echo ""
    echo -e "  \033[1;36m⏳\033[0m Waiting for ${#pids[@]} specialists to complete..."
    echo ""

    # Wait for all processes with a multi-spinner display
    local all_done=false
    while ! $all_done; do
        all_done=true
        local status_line="  "
        for i in "${!pids[@]}"; do
            if ps -p ${pids[$i]} > /dev/null 2>&1; then
                all_done=false
                status_line="${status_line}${specialist_colors[$i]}⟳ ${specialist_names[$i]}\033[0m  "
            else
                status_line="${status_line}\033[1;32m✓ ${specialist_names[$i]}\033[0m  "
            fi
        done
        printf "\r${status_line}"
        if ! $all_done; then
            sleep 1
        fi
    done
    printf "\r                                                                              \r"

    # Collect exit codes
    local success_count=0
    local fail_count=0
    for i in "${!pids[@]}"; do
        wait ${pids[$i]}
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo -e "  \033[1;32m✓\033[0m ${specialist_names[$i]} completed successfully"
            success_count=$((success_count + 1))
        else
            echo -e "  \033[1;31m✗\033[0m ${specialist_names[$i]} failed (exit code $exit_code)"
            echo "    Log: $TEMP_DIR/parallel_${spec_array[$i]}.log"
            fail_count=$((fail_count + 1))
        fi
    done

    local PARALLEL_END_TIME=$(date +%s)
    local parallel_duration=$((PARALLEL_END_TIME - PARALLEL_START_TIME))
    echo ""
    echo -e "  \033[1;35m⏱\033[0m  Parallel review took $(format_duration $parallel_duration)"
    echo ""

    # Merge results
    if [ $success_count -gt 0 ]; then
        echo -e "  \033[1;36m📋 Merging results from $success_count specialists...\033[0m"
        merge_parallel_reviews

        # Single git commit + push for all merged results
        git add .ralph/review.md .ralph/review_checklist.md
        git commit -m "Parallel Review: $success_count specialists completed ($(echo ${specialist_names[@]} | tr ' ' ', '))"
        git push origin "$CURRENT_BRANCH" || git push -u origin "$CURRENT_BRANCH"

        echo -e "  \033[1;32m✓\033[0m Parallel review round complete ($success_count succeeded, $fail_count failed)"
        CONSECUTIVE_FAILURES=0
        return 0
    else
        echo -e "  \033[1;31m✗\033[0m All $fail_count specialists failed"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        ERROR_COUNT=$((ERROR_COUNT + 1))
        return 1
    fi
}

# Helper function to run completion check
run_completion_check() {
    echo ""
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;33m  🔍 COMPLETION CHECK - Is the spec fully implemented?\033[0m"
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    
    local check_log="$TEMP_DIR/completion_check.log"
    local check_result
    
    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "$(resolve_prompt completion_check.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Checking if implementation is complete..."
        
        check_result=$(cat "$(resolve_prompt completion_check.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi
    
    # Parse Claude's JSON response using jq
    # Claude with --output-format=json wraps the response in a result field
    # First try to extract from the result field, then try the raw response
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi
    # Strip markdown code fences if Claude wrapped the JSON in ```json ... ```
    json_text=$(echo "$json_text" | sed '/^```/d')

    # Extract fields with jq — handles multiline, nested quotes, and whitespace correctly
    local is_complete=$(echo "$json_text" | jq -r '.complete // false' 2>/dev/null)
    local confidence=$(echo "$json_text" | jq -r '.confidence // empty' 2>/dev/null)
    local reason=$(echo "$json_text" | jq -r '.reason // empty' 2>/dev/null)

    if [ "$is_complete" = "true" ]; then
        echo ""
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        echo -e "\033[1;32m  ✅ IMPLEMENTATION COMPLETE!\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;32m  Confidence: ${confidence}\033[0m"
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        [ -n "$reason" ] && echo -e "  \033[1;36m$reason\033[0m"
        echo ""
        return 0  # Complete
    else
        echo ""
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        echo -e "\033[1;33m  ⚠ Implementation not yet complete\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;33m  Confidence: ${confidence}\033[0m"
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        [ -n "$reason" ] && echo -e "  \033[1;36m$reason\033[0m"
        echo ""
        return 1  # Not complete
    fi
}

# Check if circuit breaker should trip
check_circuit_breaker() {
    if [ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
        echo ""
        echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
        echo -e "\033[1;31m  🔴 CIRCUIT BREAKER TRIPPED\033[0m"
        echo -e "\033[1;31m  $CONSECUTIVE_FAILURES consecutive failures detected\033[0m"
        echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
        echo ""
        echo -e "  \033[1;33mRalph has paused to prevent further issues.\033[0m"
        echo -e "  \033[1;33mHuman intervention required.\033[0m"
        echo ""
        
        create_paused_state "Circuit breaker tripped after $CONSECUTIVE_FAILURES consecutive failures"
        
        return 0  # Circuit breaker tripped
    fi
    return 1  # Circuit breaker not tripped
}

# Print cycle banner
print_cycle_banner() {
    local cycle_num=$1
    echo ""
    echo ""
    echo -e "\033[1;35m╔════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║                      CYCLE $cycle_num                              ║\033[0m"
    echo -e "\033[1;35m╠════════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;35m║  plan($FULL_PLAN_ITERS) → build($FULL_BUILD_ITERS) → review($FULL_REVIEW_ITERS) → fix($FULL_REVIEWFIX_ITERS) → distill($FULL_DISTILL_ITERS) → check  ║\033[0m"
    echo -e "\033[1;35m╚════════════════════════════════════════════════════════════╝\033[0m"
    echo ""
}

# Print phase banner
print_phase_banner() {
    local phase_name=$1
    local phase_iters=$2
    echo ""
    echo -e "\033[1;36m┌────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;36m│  $phase_name PHASE ($phase_iters iterations)                       \033[0m"
    echo -e "\033[1;36m└────────────────────────────────────────────────────────────┘\033[0m"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUB-SPEC DECOMPOSITION HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

# Check if a manifest.json exists for the current spec (decomposed spec)
check_manifest_exists() {
    local manifest_path="./.ralph/specs/${SPEC_NAME}/manifest.json"
    if [ -f "$manifest_path" ]; then
        return 0
    fi
    return 1
}

# Run spec_select.md prompt and parse the JSON result
# Returns: 0=selected, 1=all_complete, 2=blocked
run_spec_select() {
    echo ""
    echo -e "\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;35m  📋 SUB-SPEC SELECTION - Picking next sub-spec to work on\033[0m"
    echo -e "\033[1;35m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    local select_log="$TEMP_DIR/spec_select.log"
    local select_result

    if [ "$VERBOSE" = true ]; then
        select_result=$(cat "$(resolve_prompt spec_select.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$select_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Selecting next sub-spec..."

        select_result=$(cat "$(resolve_prompt spec_select.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$select_log")
    fi

    # Parse Claude's JSON response
    local json_text
    json_text=$(echo "$select_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$select_result"
    fi
    # Strip markdown code fences if Claude wrapped the JSON in ```json ... ```
    json_text=$(echo "$json_text" | sed '/^```/d')

    local action=$(echo "$json_text" | jq -r '.action // empty' 2>/dev/null)
    local sub_spec_name=$(echo "$json_text" | jq -r '.sub_spec_name // empty' 2>/dev/null)
    local sub_spec_title=$(echo "$json_text" | jq -r '.sub_spec_title // empty' 2>/dev/null)
    local progress_complete=$(echo "$json_text" | jq -r '.progress.complete // 0' 2>/dev/null)
    local progress_total=$(echo "$json_text" | jq -r '.progress.total // 0' 2>/dev/null)

    if [ "$action" = "select" ]; then
        echo ""
        echo -e "\033[1;32m  ✓ Selected: $sub_spec_name — $sub_spec_title\033[0m"
        echo -e "\033[1;36m  Progress: $progress_complete/$progress_total sub-specs complete\033[0m"
        echo ""
        CURRENT_SUBSPEC="$sub_spec_name"
        return 0  # Selected
    elif [ "$action" = "all_complete" ]; then
        echo ""
        echo -e "\033[1;32m  ✓ All sub-specs complete! ($progress_total/$progress_total)\033[0m"
        echo ""
        return 1  # All complete
    elif [ "$action" = "blocked" ]; then
        local reason=$(echo "$json_text" | jq -r '.reason // "Unknown"' 2>/dev/null)
        echo ""
        echo -e "\033[1;31m  ✗ Blocked: $reason\033[0m"
        echo ""
        return 2  # Blocked
    else
        echo ""
        echo -e "\033[1;31m  ✗ Unexpected spec_select response: $action\033[0m"
        echo -e "\033[1;31m  Raw result: $json_text\033[0m"
        echo ""
        return 2  # Treat as blocked
    fi
}

# Mark current sub-spec as complete in manifest.json
mark_subspec_complete() {
    local manifest_path="./.ralph/specs/${SPEC_NAME}/manifest.json"

    if [ ! -f "$manifest_path" ]; then
        echo -e "\033[1;31m  ✗ Manifest not found: $manifest_path\033[0m"
        return 1
    fi

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local subspec_name="${CURRENT_SUBSPEC}"

    # Use jq to update the manifest
    local updated
    updated=$(jq --arg name "$subspec_name" --arg now "$now" '
        .updated_at = $now |
        (.sub_specs |= map(
            if .name == $name then
                .status = "complete" | .completed_at = $now
            else . end
        )) |
        .progress.complete = ([.sub_specs[] | select(.status == "complete")] | length) |
        .progress.in_progress = ([.sub_specs[] | select(.status == "in_progress")] | length) |
        .progress.pending = ([.sub_specs[] | select(.status == "pending")] | length)
    ' "$manifest_path" 2>/dev/null)
    local jq_exit=$?

    if [ $jq_exit -eq 0 ] && [ -n "$updated" ]; then
        echo "$updated" > "$manifest_path"
        echo -e "\033[1;32m  ✓ Marked $subspec_name as complete\033[0m"

        git add "$manifest_path"
        git commit -m "Complete sub-spec: $subspec_name"
        git push origin "$CURRENT_BRANCH" 2>/dev/null || true
    else
        echo -e "\033[1;31m  ✗ Failed to update manifest\033[0m"
        return 1
    fi
}

# Run master completion check for decomposed specs
run_master_completion_check() {
    echo ""
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;33m  🔍 MASTER COMPLETION CHECK - Verifying all sub-specs cover the full spec\033[0m"
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    local check_log="$TEMP_DIR/master_completion_check.log"
    local check_result

    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "$(resolve_prompt master_completion_check.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Running master completion check..."

        check_result=$(cat "$(resolve_prompt master_completion_check.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi

    # Parse Claude's JSON response
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi
    # Strip markdown code fences if Claude wrapped the JSON in ```json ... ```
    json_text=$(echo "$json_text" | sed '/^```/d')

    local is_complete=$(echo "$json_text" | jq -r '.complete // false' 2>/dev/null)
    local confidence=$(echo "$json_text" | jq -r '.confidence // empty' 2>/dev/null)
    local reason=$(echo "$json_text" | jq -r '.reason // empty' 2>/dev/null)

    if [ "$is_complete" = "true" ]; then
        echo ""
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        echo -e "\033[1;32m  ✅ MASTER SPEC FULLY IMPLEMENTED!\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;32m  Confidence: ${confidence}\033[0m"
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        [ -n "$reason" ] && echo -e "  \033[1;36m$reason\033[0m"
        echo ""
        return 0  # Complete
    else
        echo ""
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        echo -e "\033[1;33m  ⚠ Master spec not yet fully satisfied\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;33m  Confidence: ${confidence}\033[0m"
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        [ -n "$reason" ] && echo -e "  \033[1;36m$reason\033[0m"

        # Show gaps if present
        local gaps=$(echo "$json_text" | jq -r '.gaps[]? // empty' 2>/dev/null)
        if [ -n "$gaps" ]; then
            echo ""
            echo -e "  \033[1;33mGaps found:\033[0m"
            echo "$gaps" | while read -r gap; do
                echo -e "    • $gap"
            done
        fi
        echo ""
        return 1  # Not complete
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SPEC MODE - Creates specs: research → draft → refine → review → fix → signoff
# ═══════════════════════════════════════════════════════════════════════════════

# Helper function to run spec signoff check
run_spec_signoff_check() {
    echo ""
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;33m  🔍 SPEC SIGN-OFF CHECK - Is the spec ready for implementation?\033[0m"
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    local check_log="$TEMP_DIR/spec_signoff.log"
    local check_result

    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "$(resolve_prompt spec/signoff.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Checking if spec is ready for implementation..."

        check_result=$(cat "$(resolve_prompt spec/signoff.md)" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi

    # Parse Claude's JSON response using jq
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi
    # Strip markdown code fences if Claude wrapped the JSON in ```json ... ```
    json_text=$(echo "$json_text" | sed '/^```/d')

    local is_ready=$(echo "$json_text" | jq -r '.ready // false' 2>/dev/null)
    local confidence=$(echo "$json_text" | jq -r '.confidence // empty' 2>/dev/null)
    local recommendation=$(echo "$json_text" | jq -r '.recommendation // empty' 2>/dev/null)
    local sections_complete=$(echo "$json_text" | jq -r '.sections_complete // empty' 2>/dev/null)
    local sections_total=$(echo "$json_text" | jq -r '.sections_total // empty' 2>/dev/null)
    local blocking=$(echo "$json_text" | jq -r '.blocking_issues // empty' 2>/dev/null)
    local unanswered=$(echo "$json_text" | jq -r '.unanswered_questions // empty' 2>/dev/null)

    if [ "$is_ready" = "true" ]; then
        echo ""
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        echo -e "\033[1;32m  ✅ SPEC APPROVED!\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;32m  Confidence: ${confidence}\033[0m"
        [ -n "$sections_complete" ] && [ -n "$sections_total" ] && echo -e "\033[1;32m  Sections: ${sections_complete}/${sections_total}\033[0m"
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        [ -n "$recommendation" ] && echo -e "  \033[1;36m$recommendation\033[0m"
        echo ""
        return 0  # Ready
    else
        echo ""
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        echo -e "\033[1;33m  ⚠ Spec not yet ready for implementation\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;33m  Confidence: ${confidence}\033[0m"
        [ -n "$blocking" ] && echo -e "\033[1;33m  Blocking issues: ${blocking}\033[0m"
        [ -n "$unanswered" ] && echo -e "\033[1;33m  Unanswered questions: ${unanswered}\033[0m"
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        [ -n "$recommendation" ] && echo -e "  \033[1;36m$recommendation\033[0m"
        echo ""
        return 1  # Not ready
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# INSIGHTS MODE - Runs analysis on existing iteration logs
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "insights" ]; then
    echo ""
    echo -e "\033[1;35m╔════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║              INSIGHTS ANALYSIS MODE                        ║\033[0m"
    echo -e "\033[1;35m╚════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    run_insights_analysis "standalone"

    # Calculate final total elapsed time
    FINAL_ELAPSED=$(($(date +%s) - LOOP_START_TIME))
    FINAL_FORMATTED=$(format_duration $FINAL_ELAPSED)

    echo ""
    echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;32m  Insights analysis complete in $FINAL_FORMATTED\033[0m"
    echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
    echo ""

    exit 0
fi

if [ "$MODE" = "spec" ]; then
    TOTAL_ITERATIONS=0
    SPEC_READY=false

    echo ""
    echo -e "\033[1;35m╔════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║              SPEC CREATION MODE                            ║\033[0m"
    echo -e "\033[1;35m╠════════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;35m║  research → draft → refine → review → fix → signoff       ║\033[0m"
    echo -e "\033[1;35m╚════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    # ─────────────────────────────────────────────────────────────────────
    # PHASE 2a: RESEARCH
    # ─────────────────────────────────────────────────────────────────────
    print_phase_banner "RESEARCH" $SPEC_RESEARCH_ITERS

    RESEARCH_ITERATION=0
    while [ $RESEARCH_ITERATION -lt $SPEC_RESEARCH_ITERS ]; do
        RESEARCH_ITERATION=$((RESEARCH_ITERATION + 1))
        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

        if ! run_single_iteration "$(resolve_prompt spec/research.md)" $TOTAL_ITERATIONS "RESEARCH ($RESEARCH_ITERATION/$SPEC_RESEARCH_ITERS)"; then
            echo -e "  \033[1;31m✗\033[0m Research phase failed"
            if check_circuit_breaker; then
                break
            fi
        fi
    done

    echo -e "  \033[1;32m✓\033[0m Research phase complete"

    # ─────────────────────────────────────────────────────────────────────
    # PHASE 2b: DRAFT
    # ─────────────────────────────────────────────────────────────────────
    print_phase_banner "DRAFT" $SPEC_DRAFT_ITERS

    DRAFT_ITERATION=0
    while [ $DRAFT_ITERATION -lt $SPEC_DRAFT_ITERS ]; do
        DRAFT_ITERATION=$((DRAFT_ITERATION + 1))
        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

        if ! run_single_iteration "$(resolve_prompt spec/draft.md)" $TOTAL_ITERATIONS "DRAFT ($DRAFT_ITERATION/$SPEC_DRAFT_ITERS)"; then
            echo -e "  \033[1;31m✗\033[0m Draft phase failed"
            if check_circuit_breaker; then
                break
            fi
        fi
    done

    # Copy new spec to active.md if it was created
    if [ -f "$SPEC_FILE" ]; then
        echo -e "  \033[1;36mℹ\033[0m  Copying spec to active.md"
        cp "$SPEC_FILE" "$ACTIVE_SPEC"
        git add "$ACTIVE_SPEC"
        git commit -m "spec: copy to active.md" 2>/dev/null || true
        git push origin "$CURRENT_BRANCH" 2>/dev/null || true
    fi

    echo -e "  \033[1;32m✓\033[0m Draft phase complete"

    # ─────────────────────────────────────────────────────────────────────
    # PHASE 2c: REFINE (with early exit)
    # ─────────────────────────────────────────────────────────────────────
    print_phase_banner "REFINE" $SPEC_REFINE_ITERS

    REFINE_ITERATION=0
    REFINEMENT_DONE=false
    while [ $REFINE_ITERATION -lt $SPEC_REFINE_ITERS ] && [ "$REFINEMENT_DONE" = false ]; do
        REFINE_ITERATION=$((REFINE_ITERATION + 1))
        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

        # Check for early exit — REFINEMENT_COMPLETE flag in spec_questions.md
        if [ -f "./.ralph/spec_questions.md" ]; then
            if grep -q 'REFINEMENT_COMPLETE=true' "./.ralph/spec_questions.md" 2>/dev/null; then
                echo -e "  \033[1;32m✓\033[0m Refinement complete — all questions answered, no feedback pending"
                REFINEMENT_DONE=true
                break
            fi

            # Show unanswered question count
            UNANSWERED=$(grep -c '^A:$\|^A: *$' "./.ralph/spec_questions.md" 2>/dev/null) || UNANSWERED=0
            if [ "$UNANSWERED" -gt 0 ]; then
                echo -e "  \033[1;34mℹ\033[0m  $UNANSWERED unanswered questions remaining"
                echo -e "  \033[1;34mℹ\033[0m  Edit .ralph/spec_questions.md to answer them, then this phase will incorporate them"
            fi
        fi

        # Check for user-review.md feedback
        if [ -f "./.ralph/user-review.md" ]; then
            REVIEW_LINES=$(wc -l < "./.ralph/user-review.md" 2>/dev/null || echo "0")
            if [ "$REVIEW_LINES" -gt 1 ]; then
                echo -e "  \033[1;34mℹ\033[0m  User review feedback detected ($REVIEW_LINES lines)"
            fi
        fi

        if ! run_single_iteration "$(resolve_prompt spec/refine.md)" $TOTAL_ITERATIONS "REFINE ($REFINE_ITERATION/$SPEC_REFINE_ITERS)"; then
            echo -e "  \033[1;31m✗\033[0m Refine iteration failed"
            if check_circuit_breaker; then
                break
            fi
        fi
    done

    echo -e "  \033[1;32m✓\033[0m Refine phase complete ($REFINE_ITERATION iterations)"

    # ─────────────────────────────────────────────────────────────────────
    # PHASE 3a: REVIEW
    # ─────────────────────────────────────────────────────────────────────
    print_phase_banner "SPEC REVIEW" $SPEC_REVIEW_ITERS

    REVIEW_ITERATION=0
    while [ $REVIEW_ITERATION -lt $SPEC_REVIEW_ITERS ]; do
        REVIEW_ITERATION=$((REVIEW_ITERATION + 1))
        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

        if ! run_single_iteration "$(resolve_prompt spec/review.md)" $TOTAL_ITERATIONS "SPEC REVIEW ($REVIEW_ITERATION/$SPEC_REVIEW_ITERS)"; then
            echo -e "  \033[1;31m✗\033[0m Review phase failed"
            if check_circuit_breaker; then
                break
            fi
        fi
    done

    echo -e "  \033[1;32m✓\033[0m Review phase complete"

    # ─────────────────────────────────────────────────────────────────────
    # PHASE 3b: REVIEW-FIX (conditional)
    # ─────────────────────────────────────────────────────────────────────
    SPEC_REVIEW_FILE="./.ralph/spec_review.md"
    SHOULD_RUN_SPEC_FIX=false
    if [ -f "$SPEC_REVIEW_FILE" ]; then
        SPEC_FIX_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$SPEC_REVIEW_FILE" 2>/dev/null) || SPEC_FIX_BLOCKING=0
        SPEC_FIX_ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$SPEC_REVIEW_FILE" 2>/dev/null) || SPEC_FIX_ATTENTION=0
        if [ "$SPEC_FIX_BLOCKING" -gt 0 ] || [ "$SPEC_FIX_ATTENTION" -gt 0 ]; then
            SHOULD_RUN_SPEC_FIX=true
        fi
    fi

    if [ "$SHOULD_RUN_SPEC_FIX" = true ]; then
        print_phase_banner "SPEC REVIEW-FIX" $SPEC_REVIEWFIX_ITERS
        echo -e "  \033[1;34mℹ\033[0m  Issues to fix: \033[1;31m❌ Blocking: $SPEC_FIX_BLOCKING\033[0m  \033[1;33m⚠️ Attention: $SPEC_FIX_ATTENTION\033[0m"

        REVIEWFIX_ITERATION=0
        while [ $REVIEWFIX_ITERATION -lt $SPEC_REVIEWFIX_ITERS ]; do
            REVIEWFIX_ITERATION=$((REVIEWFIX_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

            if ! run_single_iteration "$(resolve_prompt spec/review_fix.md)" $TOTAL_ITERATIONS "SPEC REVIEW-FIX ($REVIEWFIX_ITERATION/$SPEC_REVIEWFIX_ITERS)"; then
                echo -e "  \033[1;31m✗\033[0m Review-fix iteration failed"
                if check_circuit_breaker; then
                    break
                fi
            fi
        done

        echo -e "  \033[1;32m✓\033[0m Review-fix phase complete"
    else
        echo -e "  \033[1;32m✓\033[0m No blocking/attention issues — skipping review-fix"
    fi

    # ─────────────────────────────────────────────────────────────────────
    # SIGN-OFF CHECK
    # ─────────────────────────────────────────────────────────────────────
    TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
    if run_spec_signoff_check; then
        SPEC_READY=true
    fi

    # Calculate final total elapsed time
    FINAL_ELAPSED=$(($(date +%s) - LOOP_START_TIME))
    FINAL_FORMATTED=$(format_duration $FINAL_ELAPSED)

    # Clean up state file on completion
    rm -f "$STATE_FILE"

    echo ""
    echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
    if [ "$SPEC_READY" = true ]; then
        echo -e "\033[1;32m  🎉 Spec created and approved in $TOTAL_ITERATIONS iteration(s)\033[0m"
        echo -e "\033[1;32m  Next: node .ralph/run.js $SPEC_NAME plan\033[0m"
    else
        echo -e "\033[1;33m  ⚠ Spec creation completed but not yet approved\033[0m"
        echo -e "\033[1;33m  Review .ralph/spec_review.md and .ralph/spec_questions.md\033[0m"
        echo -e "\033[1;33m  Then run spec mode again to continue refinement\033[0m"
    fi
    echo -e "\033[1;32m  Total time: $FINAL_FORMATTED\033[0m"
    echo -e "\033[1;32m  Errors: $ERROR_COUNT\033[0m"
    echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
    echo ""

    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# FULL MODE - Runs plan → build → review → check cycles
# In full mode, MAX_ITERATIONS is treated as MAX_CYCLES (number of complete cycles)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "full" ]; then
    TOTAL_ITERATIONS=0
    CYCLE=0
    MAX_CYCLES=$MAX_ITERATIONS  # Rename for clarity - in full mode, this is cycles not iterations
    IMPLEMENTATION_COMPLETE=false
    CURRENT_SUBSPEC=""

    # Detect if this spec has been decomposed into sub-specs
    IS_DECOMPOSED=false
    if check_manifest_exists; then
        IS_DECOMPOSED=true
        MANIFEST_PATH="./.ralph/specs/${SPEC_NAME}/manifest.json"
        echo ""
        echo -e "\033[1;35m╔════════════════════════════════════════════════════════════╗\033[0m"
        echo -e "\033[1;35m║  📦 DECOMPOSED SPEC DETECTED                              ║\033[0m"
        echo -e "\033[1;35m╚════════════════════════════════════════════════════════════╝\033[0m"
        echo ""
        # Show current progress from manifest
        MANIFEST_TOTAL=$(jq -r '.progress.total // 0' "$MANIFEST_PATH" 2>/dev/null)
        MANIFEST_COMPLETE=$(jq -r '.progress.complete // 0' "$MANIFEST_PATH" 2>/dev/null)
        MANIFEST_IN_PROGRESS=$(jq -r '.progress.in_progress // 0' "$MANIFEST_PATH" 2>/dev/null)
        MANIFEST_PENDING=$(jq -r '.progress.pending // 0' "$MANIFEST_PATH" 2>/dev/null)
        echo -e "  Sub-specs: $MANIFEST_TOTAL total, \033[1;32m$MANIFEST_COMPLETE complete\033[0m, \033[1;33m$MANIFEST_IN_PROGRESS in progress\033[0m, \033[1;36m$MANIFEST_PENDING pending\033[0m"
        echo ""
    else
        # Check if spec is large and suggest decomposition
        SPEC_LINE_COUNT=$(wc -l < "$SPEC_FILE" 2>/dev/null || echo "0")
        if [ "$SPEC_LINE_COUNT" -gt 200 ]; then
            echo ""
            echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
            echo -e "\033[1;33m  ⚠ LARGE SPEC DETECTED ($SPEC_LINE_COUNT lines)\033[0m"
            echo -e "\033[1;33m  Consider running decompose mode first for better results:\033[0m"
            echo -e "\033[1;33m    node .ralph/run.js $SPEC_NAME decompose\033[0m"
            echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
            echo ""
        fi
    fi

    while [ "$IMPLEMENTATION_COMPLETE" = false ]; do
        CYCLE=$((CYCLE + 1))

        # Check max cycles at the start of each cycle
        if [ $CYCLE -gt $MAX_CYCLES ]; then
            echo -e "\033[1;33mReached max cycles: $MAX_CYCLES\033[0m"
            break
        fi

        # Check circuit breaker
        if check_circuit_breaker; then
            break
        fi

        # ─────────────────────────────────────────────────────────────────────
        # SUB-SPEC SELECTION (decomposed specs only)
        # ─────────────────────────────────────────────────────────────────────
        if [ "$IS_DECOMPOSED" = true ]; then
            run_spec_select
            SPEC_SELECT_RESULT=$?

            if [ $SPEC_SELECT_RESULT -eq 1 ]; then
                # All sub-specs complete — run master completion check
                if run_master_completion_check; then
                    IMPLEMENTATION_COMPLETE=true
                    break
                else
                    echo -e "  \033[1;33m⚠ Master check found gaps. Continuing cycles...\033[0m"
                    # The gaps will be addressed in the next cycle
                    # spec_select should find something to work on, or we'll be stuck
                fi
            elif [ $SPEC_SELECT_RESULT -eq 2 ]; then
                # Blocked — cannot proceed
                echo -e "\033[1;31m  ✗ All remaining sub-specs are blocked. Human intervention required.\033[0m"
                create_paused_state "All remaining sub-specs are blocked by unmet dependencies"
                break
            fi
            # SPEC_SELECT_RESULT=0 means we selected a sub-spec, continue to plan phase
        fi

        print_cycle_banner $CYCLE
        
        # ─────────────────────────────────────────────────────────────────────
        # PLAN PHASE
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "PLAN" $FULL_PLAN_ITERS
        
        PLAN_ITERATION=0
        PHASE_ERROR=false
        while [ $PLAN_ITERATION -lt $FULL_PLAN_ITERS ]; do
            PLAN_ITERATION=$((PLAN_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
            
            if ! run_single_iteration "$(resolve_prompt plan.md)" $TOTAL_ITERATIONS "PLAN ($PLAN_ITERATION/$FULL_PLAN_ITERS)"; then
                echo -e "  \033[1;31m✗\033[0m Claude error - checking circuit breaker"
                if check_circuit_breaker; then
                    PHASE_ERROR=true
                    break
                fi
            fi
            
            # Show progress
            PLAN_FILE="./.ralph/implementation_plan.md"
            if [ -f "$PLAN_FILE" ]; then
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
                echo -e "  \033[1;34mℹ\033[0m  Implementation plan has $UNCHECKED_COUNT items"
            fi
        done
        
        # Exit full mode on error
        if [ "$PHASE_ERROR" = true ]; then
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            echo -e "\033[1;31m  ❌ Full mode stopped due to circuit breaker\033[0m"
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            break
        fi
        
        echo -e "  \033[1;32m✓\033[0m Plan phase complete ($PLAN_ITERATION iterations)"

        run_insights_analysis "plan"

        # ─────────────────────────────────────────────────────────────────────
        # BUILD PHASE
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "BUILD" $FULL_BUILD_ITERS
        
        BUILD_ITERATION=0
        PHASE_ERROR=false
        while [ $BUILD_ITERATION -lt $FULL_BUILD_ITERS ]; do
            BUILD_ITERATION=$((BUILD_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
            
            # Check if build is complete before running
            PLAN_FILE="./.ralph/implementation_plan.md"
            if [ -f "$PLAN_FILE" ]; then
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
                if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                    echo -e "  \033[1;32m✓\033[0m All build tasks complete!"
                    break
                fi
                echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT unchecked items remaining"
            fi
            
            if ! run_single_iteration "$(resolve_prompt build.md)" $TOTAL_ITERATIONS "BUILD ($BUILD_ITERATION/$FULL_BUILD_ITERS)"; then
                echo -e "  \033[1;31m✗\033[0m Claude error - checking circuit breaker"
                if check_circuit_breaker; then
                    PHASE_ERROR=true
                    break
                fi
            fi
        done
        
        # Exit full mode on error
        if [ "$PHASE_ERROR" = true ]; then
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            echo -e "\033[1;31m  ❌ Full mode stopped due to circuit breaker\033[0m"
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            break
        fi
        
        echo -e "  \033[1;32m✓\033[0m Build phase complete"

        run_insights_analysis "build"

        # ─────────────────────────────────────────────────────────────────────
        # REVIEW PHASE (with setup on first iteration of each cycle)
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "REVIEW" $FULL_REVIEW_ITERS
        
        # Run review setup
        echo -e "  \033[1;35m⚙\033[0m  Running review setup..."
        SETUP_LOG_FILE="$TEMP_DIR/review_setup_cycle_${CYCLE}.log"
        
        if [ "$VERBOSE" = true ]; then
            cat "$(resolve_prompt review/setup.md)" | claude -p \
                --dangerously-skip-permissions \
                --output-format=stream-json \
                --verbose 2>&1 | tee "$SETUP_LOG_FILE"
        else
            cat "$(resolve_prompt review/setup.md)" | claude -p \
                --dangerously-skip-permissions \
                --output-format=stream-json \
                --verbose > "$SETUP_LOG_FILE" 2>&1 &
            
            SETUP_PID=$!
            spin $SETUP_PID
            wait $SETUP_PID
        fi
        
        git push origin "$CURRENT_BRANCH" || git push -u origin "$CURRENT_BRANCH"
        echo -e "  \033[1;32m✓\033[0m Review setup complete"
        echo ""
        
        REVIEW_ITERATION=0
        PHASE_ERROR=false

        if [ "${PARALLEL_REVIEW:-true}" = "true" ]; then
            # ── PARALLEL REVIEW MODE ──
            # Run all specialist types simultaneously, then iterate for remaining items
            while [ $REVIEW_ITERATION -lt $FULL_REVIEW_ITERS ]; do
                REVIEW_ITERATION=$((REVIEW_ITERATION + 1))
                TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

                # Check if review is complete before running
                CHECKLIST_FILE="./.ralph/review_checklist.md"
                if [ -f "$CHECKLIST_FILE" ]; then
                    UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$CHECKLIST_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
                    if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                        echo -e "  \033[1;32m✓\033[0m All review items complete!"
                        break
                    fi

                    # Count items by specialist type
                    SEC_COUNT=$(grep -c '^\- \[ \].*\[SEC' "$CHECKLIST_FILE" 2>/dev/null) || SEC_COUNT=0
                    UX_COUNT=$(grep -c '^\- \[ \].*\[UX\]' "$CHECKLIST_FILE" 2>/dev/null) || UX_COUNT=0
                    DB_COUNT=$(grep -c '^\- \[ \].*\[DB\]' "$CHECKLIST_FILE" 2>/dev/null) || DB_COUNT=0
                    PERF_COUNT=$(grep -c '^\- \[ \].*\[PERF\]' "$CHECKLIST_FILE" 2>/dev/null) || PERF_COUNT=0
                    API_COUNT=$(grep -c '^\- \[ \].*\[API\]' "$CHECKLIST_FILE" 2>/dev/null) || API_COUNT=0
                    ANTAG_COUNT=$(grep -c '^\- \[ \].*\[ANTAG' "$CHECKLIST_FILE" 2>/dev/null) || ANTAG_COUNT=0
                    QA_COUNT=$((UNCHECKED_COUNT - SEC_COUNT - UX_COUNT - DB_COUNT - PERF_COUNT - API_COUNT - ANTAG_COUNT))
                    echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining: \033[1;31mSEC:$SEC_COUNT\033[0m \033[1;35mUX:$UX_COUNT\033[0m \033[1;36mDB:$DB_COUNT\033[0m \033[1;32mPERF:$PERF_COUNT\033[0m \033[1;34mAPI:$API_COUNT\033[0m \033[0;91mANTAG:$ANTAG_COUNT\033[0m \033[1;33mQA:$QA_COUNT\033[0m"
                fi

                run_parallel_review
                local parallel_exit=$?

                if [ $parallel_exit -eq 2 ]; then
                    # Wrapper not found — fall back to sequential for rest of this cycle
                    echo -e "  \033[1;33m⚠\033[0m  Falling back to sequential review"
                    break
                elif [ $parallel_exit -ne 0 ]; then
                    echo -e "  \033[1;31m✗\033[0m Parallel review failed - checking circuit breaker"
                    if check_circuit_breaker; then
                        PHASE_ERROR=true
                        break
                    fi
                fi
            done
        else
            # ── SEQUENTIAL REVIEW MODE (fallback) ──
            while [ $REVIEW_ITERATION -lt $FULL_REVIEW_ITERS ]; do
                REVIEW_ITERATION=$((REVIEW_ITERATION + 1))
                TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

                # Check if review is complete before running
                CHECKLIST_FILE="./.ralph/review_checklist.md"
                if [ -f "$CHECKLIST_FILE" ]; then
                    UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$CHECKLIST_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
                    if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                        echo -e "  \033[1;32m✓\033[0m All review items complete!"
                        break
                    fi

                    # Count items by specialist type
                    SEC_COUNT=$(grep -c '^\- \[ \].*\[SEC' "$CHECKLIST_FILE" 2>/dev/null) || SEC_COUNT=0
                    UX_COUNT=$(grep -c '^\- \[ \].*\[UX\]' "$CHECKLIST_FILE" 2>/dev/null) || UX_COUNT=0
                    DB_COUNT=$(grep -c '^\- \[ \].*\[DB\]' "$CHECKLIST_FILE" 2>/dev/null) || DB_COUNT=0
                    PERF_COUNT=$(grep -c '^\- \[ \].*\[PERF\]' "$CHECKLIST_FILE" 2>/dev/null) || PERF_COUNT=0
                    API_COUNT=$(grep -c '^\- \[ \].*\[API\]' "$CHECKLIST_FILE" 2>/dev/null) || API_COUNT=0
                    ANTAG_COUNT=$(grep -c '^\- \[ \].*\[ANTAG' "$CHECKLIST_FILE" 2>/dev/null) || ANTAG_COUNT=0
                    QA_COUNT=$((UNCHECKED_COUNT - SEC_COUNT - UX_COUNT - DB_COUNT - PERF_COUNT - API_COUNT - ANTAG_COUNT))
                    echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining: \033[1;31mSEC:$SEC_COUNT\033[0m \033[1;35mUX:$UX_COUNT\033[0m \033[1;36mDB:$DB_COUNT\033[0m \033[1;32mPERF:$PERF_COUNT\033[0m \033[1;34mAPI:$API_COUNT\033[0m \033[0;91mANTAG:$ANTAG_COUNT\033[0m \033[1;33mQA:$QA_COUNT\033[0m"
                fi

                # Determine which specialist should handle the next item
                SPECIALIST=$(get_next_review_specialist)
                case $SPECIALIST in
                    security)
                        REVIEW_PROMPT="$(resolve_prompt review/security.md)"
                        SPECIALIST_NAME="Security"
                        SPECIALIST_COLOR="\033[1;31m"  # Red
                        ;;
                    ux)
                        REVIEW_PROMPT="$(resolve_prompt review/ux.md)"
                        SPECIALIST_NAME="UX"
                        SPECIALIST_COLOR="\033[1;35m"  # Magenta
                        ;;
                    db)
                        REVIEW_PROMPT="$(resolve_prompt review/db.md)"
                        SPECIALIST_NAME="DB"
                        SPECIALIST_COLOR="\033[1;36m"  # Cyan
                        ;;
                    perf)
                        REVIEW_PROMPT="$(resolve_prompt review/perf.md)"
                        SPECIALIST_NAME="Performance"
                        SPECIALIST_COLOR="\033[1;32m"  # Green
                        ;;
                    api)
                        REVIEW_PROMPT="$(resolve_prompt review/api.md)"
                        SPECIALIST_NAME="API"
                        SPECIALIST_COLOR="\033[1;34m"  # Blue
                        ;;
                    antagonist)
                        REVIEW_PROMPT="$(resolve_prompt review/antagonist.md)"
                        SPECIALIST_NAME="Antagonist"
                        SPECIALIST_COLOR="\033[0;91m"  # Bright red
                        ;;
                    *)
                        REVIEW_PROMPT="$(resolve_prompt review/qa.md)"
                        SPECIALIST_NAME="QA"
                        SPECIALIST_COLOR="\033[1;33m"  # Yellow
                        ;;
                esac

                # Fallback to generic review.md if specialist prompt doesn't exist
                if [ ! -f "$REVIEW_PROMPT" ]; then
                    REVIEW_PROMPT="$(resolve_prompt review/general.md)"
                    SPECIALIST_NAME="General"
                    SPECIALIST_COLOR="\033[1;37m"
                fi

                echo -e "  ${SPECIALIST_COLOR}🔍 Specialist: $SPECIALIST_NAME\033[0m"

                if ! run_single_iteration "$REVIEW_PROMPT" $TOTAL_ITERATIONS "REVIEW-$SPECIALIST_NAME ($REVIEW_ITERATION/$FULL_REVIEW_ITERS)"; then
                    echo -e "  \033[1;31m✗\033[0m Claude error - checking circuit breaker"
                    if check_circuit_breaker; then
                        PHASE_ERROR=true
                        break
                    fi
                fi
            done
        fi
        
        # Exit full mode on error
        if [ "$PHASE_ERROR" = true ]; then
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            echo -e "\033[1;31m  ❌ Full mode stopped due to circuit breaker\033[0m"
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            break
        fi
        
        echo -e "  \033[1;32m✓\033[0m Review phase complete"

        run_insights_analysis "review"

        # ─────────────────────────────────────────────────────────────────────
        # REVIEW-FIX PHASE
        # ─────────────────────────────────────────────────────────────────────

        # Only run review-fix if review.md exists and has blocking/attention issues
        REVIEW_FILE="./.ralph/review.md"
        SHOULD_RUN_FIX=false
        if [ -f "$REVIEW_FILE" ]; then
            FIX_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null) || FIX_BLOCKING=0
            FIX_ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$REVIEW_FILE" 2>/dev/null) || FIX_ATTENTION=0
            if [ "$FIX_BLOCKING" -gt 0 ] || [ "$FIX_ATTENTION" -gt 0 ]; then
                SHOULD_RUN_FIX=true
            fi
        fi

        if [ "$SHOULD_RUN_FIX" = true ]; then
            print_phase_banner "REVIEW-FIX" $FULL_REVIEWFIX_ITERS
            echo -e "  \033[1;34mℹ\033[0m  Issues to fix: \033[1;31m❌ Blocking: $FIX_BLOCKING\033[0m  \033[1;33m⚠️ Attention: $FIX_ATTENTION\033[0m"

            REVIEWFIX_ITERATION=0
            PHASE_ERROR=false
            while [ $REVIEWFIX_ITERATION -lt $FULL_REVIEWFIX_ITERS ]; do
                REVIEWFIX_ITERATION=$((REVIEWFIX_ITERATION + 1))
                TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

                # Check if all issues are resolved before running
                if [ -f "$REVIEW_FILE" ]; then
                    REMAINING_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null) || REMAINING_BLOCKING=0
                    REMAINING_ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$REVIEW_FILE" 2>/dev/null) || REMAINING_ATTENTION=0
                    if [ "$REMAINING_BLOCKING" -eq 0 ] && [ "$REMAINING_ATTENTION" -eq 0 ]; then
                        echo -e "  \033[1;32m✓\033[0m All review issues resolved!"
                        break
                    fi
                    echo -e "  \033[1;34mℹ\033[0m  Remaining: \033[1;31m❌ $REMAINING_BLOCKING\033[0m  \033[1;33m⚠️ $REMAINING_ATTENTION\033[0m"
                fi

                if ! run_single_iteration "$(resolve_prompt review/fix.md)" $TOTAL_ITERATIONS "REVIEW-FIX ($REVIEWFIX_ITERATION/$FULL_REVIEWFIX_ITERS)"; then
                    echo -e "  \033[1;31m✗\033[0m Claude error - checking circuit breaker"
                    if check_circuit_breaker; then
                        PHASE_ERROR=true
                        break
                    fi
                fi
            done

            # Exit full mode on error
            if [ "$PHASE_ERROR" = true ]; then
                echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
                echo -e "\033[1;31m  ❌ Full mode stopped due to circuit breaker\033[0m"
                echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
                break
            fi

            echo -e "  \033[1;32m✓\033[0m Review-fix phase complete"

            run_insights_analysis "review-fix"
        else
            echo -e "  \033[1;32m✓\033[0m No blocking/attention issues — skipping review-fix"
        fi

        # ─────────────────────────────────────────────────────────────────────
        # DISTILL PHASE (update AGENTS.md with cycle learnings)
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "DISTILL" $FULL_DISTILL_ITERS

        DISTILL_ITERATION=0
        PHASE_ERROR=false
        while [ $DISTILL_ITERATION -lt $FULL_DISTILL_ITERS ]; do
            DISTILL_ITERATION=$((DISTILL_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

            if ! run_single_iteration "$(resolve_prompt distill.md)" $TOTAL_ITERATIONS "DISTILL ($DISTILL_ITERATION/$FULL_DISTILL_ITERS)"; then
                echo -e "  \033[1;31m✗\033[0m Claude error - checking circuit breaker"
                if check_circuit_breaker; then
                    PHASE_ERROR=true
                    break
                fi
            fi
        done

        if [ "$PHASE_ERROR" = true ]; then
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            echo -e "\033[1;31m  ❌ Full mode stopped due to circuit breaker\033[0m"
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            break
        fi

        echo -e "  \033[1;32m✓\033[0m Distill phase complete"

        run_insights_analysis "distill"

        # ─────────────────────────────────────────────────────────────────────
        # COMPLETION CHECK
        # ─────────────────────────────────────────────────────────────────────
        if run_completion_check; then
            # Write completion marker for parallel orchestrator detection
            local completion_marker="./.ralph/sub_spec_complete.json"
            echo "{\"complete\": true, \"spec\": \"${SPEC_NAME}\", \"subspec\": \"${RALPH_SUBSPEC_NAME:-none}\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$completion_marker"

            if [ "$IS_DECOMPOSED" = true ]; then
                # Mark current sub-spec as complete and loop to select next
                mark_subspec_complete
                echo -e "  \033[1;35m→\033[0m Sub-spec complete. Selecting next sub-spec..."
                # Don't set IMPLEMENTATION_COMPLETE — let spec_select determine if all are done
            else
                IMPLEMENTATION_COMPLETE=true
            fi
        else
            echo -e "  \033[1;35m→\033[0m Starting next cycle..."
        fi
    done
    
    # Calculate final total elapsed time
    FINAL_ELAPSED=$(($(date +%s) - LOOP_START_TIME))
    FINAL_FORMATTED=$(format_duration $FINAL_ELAPSED)
    
    # Clean up state file on successful completion
    if [ "$IMPLEMENTATION_COMPLETE" = true ]; then
        rm -f "$STATE_FILE"
    fi
    
    echo ""
    echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
    if [ "$IMPLEMENTATION_COMPLETE" = true ]; then
        echo -e "\033[1;32m  🎉 Ralph completed spec in $CYCLE cycle(s), $TOTAL_ITERATIONS iteration(s)\033[0m"
    else
        echo -e "\033[1;33m  ⚠ Ralph stopped after $CYCLE cycle(s), $TOTAL_ITERATIONS iteration(s)\033[0m"
    fi
    echo -e "\033[1;32m  Total time: $FINAL_FORMATTED\033[0m"
    echo -e "\033[1;32m  Errors: $ERROR_COUNT\033[0m"
    echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
    echo ""
    
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STANDARD MODE - Runs single mode (plan, build, review, review-fix, or debug)
# ═══════════════════════════════════════════════════════════════════════════════

while true; do
    ITERATION=$((ITERATION + 1))
    TURN_START_TIME=$(date +%s)
    TURN_START_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")

    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -gt $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi
    
    # Check circuit breaker
    if check_circuit_breaker; then
        break
    fi

    # Check if there are any remaining unchecked items (build and review modes)
    if [ "$MODE" = "build" ]; then
        PLAN_FILE="./.ralph/implementation_plan.md"
        if [ -f "$PLAN_FILE" ]; then
            UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
            if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                echo ""
                echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
                echo -e "\033[1;32m  ✅ All tasks complete! No unchecked items remaining.\033[0m"
                echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
                echo ""
                break
            fi
            echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT unchecked items remaining"
        fi
    elif [ "$MODE" = "review" ]; then
        CHECKLIST_FILE="./.ralph/review_checklist.md"
        if [ -f "$CHECKLIST_FILE" ]; then
            UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$CHECKLIST_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
            if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                echo ""
                echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
                echo -e "\033[1;32m  ✅ Review complete! All items have been reviewed.\033[0m"
                echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
                echo ""
                break
            fi

            # Count items by specialist type
            SEC_COUNT=$(grep -c '^\- \[ \].*\[SEC' "$CHECKLIST_FILE" 2>/dev/null) || SEC_COUNT=0
            UX_COUNT=$(grep -c '^\- \[ \].*\[UX\]' "$CHECKLIST_FILE" 2>/dev/null) || UX_COUNT=0
            DB_COUNT=$(grep -c '^\- \[ \].*\[DB\]' "$CHECKLIST_FILE" 2>/dev/null) || DB_COUNT=0
            PERF_COUNT=$(grep -c '^\- \[ \].*\[PERF\]' "$CHECKLIST_FILE" 2>/dev/null) || PERF_COUNT=0
            API_COUNT=$(grep -c '^\- \[ \].*\[API\]' "$CHECKLIST_FILE" 2>/dev/null) || API_COUNT=0
            ANTAG_COUNT=$(grep -c '^\- \[ \].*\[ANTAG' "$CHECKLIST_FILE" 2>/dev/null) || ANTAG_COUNT=0
            QA_COUNT=$((UNCHECKED_COUNT - SEC_COUNT - UX_COUNT - DB_COUNT - PERF_COUNT - API_COUNT - ANTAG_COUNT))
            echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining: \033[1;31mSEC:$SEC_COUNT\033[0m \033[1;35mUX:$UX_COUNT\033[0m \033[1;36mDB:$DB_COUNT\033[0m \033[1;32mPERF:$PERF_COUNT\033[0m \033[1;34mAPI:$API_COUNT\033[0m \033[0;91mANTAG:$ANTAG_COUNT\033[0m \033[1;33mQA:$QA_COUNT\033[0m"

            if [ "${PARALLEL_REVIEW:-true}" = "true" ]; then
                # Parallel review mode — run all specialists simultaneously
                run_parallel_review
                local parallel_exit=$?
                if [ $parallel_exit -eq 2 ]; then
                    # Wrapper not found — fall through to sequential
                    :
                elif [ $parallel_exit -eq 0 ]; then
                    continue  # Skip sequential, loop back to check remaining
                else
                    # Failed — circuit breaker checked inside run_parallel_review
                    continue
                fi
            fi

            # Sequential fallback (or PARALLEL_REVIEW=false)
            # Determine which specialist should handle the next item
            SPECIALIST=$(get_next_review_specialist)
            case $SPECIALIST in
                security)
                    PROMPT_FILE="$(resolve_prompt review/security.md)"
                    echo -e "  \033[1;31m🔍 Specialist: Security Expert\033[0m"
                    ;;
                ux)
                    PROMPT_FILE="$(resolve_prompt review/ux.md)"
                    echo -e "  \033[1;35m🔍 Specialist: UX Expert\033[0m"
                    ;;
                db)
                    PROMPT_FILE="$(resolve_prompt review/db.md)"
                    echo -e "  \033[1;36m🔍 Specialist: DB Expert\033[0m"
                    ;;
                perf)
                    PROMPT_FILE="$(resolve_prompt review/perf.md)"
                    echo -e "  \033[1;32m🔍 Specialist: Performance Expert\033[0m"
                    ;;
                api)
                    PROMPT_FILE="$(resolve_prompt review/api.md)"
                    echo -e "  \033[1;34m🔍 Specialist: API Expert\033[0m"
                    ;;
                antagonist)
                    PROMPT_FILE="$(resolve_prompt review/antagonist.md)"
                    echo -e "  \033[0;91m🔍 Specialist: Antagonist\033[0m"
                    ;;
                *)
                    PROMPT_FILE="$(resolve_prompt review/qa.md)"
                    echo -e "  \033[1;33m🔍 Specialist: QA Expert\033[0m"
                    ;;
            esac

            # Fallback to generic review.md if specialist prompt doesn't exist
            if [ ! -f "$PROMPT_FILE" ]; then
                PROMPT_FILE="$(resolve_prompt review/general.md)"
                echo -e "  \033[1;37m🔍 Specialist: General\033[0m"
            fi
        else
            echo -e "  \033[1;31m✗\033[0m  Review checklist not found. Run setup first."
            break
        fi
    elif [ "$MODE" = "review-fix" ]; then
        # Check if there are blocking issues to fix
        REVIEW_FILE="./.ralph/review.md"
        if [ -f "$REVIEW_FILE" ]; then
            BLOCKING_COUNT=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null) || BLOCKING_COUNT=0
            ATTENTION_COUNT=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$REVIEW_FILE" 2>/dev/null) || ATTENTION_COUNT=0
            if [ "$BLOCKING_COUNT" -eq 0 ] && [ "$ATTENTION_COUNT" -eq 0 ]; then
                echo ""
                echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
                echo -e "\033[1;32m  ✅ All review issues resolved!\033[0m"
                echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
                echo ""
                break
            fi
            echo -e "  \033[1;34mℹ\033[0m  Issues remaining: \033[1;31m❌ Blocking: $BLOCKING_COUNT\033[0m  \033[1;33m⚠️ Attention: $ATTENTION_COUNT\033[0m"
        else
            echo -e "  \033[1;31m✗\033[0m  Review file not found. Run review mode first."
            break
        fi
    fi

    # Display turn banner
    print_turn_banner $ITERATION
    
    # Save checkpoint
    save_state "$MODE" "$ITERATION" "Running iteration"

    # Prepare log file for this iteration
    LOG_FILE="$TEMP_DIR/iteration_${ITERATION}.log"

    # Run Ralph iteration with selected prompt
    # -p: Headless mode (non-interactive, reads from stdin)
    # --dangerously-skip-permissions: Auto-approve all tool calls (YOLO mode)
    # --output-format=stream-json: Structured output for logging/monitoring
    # --verbose: Detailed execution logging
    
    if [ "$VERBOSE" = true ]; then
        # Verbose mode: show full output and log to file
        cat "$PROMPT_FILE" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose 2>&1 | tee "$LOG_FILE"
        CLAUDE_EXIT=${PIPESTATUS[1]}
    else
        # Quiet mode: show spinner, log to file
        echo -e "  \033[1;36m⏳\033[0m Running Claude iteration $ITERATION..."
        echo ""
        
        cat "$PROMPT_FILE" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose > "$LOG_FILE" 2>&1 &
        
        CLAUDE_PID=$!
        spin $CLAUDE_PID
        wait $CLAUDE_PID
        CLAUDE_EXIT=$?
    fi
    
    if [ $CLAUDE_EXIT -ne 0 ]; then
        echo -e "  \033[1;31m✗\033[0m Claude exited with code $CLAUDE_EXIT"
        echo "  Check log: $LOG_FILE"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        echo -e "  \033[1;32m✓\033[0m Claude iteration completed"
        CONSECUTIVE_FAILURES=0  # Reset on success
    fi

    # Generate and display summary
    generate_summary "$LOG_FILE" "$ITERATION" "$TURN_START_TIME"

    # Capture iteration summary for insights
    capture_iteration_summary "$LOG_FILE" "$ITERATION" "$MODE" "$CLAUDE_EXIT" "$TURN_START_TIME" "$TURN_START_SHA"

    # Skip commit/push in debug mode
    if [ "${NO_COMMIT:-false}" = true ]; then
        echo -e "  \033[1;33m⚠️  DEBUG MODE - Skipping commit and push\033[0m"
        break  # Debug mode only runs once
    fi

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }
    
    # Update checkpoint
    save_state "$MODE" "$ITERATION" "Completed"
done

# Run insights analysis at end of standard mode
run_insights_analysis "$MODE"

# Calculate final total elapsed time
FINAL_ELAPSED=$(($(date +%s) - LOOP_START_TIME))
FINAL_FORMATTED=$(format_duration $FINAL_ELAPSED)
COMPLETED_ITERATIONS=$((ITERATION - 1))

# Clean up state file on normal completion
rm -f "$STATE_FILE"

echo ""
echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  Ralph completed $COMPLETED_ITERATIONS iteration(s) in $FINAL_FORMATTED\033[0m"
echo -e "\033[1;32m  Errors: $ERROR_COUNT\033[0m"
echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
echo ""
