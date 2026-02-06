#!/bin/bash
# Usage: ./loop.sh <spec-name> [plan|build|review|review-fix|debug|full|decompose|spec] [max_iterations] [--verbose]
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
#   FULL_REVIEW_ITERS=5     # Review iterations per cycle (default: 5)
#   FULL_REVIEWFIX_ITERS=5  # Review-fix iterations per cycle (default: 5)
#
# Circuit breaker settings (via environment variables):
#   MAX_CONSECUTIVE_FAILURES=3  # Stop after N consecutive failures (default: 3)

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
    elif [ -z "$MODE" ] && ([ "$arg" = "plan" ] || [ "$arg" = "build" ] || [ "$arg" = "review" ] || [ "$arg" = "review-fix" ] || [ "$arg" = "debug" ] || [ "$arg" = "full" ] || [ "$arg" = "decompose" ] || [ "$arg" = "spec" ]); then
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

# Verify spec file exists (skip for spec mode — spec doesn't exist yet)
SPEC_FILE="./.ralph/specs/${SPEC_NAME}.md"
if [ "$MODE" != "spec" ]; then
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
    PROMPT_FILE="./.ralph/prompts/plan.md"
    MAX_ITERATIONS=${MAX_ITERATIONS:-5}
elif [ "$MODE" = "review" ]; then
    SETUP_PROMPT_FILE="./.ralph/prompts/review/setup.md"
    PROMPT_FILE="./.ralph/prompts/review/general.md"
    MAX_ITERATIONS=${MAX_ITERATIONS:-10}
elif [ "$MODE" = "review-fix" ]; then
    PROMPT_FILE="./.ralph/prompts/review/fix.md"
    MAX_ITERATIONS=${MAX_ITERATIONS:-5}
elif [ "$MODE" = "debug" ]; then
    # Debug mode: single iteration, verbose, no commit/push
    PROMPT_FILE="./.ralph/prompts/build.md"
    MAX_ITERATIONS=1
    VERBOSE=true
    NO_COMMIT=true
elif [ "$MODE" = "decompose" ]; then
    # Decompose mode: single iteration to break spec into sub-specs
    PROMPT_FILE="./.ralph/prompts/decompose.md"
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
elif [ "$MODE" = "full" ]; then
    # Full mode: cycles of plan → build → review → completion check
    MAX_ITERATIONS=${MAX_ITERATIONS:-100}
    FULL_PLAN_ITERS=${FULL_PLAN_ITERS:-5}
    FULL_BUILD_ITERS=${FULL_BUILD_ITERS:-10}
    FULL_REVIEW_ITERS=${FULL_REVIEW_ITERS:-15}  # More iterations to cover all review items
    FULL_REVIEWFIX_ITERS=${FULL_REVIEWFIX_ITERS:-5}  # Review-fix iterations per cycle
else
    MODE="build"
    PROMPT_FILE="./.ralph/prompts/build.md"
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
    echo "Cycle:   plan($FULL_PLAN_ITERS) → build($FULL_BUILD_ITERS) → review($FULL_REVIEW_ITERS) → review-fix($FULL_REVIEWFIX_ITERS) → check"
    [ $MAX_ITERATIONS -gt 0 ] && echo "Max:     $MAX_ITERATIONS cycles"
elif [ "$MODE" = "debug" ]; then
    echo "⚠️  DEBUG MODE - No commits will be made"
else
    [ -n "$SETUP_PROMPT_FILE" ] && echo "Setup:   $SETUP_PROMPT_FILE"
    echo "Prompt:  $PROMPT_FILE"
    [ $MAX_ITERATIONS -gt 0 ] && echo "Max:     $MAX_ITERATIONS iterations"
