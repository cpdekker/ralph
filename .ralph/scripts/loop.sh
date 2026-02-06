#!/bin/bash
# Ralph Wiggum - Main Loop Script
#
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

# ═══════════════════════════════════════════════════════════════════════════════
# Resolve script directory and source library modules
# ═══════════════════════════════════════════════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/display.sh"
source "$SCRIPT_DIR/lib/checkpoint.sh"
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/review.sh"
source "$SCRIPT_DIR/lib/decompose.sh"
source "$SCRIPT_DIR/lib/spec_mode.sh"
source "$SCRIPT_DIR/lib/full_mode.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════════════════════
# SPEC FILE SETUP
# ═══════════════════════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════════════════════
# MODE DEFAULTS
# ═══════════════════════════════════════════════════════════════════════════════

MAX_CONSECUTIVE_FAILURES=${MAX_CONSECUTIVE_FAILURES:-3}
CONSECUTIVE_FAILURES=0
STATE_FILE="./.ralph/state.json"

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
    PROMPT_FILE="./.ralph/prompts/build.md"
    MAX_ITERATIONS=1
    VERBOSE=true
    NO_COMMIT=true
elif [ "$MODE" = "decompose" ]; then
    PROMPT_FILE="./.ralph/prompts/decompose.md"
    MAX_ITERATIONS=1
    VERBOSE=true
elif [ "$MODE" = "spec" ]; then
    MAX_ITERATIONS=${MAX_ITERATIONS:-8}
    SPEC_RESEARCH_ITERS=1
    SPEC_DRAFT_ITERS=1
    SPEC_REFINE_ITERS=${SPEC_REFINE_ITERS:-3}
    SPEC_REVIEW_ITERS=${SPEC_REVIEW_ITERS:-1}
    SPEC_REVIEWFIX_ITERS=${SPEC_REVIEWFIX_ITERS:-1}
elif [ "$MODE" = "full" ]; then
    MAX_ITERATIONS=${MAX_ITERATIONS:-100}
    FULL_PLAN_ITERS=${FULL_PLAN_ITERS:-5}
    FULL_BUILD_ITERS=${FULL_BUILD_ITERS:-10}
    FULL_REVIEW_ITERS=${FULL_REVIEW_ITERS:-15}
    FULL_REVIEWFIX_ITERS=${FULL_REVIEWFIX_ITERS:-5}
else
    MODE="build"
    PROMPT_FILE="./.ralph/prompts/build.md"
    MAX_ITERATIONS=${MAX_ITERATIONS:-10}
fi

ITERATION=0

# ═══════════════════════════════════════════════════════════════════════════════
# BRANCH SETUP
# ═══════════════════════════════════════════════════════════════════════════════

TARGET_BRANCH="ralph/$SPEC_NAME"
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]; then
    echo "Current branch '$CURRENT_BRANCH' does not match target '$TARGET_BRANCH'"

    if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
        echo "Switching to existing branch: $TARGET_BRANCH"
        git checkout "$TARGET_BRANCH"
    else
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

# ═══════════════════════════════════════════════════════════════════════════════
# STARTUP DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════════════════════
# PROMPT FILE VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

if [ "$MODE" = "spec" ]; then
    for pf in "./.ralph/prompts/spec/research.md" "./.ralph/prompts/spec/draft.md" "./.ralph/prompts/spec/refine.md" "./.ralph/prompts/spec/review.md" "./.ralph/prompts/spec/review_fix.md" "./.ralph/prompts/spec/signoff.md"; do
        if [ ! -f "$pf" ]; then
            echo "Error: $pf not found (required for spec mode)"
            exit 1
        fi
    done
    if [ ! -f "./.ralph/spec_seed.md" ]; then
        echo "Error: .ralph/spec_seed.md not found. Run the spec wizard first (node .ralph/run.js <name> spec)"
        exit 1
    fi
elif [ "$MODE" = "full" ]; then
    for pf in "./.ralph/prompts/plan.md" "./.ralph/prompts/build.md" "./.ralph/prompts/review/setup.md" "./.ralph/prompts/completion_check.md"; do
        if [ ! -f "$pf" ]; then
            echo "Error: $pf not found (required for full mode)"
            exit 1
        fi
    done
    if [ -f "./.ralph/specs/${SPEC_NAME}/manifest.json" ]; then
        for pf in "./.ralph/prompts/spec_select.md" "./.ralph/prompts/master_completion_check.md"; do
            if [ ! -f "$pf" ]; then
                echo "Error: $pf not found (required for decomposed full mode)"
                exit 1
            fi
        done
    fi
    if [ ! -f "./.ralph/prompts/review/qa.md" ] && [ ! -f "./.ralph/prompts/review/general.md" ]; then
        echo "Error: No review prompt found (need review/qa.md or review/general.md)"
        exit 1
    fi
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

# ═══════════════════════════════════════════════════════════════════════════════
# AUTHENTICATION CHECK
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "Verifying Claude CLI authentication..."
if ! claude -p --output-format json <<< "Reply with only the word 'ok'" > /dev/null 2>&1; then
    echo ""
    echo -e "\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;31m  ERROR: Claude CLI authentication failed\033[0m"
    echo -e "\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    echo "  Possible causes:"
    echo "    • API credentials are missing, invalid, or expired"
    echo "    • Network connectivity issues"
    echo ""
    echo "  Check your .ralph/.env file and ensure your API provider is configured."
    echo "  See .ralph/.env.example for supported providers (Anthropic API, AWS Bedrock, Google Vertex)."
    echo ""
    exit 1
fi
echo -e "\033[1;32m✓ Claude CLI authenticated successfully\033[0m"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

LOOP_START_TIME=$(date +%s)
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

# ═══════════════════════════════════════════════════════════════════════════════
# MODE DISPATCH
# ═══════════════════════════════════════════════════════════════════════════════

if [ "$MODE" = "spec" ]; then
    run_spec_mode
    exit 0
fi

if [ "$MODE" = "full" ]; then
    run_full_mode
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STANDARD MODE - Runs single mode (plan, build, review, review-fix, debug, decompose)
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
    if [ "$VERBOSE" = true ]; then
        cat "$PROMPT_FILE" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose 2>&1 | tee "$LOG_FILE"
        CLAUDE_EXIT=${PIPESTATUS[1]}
    else
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
        CONSECUTIVE_FAILURES=0
    fi

    # Generate and display summary
    generate_summary "$LOG_FILE" "$ITERATION" "$TURN_START_TIME"

    # Skip commit/push in debug mode
    if [ "${NO_COMMIT:-false}" = true ]; then
        echo -e "  \033[1;33m⚠️  DEBUG MODE - Skipping commit and push\033[0m"
        break
    fi

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }

    # Update checkpoint
    save_state "$MODE" "$ITERATION" "Completed"
done

# ═══════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

FINAL_ELAPSED=$(($(date +%s) - LOOP_START_TIME))
FINAL_FORMATTED=$(format_duration $FINAL_ELAPSED)
COMPLETED_ITERATIONS=$((ITERATION - 1))

rm -f "$STATE_FILE"

echo ""
echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  Ralph completed $COMPLETED_ITERATIONS iteration(s) in $FINAL_FORMATTED\033[0m"
echo -e "\033[1;32m  Errors: $ERROR_COUNT\033[0m"
echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
echo ""
