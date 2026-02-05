#!/bin/bash
# Usage: ./loop.sh <spec-name> [plan|build|review|full] [max_iterations] [--verbose]
# Examples:
#   ./loop.sh my-feature                    # Build mode, 10 iterations, quiet
#   ./loop.sh my-feature plan               # Plan mode, 5 iterations, quiet
#   ./loop.sh my-feature build 20           # Build mode, 20 iterations, quiet
#   ./loop.sh my-feature review             # Review mode, 10 iterations, quiet
#   ./loop.sh my-feature plan 10 --verbose  # Plan mode, 10 iterations, verbose
#   ./loop.sh my-feature full               # Full mode: plan→build→review→check cycles
#   ./loop.sh my-feature full 100           # Full mode with max 100 total iterations
#
# Full mode options (via environment variables):
#   FULL_PLAN_ITERS=5       # Plan iterations per cycle (default: 5)
#   FULL_BUILD_ITERS=10     # Build iterations per cycle (default: 10)
#   FULL_REVIEW_ITERS=5     # Review iterations per cycle (default: 5)

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
    elif [ -z "$MODE" ] && ([ "$arg" = "plan" ] || [ "$arg" = "build" ] || [ "$arg" = "review" ] || [ "$arg" = "full" ]); then
        MODE="$arg"
    elif [ -z "$MAX_ITERATIONS" ] && [[ "$arg" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$arg"
    fi
done

# First argument is required: spec name
if [ -z "$SPEC_NAME" ]; then
    echo "Error: Spec name is required"
    echo "Usage: ./loop.sh <spec-name> [plan|build|review] [max_iterations] [--verbose]"
    exit 1
fi

# Verify spec file exists
SPEC_FILE="./.ralph/specs/${SPEC_NAME}.md"
if [ ! -f "$SPEC_FILE" ]; then
    echo "Error: Spec file not found: $SPEC_FILE"
    echo "Available specs:"
    ls -1 ./.ralph/specs/*.md 2>/dev/null | grep -v active.md | xargs -I {} basename {} .md | sed 's/^/  - /'
    exit 1
fi

# Copy spec to active.md
ACTIVE_SPEC="./.ralph/specs/active.md"
echo "Copying $SPEC_FILE to $ACTIVE_SPEC"
cp "$SPEC_FILE" "$ACTIVE_SPEC"

# Set defaults based on mode
if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="./.ralph/prompts/plan.md"
    MAX_ITERATIONS=${MAX_ITERATIONS:-5}
elif [ "$MODE" = "review" ]; then
    SETUP_PROMPT_FILE="./.ralph/prompts/review_setup.md"
    PROMPT_FILE="./.ralph/prompts/review.md"
    MAX_ITERATIONS=${MAX_ITERATIONS:-10}
elif [ "$MODE" = "full" ]; then
    # Full mode: cycles of plan → build → review → completion check
    MAX_ITERATIONS=${MAX_ITERATIONS:-100}
    FULL_PLAN_ITERS=${FULL_PLAN_ITERS:-5}
    FULL_BUILD_ITERS=${FULL_BUILD_ITERS:-10}
    FULL_REVIEW_ITERS=${FULL_REVIEW_ITERS:-15}  # More iterations to cover all review items
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
if [ "$MODE" = "full" ]; then
    echo "Cycle:   plan($FULL_PLAN_ITERS) → build($FULL_BUILD_ITERS) → review($FULL_REVIEW_ITERS) → check"
    [ $MAX_ITERATIONS -gt 0 ] && echo "Max:     $MAX_ITERATIONS cycles"
else
    [ -n "$SETUP_PROMPT_FILE" ] && echo "Setup:   $SETUP_PROMPT_FILE"
    echo "Prompt:  $PROMPT_FILE"
    [ $MAX_ITERATIONS -gt 0 ] && echo "Max:     $MAX_ITERATIONS iterations"
fi
echo "Branch:  $CURRENT_BRANCH"
echo "Verbose: $VERBOSE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify prompt file(s) exist
if [ "$MODE" = "full" ]; then
    # Full mode uses multiple prompt files
    for pf in "./.ralph/prompts/plan.md" "./.ralph/prompts/build.md" "./.ralph/prompts/review_setup.md" "./.ralph/prompts/completion_check.md"; do
        if [ ! -f "$pf" ]; then
            echo "Error: $pf not found (required for full mode)"
            exit 1
        fi
    done
    # Check for at least one review prompt (specialist or generic)
    if [ ! -f "./.ralph/prompts/review_qa.md" ] && [ ! -f "./.ralph/prompts/review.md" ]; then
        echo "Error: No review prompt found (need review_qa.md or review.md)"
        exit 1
    fi
    # Show which specialist prompts are available
    echo ""
    echo "Review specialists available:"
    [ -f "./.ralph/prompts/review_ux.md" ] && echo -e "  \033[1;35m✓\033[0m UX Expert (review_ux.md)"
    [ -f "./.ralph/prompts/review_db.md" ] && echo -e "  \033[1;36m✓\033[0m DB Expert (review_db.md)"
    [ -f "./.ralph/prompts/review_qa.md" ] && echo -e "  \033[1;33m✓\033[0m QA Expert (review_qa.md)"
    [ -f "./.ralph/prompts/review.md" ] && echo -e "  \033[1;37m✓\033[0m General (review.md - fallback)"
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
            return 1
        else
            echo -e "  \033[1;32m✓\033[0m Claude iteration completed"
        fi
    fi
    
    # Generate and display summary
    generate_summary "$LOG_FILE" "$iteration_num" "$TURN_START_TIME"
    
    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }
    
    return 0
}

# Helper function to determine which review specialist to use
# Returns: ux, db, or qa
get_next_review_specialist() {
    local checklist_file="./.ralph/review_checklist.md"
    
    if [ ! -f "$checklist_file" ]; then
        echo "qa"
        return
    fi
    
    # Find the first unchecked item and check its tag
    local next_item=$(grep -m1 '^\- \[ \]' "$checklist_file" 2>/dev/null || echo "")
    
    if echo "$next_item" | grep -qi '\[UX\]'; then
        echo "ux"
    elif echo "$next_item" | grep -qi '\[DB\]'; then
        echo "db"
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
    
    # Extract the result text from Claude's JSON response
    local result_text=$(echo "$check_result" | grep -o '"result"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"result"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/')
    
    # If we couldn't extract from result field, try to find JSON in the response
    if [ -z "$result_text" ]; then
        result_text="$check_result"
    fi
    
    # Check if the response indicates completion
    if echo "$result_text" | grep -qi '"complete"[[:space:]]*:[[:space:]]*true'; then
        local reason=$(echo "$result_text" | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"reason"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/')
        echo ""
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        echo -e "\033[1;32m  ✅ IMPLEMENTATION COMPLETE!\033[0m"
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        [ -n "$reason" ] && echo -e "  \033[1;36m$reason\033[0m"
        echo ""
        return 0  # Complete
    else
        local reason=$(echo "$result_text" | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/"reason"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/')
        echo ""
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        echo -e "\033[1;33m  ⚠ Implementation not yet complete\033[0m"
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        [ -n "$reason" ] && echo -e "  \033[1;36m$reason\033[0m"
        echo ""
        return 1  # Not complete
    fi
}

# Print cycle banner
print_cycle_banner() {
    local cycle_num=$1
    echo ""
    echo ""
    echo -e "\033[1;35m╔════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║                      CYCLE $cycle_num                              ║\033[0m"
    echo -e "\033[1;35m╠════════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;35m║  plan($FULL_PLAN_ITERS) → build($FULL_BUILD_ITERS) → review($FULL_REVIEW_ITERS) → check            ║\033[0m"
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
# FULL MODE - Runs plan → build → review → check cycles
# In full mode, MAX_ITERATIONS is treated as MAX_CYCLES (number of complete cycles)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$MODE" = "full" ]; then
    TOTAL_ITERATIONS=0
    CYCLE=0
    MAX_CYCLES=$MAX_ITERATIONS  # Rename for clarity - in full mode, this is cycles not iterations
    IMPLEMENTATION_COMPLETE=false
    
    while [ "$IMPLEMENTATION_COMPLETE" = false ]; do
        CYCLE=$((CYCLE + 1))
        
        # Check max cycles at the start of each cycle
        if [ $CYCLE -gt $MAX_CYCLES ]; then
            echo -e "\033[1;33mReached max cycles: $MAX_CYCLES\033[0m"
            break
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
                echo -e "  \033[1;31m✗\033[0m Claude error - stopping full mode"
                PHASE_ERROR=true
                break
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
            echo -e "\033[1;31m  ❌ Full mode stopped due to Claude error\033[0m"
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
                echo -e "  \033[1;31m✗\033[0m Claude error - stopping full mode"
                PHASE_ERROR=true
                break
            fi
        done
        
        # Exit full mode on error
        if [ "$PHASE_ERROR" = true ]; then
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            echo -e "\033[1;31m  ❌ Full mode stopped due to Claude error\033[0m"
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
            cat "./.ralph/prompts/review_setup.md" | claude -p \
                --dangerously-skip-permissions \
                --output-format=stream-json \
                --verbose 2>&1 | tee "$SETUP_LOG_FILE"
        else
            cat "./.ralph/prompts/review_setup.md" | claude -p \
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
                UX_COUNT=$(grep -c '^\- \[ \].*\[UX\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
                DB_COUNT=$(grep -c '^\- \[ \].*\[DB\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
                QA_COUNT=$((UNCHECKED_COUNT - UX_COUNT - DB_COUNT))
                echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining: \033[1;35mUX:$UX_COUNT\033[0m \033[1;36mDB:$DB_COUNT\033[0m \033[1;33mQA:$QA_COUNT\033[0m"
            fi
            
            # Determine which specialist should handle the next item
            SPECIALIST=$(get_next_review_specialist)
            case $SPECIALIST in
                ux)
                    REVIEW_PROMPT="./.ralph/prompts/review_ux.md"
                    SPECIALIST_NAME="UX"
                    SPECIALIST_COLOR="\033[1;35m"  # Magenta
                    ;;
                db)
                    REVIEW_PROMPT="./.ralph/prompts/review_db.md"
                    SPECIALIST_NAME="DB"
                    SPECIALIST_COLOR="\033[1;36m"  # Cyan
                    ;;
                *)
                    REVIEW_PROMPT="./.ralph/prompts/review_qa.md"
                    SPECIALIST_NAME="QA"
                    SPECIALIST_COLOR="\033[1;33m"  # Yellow
                    ;;
            esac
            
            # Fallback to generic review.md if specialist prompt doesn't exist
            if [ ! -f "$REVIEW_PROMPT" ]; then
                REVIEW_PROMPT="./.ralph/prompts/review.md"
                SPECIALIST_NAME="General"
                SPECIALIST_COLOR="\033[1;37m"
            fi
            
            echo -e "  ${SPECIALIST_COLOR}🔍 Specialist: $SPECIALIST_NAME\033[0m"
            
            if ! run_single_iteration "$REVIEW_PROMPT" $TOTAL_ITERATIONS "REVIEW-$SPECIALIST_NAME ($REVIEW_ITERATION/$FULL_REVIEW_ITERS)"; then
                echo -e "  \033[1;31m✗\033[0m Claude error - stopping full mode"
                PHASE_ERROR=true
                break
            fi
        done
        
        # Exit full mode on error
        if [ "$PHASE_ERROR" = true ]; then
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            echo -e "\033[1;31m  ❌ Full mode stopped due to Claude error\033[0m"
            echo -e "\033[1;31m════════════════════════════════════════════════════════════\033[0m"
            break
        fi
        
        echo -e "  \033[1;32m✓\033[0m Review phase complete"
        
        # ─────────────────────────────────────────────────────────────────────
        # COMPLETION CHECK
        # ─────────────────────────────────────────────────────────────────────
        if run_completion_check; then
            IMPLEMENTATION_COMPLETE=true
        else
            echo -e "  \033[1;35m→\033[0m Starting next cycle..."
        fi
    done
    
    # Calculate final total elapsed time
    FINAL_ELAPSED=$(($(date +%s) - LOOP_START_TIME))
    FINAL_FORMATTED=$(format_duration $FINAL_ELAPSED)
    
    echo ""
    echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
    if [ "$IMPLEMENTATION_COMPLETE" = true ]; then
        echo -e "\033[1;32m  🎉 Ralph completed spec in $CYCLE cycle(s), $TOTAL_ITERATIONS iteration(s)\033[0m"
    else
        echo -e "\033[1;33m  ⚠ Ralph stopped after $CYCLE cycle(s), $TOTAL_ITERATIONS iteration(s)\033[0m"
    fi
    echo -e "\033[1;32m  Total time: $FINAL_FORMATTED\033[0m"
    echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
    echo ""
    
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STANDARD MODE - Runs single mode (plan, build, or review)
# ═══════════════════════════════════════════════════════════════════════════════

while true; do
    ITERATION=$((ITERATION + 1))
    TURN_START_TIME=$(date +%s)
    
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -gt $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
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
            UX_COUNT=$(grep -c '^\- \[ \].*\[UX\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
            DB_COUNT=$(grep -c '^\- \[ \].*\[DB\]' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
            QA_COUNT=$((UNCHECKED_COUNT - UX_COUNT - DB_COUNT))
            echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining: \033[1;35mUX:$UX_COUNT\033[0m \033[1;36mDB:$DB_COUNT\033[0m \033[1;33mQA:$QA_COUNT\033[0m"
            
            # Determine which specialist should handle the next item
            SPECIALIST=$(get_next_review_specialist)
            case $SPECIALIST in
                ux)
                    PROMPT_FILE="./.ralph/prompts/review_ux.md"
                    echo -e "  \033[1;35m🔍 Specialist: UX Expert\033[0m"
                    ;;
                db)
                    PROMPT_FILE="./.ralph/prompts/review_db.md"
                    echo -e "  \033[1;36m🔍 Specialist: DB Expert\033[0m"
                    ;;
                *)
                    PROMPT_FILE="./.ralph/prompts/review_qa.md"
                    echo -e "  \033[1;33m🔍 Specialist: QA Expert\033[0m"
                    ;;
            esac
            
            # Fallback to generic review.md if specialist prompt doesn't exist
            if [ ! -f "$PROMPT_FILE" ]; then
                PROMPT_FILE="./.ralph/prompts/review.md"
                echo -e "  \033[1;37m🔍 Specialist: General\033[0m"
            fi
        else
            echo -e "  \033[1;31m✗\033[0m  Review checklist not found. Run setup first."
            break
        fi
    fi

    # Display turn banner
    print_turn_banner $ITERATION

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
        
        if [ $CLAUDE_EXIT -ne 0 ]; then
            echo -e "  \033[1;31m✗\033[0m Claude exited with code $CLAUDE_EXIT"
            echo "  Check log: $LOG_FILE"
        else
            echo -e "  \033[1;32m✓\033[0m Claude iteration completed"
        fi
    fi

    # Generate and display summary
    generate_summary "$LOG_FILE" "$ITERATION" "$TURN_START_TIME"

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }
done

# Calculate final total elapsed time
FINAL_ELAPSED=$(($(date +%s) - LOOP_START_TIME))
FINAL_FORMATTED=$(format_duration $FINAL_ELAPSED)
COMPLETED_ITERATIONS=$((ITERATION - 1))

echo ""
echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  Ralph completed $COMPLETED_ITERATIONS iteration(s) in $FINAL_FORMATTED\033[0m"
echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
echo ""
