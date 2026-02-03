#!/bin/bash
# Usage: ./loop.sh <spec-name> [plan|build|review] [max_iterations] [--verbose]
# Examples:
#   ./loop.sh my-feature                    # Build mode, 10 iterations, quiet
#   ./loop.sh my-feature plan               # Plan mode, 5 iterations, quiet
#   ./loop.sh my-feature build 20           # Build mode, 20 iterations, quiet
#   ./loop.sh my-feature review             # Review mode, 10 iterations, quiet
#   ./loop.sh my-feature plan 10 --verbose  # Plan mode, 10 iterations, verbose

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
    elif [ -z "$MODE" ] && ([ "$arg" = "plan" ] || [ "$arg" = "build" ] || [ "$arg" = "review" ]); then
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
[ -n "$SETUP_PROMPT_FILE" ] && echo "Setup:   $SETUP_PROMPT_FILE"
echo "Prompt:  $PROMPT_FILE"
echo "Branch:  $CURRENT_BRANCH"
echo "Verbose: $VERBOSE"
[ $MAX_ITERATIONS -gt 0 ] && echo "Max:     $MAX_ITERATIONS iterations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify prompt file(s) exist
if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: $PROMPT_FILE not found"
    exit 1
fi

if [ -n "$SETUP_PROMPT_FILE" ] && [ ! -f "$SETUP_PROMPT_FILE" ]; then
    echo "Error: $SETUP_PROMPT_FILE not found"
    exit 1
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
            echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining to review"
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