fi
echo "Branch:  $CURRENT_BRANCH"
echo "Verbose: $VERBOSE"
echo "Circuit Breaker: $MAX_CONSECUTIVE_FAILURES consecutive failures"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify prompt file(s) exist
if [ "$MODE" = "spec" ]; then
    # Spec mode uses its own set of prompt files
    for pf in "./.ralph/prompts/spec/research.md" "./.ralph/prompts/spec/draft.md" "./.ralph/prompts/spec/refine.md" "./.ralph/prompts/spec/review.md" "./.ralph/prompts/spec/review_fix.md" "./.ralph/prompts/spec/signoff.md"; do
        if [ ! -f "$pf" ]; then
            echo "Error: $pf not found (required for spec mode)"
            exit 1
        fi
    done
    # Verify spec_seed.md exists
    if [ ! -f "./.ralph/spec_seed.md" ]; then
        echo "Error: .ralph/spec_seed.md not found. Run the spec wizard first (node .ralph/run.js <name> spec)"
        exit 1
    fi
elif [ "$MODE" = "full" ]; then
    # Full mode uses multiple prompt files
    for pf in "./.ralph/prompts/plan.md" "./.ralph/prompts/build.md" "./.ralph/prompts/review/setup.md" "./.ralph/prompts/completion_check.md"; do
        if [ ! -f "$pf" ]; then
            echo "Error: $pf not found (required for full mode)"
            exit 1
        fi
    done
    # Check decomposition-specific prompts if manifest exists
    if [ -f "./.ralph/specs/${SPEC_NAME}/manifest.json" ]; then
        for pf in "./.ralph/prompts/spec_select.md" "./.ralph/prompts/master_completion_check.md"; do
            if [ ! -f "$pf" ]; then
                echo "Error: $pf not found (required for decomposed full mode)"
                exit 1
            fi
        done
    fi
    # Check for at least one review prompt (specialist or generic)
    if [ ! -f "./.ralph/prompts/review/qa.md" ] && [ ! -f "./.ralph/prompts/review/general.md" ]; then
        echo "Error: No review prompt found (need review/qa.md or review/general.md)"
        exit 1
    fi
    # Show which specialist prompts are available
    echo ""
    echo "Review specialists available:"
    [ -f "./.ralph/prompts/review/ux.md" ] && echo -e "  \033[1;35m✓\033[0m UX Expert (review/ux.md)"
    [ -f "./.ralph/prompts/review/db.md" ] && echo -e "  \033[1;36m✓\033[0m DB Expert (review/db.md)"
    [ -f "./.ralph/prompts/review/qa.md" ] && echo -e "  \033[1;33m✓\033[0m QA Expert (review/qa.md)"
    [ -f "./.ralph/prompts/review/security.md" ] && echo -e "  \033[1;31m✓\033[0m Security Expert (review/security.md)"
    [ -f "./.ralph/prompts/review/perf.md" ] && echo -e "  \033[1;32m✓\033[0m Performance Expert (review/perf.md)"
    [ -f "./.ralph/prompts/review/api.md" ] && echo -e "  \033[1;34m✓\033[0m API Expert (review/api.md)"
    [ -f "./.ralph/prompts/review/general.md" ] && echo -e "  \033[1;37m✓\033[0m General (review/general.md - fallback)"
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
node .ralph/run.js $SPEC_NAME $MODE
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

# Helper function to run a single iteration with a given prompt
run_single_iteration() {
    local prompt_file=$1
    local iteration_num=$2
    local phase_name=$3
    
    TURN_START_TIME=$(date +%s)
    
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
# Returns: ux, db, qa, security, perf, or api
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
    else
        echo "qa"
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
        check_result=$(cat "./.ralph/prompts/completion_check.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Checking if implementation is complete..."
        
        check_result=$(cat "./.ralph/prompts/completion_check.md" | claude -p \
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
    echo -e "\033[1;35m║  plan($FULL_PLAN_ITERS) → build($FULL_BUILD_ITERS) → review($FULL_REVIEW_ITERS) → fix($FULL_REVIEWFIX_ITERS) → check  ║\033[0m"
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
        select_result=$(cat "./.ralph/prompts/spec_select.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$select_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Selecting next sub-spec..."

        select_result=$(cat "./.ralph/prompts/spec_select.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$select_log")
    fi

    # Parse Claude's JSON response
    local json_text
    json_text=$(echo "$select_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$select_result"
    fi

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
        check_result=$(cat "./.ralph/prompts/master_completion_check.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Running master completion check..."

        check_result=$(cat "./.ralph/prompts/master_completion_check.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi

    # Parse Claude's JSON response
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi

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
        check_result=$(cat "./.ralph/prompts/spec/signoff.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Checking if spec is ready for implementation..."

        check_result=$(cat "./.ralph/prompts/spec/signoff.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi

    # Parse Claude's JSON response using jq
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi

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

        if ! run_single_iteration "./.ralph/prompts/spec/research.md" $TOTAL_ITERATIONS "RESEARCH ($RESEARCH_ITERATION/$SPEC_RESEARCH_ITERS)"; then
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

        if ! run_single_iteration "./.ralph/prompts/spec/draft.md" $TOTAL_ITERATIONS "DRAFT ($DRAFT_ITERATION/$SPEC_DRAFT_ITERS)"; then
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
            UNANSWERED=$(grep -c '^A:$\|^A: *$' "./.ralph/spec_questions.md" 2>/dev/null || echo "0")
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

        if ! run_single_iteration "./.ralph/prompts/spec/refine.md" $TOTAL_ITERATIONS "REFINE ($REFINE_ITERATION/$SPEC_REFINE_ITERS)"; then
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

        if ! run_single_iteration "./.ralph/prompts/spec/review.md" $TOTAL_ITERATIONS "SPEC REVIEW ($REVIEW_ITERATION/$SPEC_REVIEW_ITERS)"; then
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
        SPEC_FIX_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$SPEC_REVIEW_FILE" 2>/dev/null || echo "0")
        SPEC_FIX_ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$SPEC_REVIEW_FILE" 2>/dev/null || echo "0")
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

            if ! run_single_iteration "./.ralph/prompts/spec/review_fix.md" $TOTAL_ITERATIONS "SPEC REVIEW-FIX ($REVIEWFIX_ITERATION/$SPEC_REVIEWFIX_ITERS)"; then
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
            
            if ! run_single_iteration "./.ralph/prompts/plan.md" $TOTAL_ITERATIONS "PLAN ($PLAN_ITERATION/$FULL_PLAN_ITERS)"; then
                echo -e "  \033[1;31m✗\033[0m Claude error - checking circuit breaker"
                if check_circuit_breaker; then
                    PHASE_ERROR=true
                    break
                fi
            fi
            
            # Show progress
            PLAN_FILE="./.ralph/implementation_plan.md"
            if [ -f "$PLAN_FILE" ]; then
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null || echo "0")
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
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null || echo "0")
                if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                    echo -e "  \033[1;32m✓\033[0m All build tasks complete!"
                    break
                fi
                echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT unchecked items remaining"
            fi
            
            if ! run_single_iteration "./.ralph/prompts/build.md" $TOTAL_ITERATIONS "BUILD ($BUILD_ITERATION/$FULL_BUILD_ITERS)"; then
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
        
        # ─────────────────────────────────────────────────────────────────────
        # REVIEW PHASE (with setup on first iteration of each cycle)
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "REVIEW" $FULL_REVIEW_ITERS
        
        # Run review setup
        echo -e "  \033[1;35m⚙\033[0m  Running review setup..."
        SETUP_LOG_FILE="$TEMP_DIR/review_setup_cycle_${CYCLE}.log"
        
        if [ "$VERBOSE" = true ]; then
            cat "./.ralph/prompts/review/setup.md" | claude -p \
                --dangerously-skip-permissions \
                --output-format=stream-json \
                --verbose 2>&1 | tee "$SETUP_LOG_FILE"
        else
            cat "./.ralph/prompts/review/setup.md" | claude -p \
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
        while [ $REVIEW_ITERATION -lt $FULL_REVIEW_ITERS ]; do
            REVIEW_ITERATION=$((REVIEW_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
            
            # Check if review is complete before running
            CHECKLIST_FILE="./.ralph/review_checklist.md"
            if [ -f "$CHECKLIST_FILE" ]; then
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
                if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                    echo -e "  \033[1;32m✓\033[0m All review items complete!"
                    break
                fi
                
                # Count items by specialist type
                SEC_COUNT=$(grep -c '^\- \[ \].*\[SEC' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
                UX_COUNT=$(grep -c '^\- \[ \].*\[UX\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
                DB_COUNT=$(grep -c '^\- \[ \].*\[DB\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
                PERF_COUNT=$(grep -c '^\- \[ \].*\[PERF\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
                API_COUNT=$(grep -c '^\- \[ \].*\[API\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
                QA_COUNT=$((UNCHECKED_COUNT - SEC_COUNT - UX_COUNT - DB_COUNT - PERF_COUNT - API_COUNT))
                echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining: \033[1;31mSEC:$SEC_COUNT\033[0m \033[1;35mUX:$UX_COUNT\033[0m \033[1;36mDB:$DB_COUNT\033[0m \033[1;32mPERF:$PERF_COUNT\033[0m \033[1;34mAPI:$API_COUNT\033[0m \033[1;33mQA:$QA_COUNT\033[0m"
            fi
            
            # Determine which specialist should handle the next item
            SPECIALIST=$(get_next_review_specialist)
            case $SPECIALIST in
                security)
                    REVIEW_PROMPT="./.ralph/prompts/review/security.md"
                    SPECIALIST_NAME="Security"
                    SPECIALIST_COLOR="\033[1;31m"  # Red
                    ;;
                ux)
                    REVIEW_PROMPT="./.ralph/prompts/review/ux.md"
                    SPECIALIST_NAME="UX"
                    SPECIALIST_COLOR="\033[1;35m"  # Magenta
                    ;;
                db)
                    REVIEW_PROMPT="./.ralph/prompts/review/db.md"
                    SPECIALIST_NAME="DB"
                    SPECIALIST_COLOR="\033[1;36m"  # Cyan
                    ;;
                perf)
                    REVIEW_PROMPT="./.ralph/prompts/review/perf.md"
                    SPECIALIST_NAME="Performance"
                    SPECIALIST_COLOR="\033[1;32m"  # Green
                    ;;
                api)
                    REVIEW_PROMPT="./.ralph/prompts/review/api.md"
                    SPECIALIST_NAME="API"
                    SPECIALIST_COLOR="\033[1;34m"  # Blue
                    ;;
                *)
                    REVIEW_PROMPT="./.ralph/prompts/review/qa.md"
                    SPECIALIST_NAME="QA"
                    SPECIALIST_COLOR="\033[1;33m"  # Yellow
                    ;;
            esac

            # Fallback to generic review.md if specialist prompt doesn't exist
            if [ ! -f "$REVIEW_PROMPT" ]; then
                REVIEW_PROMPT="./.ralph/prompts/review/general.md"
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
        
        # Exit full mode on error
        if [ "$PHASE_ERROR" = true ]; then
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            echo -e "\033[1;31m  ❌ Full mode stopped due to circuit breaker\033[0m"
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            break
        fi
        
        echo -e "  \033[1;32m✓\033[0m Review phase complete"

        # ─────────────────────────────────────────────────────────────────────
        # REVIEW-FIX PHASE
        # ─────────────────────────────────────────────────────────────────────

        # Only run review-fix if review.md exists and has blocking/attention issues
        REVIEW_FILE="./.ralph/review.md"
        SHOULD_RUN_FIX=false
        if [ -f "$REVIEW_FILE" ]; then
            FIX_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null || echo "0")
            FIX_ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$REVIEW_FILE" 2>/dev/null || echo "0")
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
                    REMAINING_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null || echo "0")
                    REMAINING_ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$REVIEW_FILE" 2>/dev/null || echo "0")
                    if [ "$REMAINING_BLOCKING" -eq 0 ] && [ "$REMAINING_ATTENTION" -eq 0 ]; then
                        echo -e "  \033[1;32m✓\033[0m All review issues resolved!"
                        break
                    fi
                    echo -e "  \033[1;34mℹ\033[0m  Remaining: \033[1;31m❌ $REMAINING_BLOCKING\033[0m  \033[1;33m⚠️ $REMAINING_ATTENTION\033[0m"
                fi

                if ! run_single_iteration "./.ralph/prompts/review/fix.md" $TOTAL_ITERATIONS "REVIEW-FIX ($REVIEWFIX_ITERATION/$FULL_REVIEWFIX_ITERS)"; then
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
        else
            echo -e "  \033[1;32m✓\033[0m No blocking/attention issues — skipping review-fix"
        fi

        # ─────────────────────────────────────────────────────────────────────
        # COMPLETION CHECK
        # ─────────────────────────────────────────────────────────────────────
        if run_completion_check; then
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
            UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null || echo "0")
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
            UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
            if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                echo ""
                echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
                echo -e "\033[1;32m  ✅ Review complete! All items have been reviewed.\033[0m"
                echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
                echo ""
                break
            fi
            
            # Count items by specialist type
            SEC_COUNT=$(grep -c '^\- \[ \].*\[SEC' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
            UX_COUNT=$(grep -c '^\- \[ \].*\[UX\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
            DB_COUNT=$(grep -c '^\- \[ \].*\[DB\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
            PERF_COUNT=$(grep -c '^\- \[ \].*\[PERF\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
            API_COUNT=$(grep -c '^\- \[ \].*\[API\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
            QA_COUNT=$((UNCHECKED_COUNT - SEC_COUNT - UX_COUNT - DB_COUNT - PERF_COUNT - API_COUNT))
            echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining: \033[1;31mSEC:$SEC_COUNT\033[0m \033[1;35mUX:$UX_COUNT\033[0m \033[1;36mDB:$DB_COUNT\033[0m \033[1;32mPERF:$PERF_COUNT\033[0m \033[1;34mAPI:$API_COUNT\033[0m \033[1;33mQA:$QA_COUNT\033[0m"
            
            # Determine which specialist should handle the next item
            SPECIALIST=$(get_next_review_specialist)
            case $SPECIALIST in
                security)
                    PROMPT_FILE="./.ralph/prompts/review/security.md"
                    echo -e "  \033[1;31m🔍 Specialist: Security Expert\033[0m"
                    ;;
                ux)
                    PROMPT_FILE="./.ralph/prompts/review/ux.md"
                    echo -e "  \033[1;35m🔍 Specialist: UX Expert\033[0m"
                    ;;
                db)
                    PROMPT_FILE="./.ralph/prompts/review/db.md"
                    echo -e "  \033[1;36m🔍 Specialist: DB Expert\033[0m"
                    ;;
                perf)
                    PROMPT_FILE="./.ralph/prompts/review/perf.md"
                    echo -e "  \033[1;32m🔍 Specialist: Performance Expert\033[0m"
                    ;;
                api)
                    PROMPT_FILE="./.ralph/prompts/review/api.md"
                    echo -e "  \033[1;34m🔍 Specialist: API Expert\033[0m"
                    ;;
                *)
                    PROMPT_FILE="./.ralph/prompts/review/qa.md"
                    echo -e "  \033[1;33m🔍 Specialist: QA Expert\033[0m"
                    ;;
            esac

            # Fallback to generic review.md if specialist prompt doesn't exist
            if [ ! -f "$PROMPT_FILE" ]; then
                PROMPT_FILE="./.ralph/prompts/review/general.md"
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
            BLOCKING_COUNT=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null || echo "0")
            ATTENTION_COUNT=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$REVIEW_FILE" 2>/dev/null || echo "0")
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
