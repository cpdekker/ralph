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
#   FULL_DISTILL_ITERS=1    # Distill iterations per cycle (default: 1)
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
    FULL_DISTILL_ITERS=${FULL_DISTILL_ITERS:-1}
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

ralph_header "Ralph Session"
echo -e "${C_MUTED}  spec${C_RESET}      $SPEC_NAME"
echo -e "${C_MUTED}  mode${C_RESET}      $MODE"
if [ "$MODE" = "spec" ]; then
    echo -e "${C_MUTED}  phases${C_RESET}    research($SPEC_RESEARCH_ITERS) → draft($SPEC_DRAFT_ITERS) → refine($SPEC_REFINE_ITERS) → review($SPEC_REVIEW_ITERS) → fix($SPEC_REVIEWFIX_ITERS) → signoff"
elif [ "$MODE" = "decompose" ]; then
    echo -e "${C_MUTED}  action${C_RESET}    Decompose spec into sub-specs"
elif [ "$MODE" = "full" ]; then
    echo -e "${C_MUTED}  cycle${C_RESET}     plan($FULL_PLAN_ITERS) → build($FULL_BUILD_ITERS) → review($FULL_REVIEW_ITERS) → fix($FULL_REVIEWFIX_ITERS) → distill($FULL_DISTILL_ITERS) → check"
    [ $MAX_ITERATIONS -gt 0 ] && echo -e "${C_MUTED}  max${C_RESET}       $MAX_ITERATIONS cycles"
elif [ "$MODE" = "debug" ]; then
    ralph_warn "DEBUG MODE - No commits will be made"
else
    [ -n "$SETUP_PROMPT_FILE" ] && echo -e "${C_MUTED}  setup${C_RESET}     $SETUP_PROMPT_FILE"
    echo -e "${C_MUTED}  prompt${C_RESET}    $PROMPT_FILE"
    [ $MAX_ITERATIONS -gt 0 ] && echo -e "${C_MUTED}  max${C_RESET}       $MAX_ITERATIONS iterations"
fi
echo -e "${C_MUTED}  branch${C_RESET}    $CURRENT_BRANCH"
echo -e "${C_MUTED}  verbose${C_RESET}   $VERBOSE"
echo -e "${C_MUTED}  breaker${C_RESET}   $MAX_CONSECUTIVE_FAILURES consecutive failures"
ralph_separator

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
    for pf in "./.ralph/prompts/plan.md" "./.ralph/prompts/build.md" "./.ralph/prompts/review/setup.md" "./.ralph/prompts/distill.md" "./.ralph/prompts/completion_check.md"; do
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
    ralph_header "Review Specialists"
    [ -f "./.ralph/prompts/review/ux.md" ] && echo -e "  ${C_UX}✓${C_RESET} UX Expert (review/ux.md)"
    [ -f "./.ralph/prompts/review/db.md" ] && echo -e "  ${C_DB}✓${C_RESET} DB Expert (review/db.md)"
    [ -f "./.ralph/prompts/review/qa.md" ] && echo -e "  ${C_QA}✓${C_RESET} QA Expert (review/qa.md)"
    [ -f "./.ralph/prompts/review/security.md" ] && echo -e "  ${C_SEC}✓${C_RESET} Security Expert (review/security.md)"
    [ -f "./.ralph/prompts/review/perf.md" ] && echo -e "  ${C_PERF}✓${C_RESET} Performance Expert (review/perf.md)"
    [ -f "./.ralph/prompts/review/api.md" ] && echo -e "  ${C_API}✓${C_RESET} API Expert (review/api.md)"
    [ -f "./.ralph/prompts/review/general.md" ] && echo -e "  ${C_HIGHLIGHT}✓${C_RESET} General (review/general.md - fallback)"
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
ralph_info "Verifying Claude CLI authentication..."
if ! claude -p --output-format json <<< "Reply with only the word 'ok'" > /dev/null 2>&1; then
    echo ""
    echo -e "${C_ERROR}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_ERROR}  ERROR: Claude CLI authentication failed${C_RESET}"
    echo -e "${C_ERROR}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
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
ralph_success "Claude CLI authenticated successfully"
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

# Initialize cross-iteration memory
append_progress "session_start" "spec=$SPEC_NAME mode=$MODE max_iters=$MAX_ITERATIONS"
init_guardrails

# Check for existing checkpoint
if load_state; then
    echo -e "${C_PRIMARY}ℹ️  Previous session state found. Continuing from checkpoint.${C_RESET}"
    echo ""
fi

# Run setup prompt if defined (for review mode)
if [ -n "$SETUP_PROMPT_FILE" ]; then
    ralph_header "Setup Phase"

    SETUP_LOG_FILE="$TEMP_DIR/setup.log"

    if [ "$VERBOSE" = true ]; then
        cat "$SETUP_PROMPT_FILE" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose 2>&1 | tee "$SETUP_LOG_FILE"
    else
        cat "$SETUP_PROMPT_FILE" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose > "$SETUP_LOG_FILE" 2>&1 &

        SETUP_PID=$!
        spin $SETUP_PID "Running setup phase..."
        wait $SETUP_PID
        SETUP_EXIT=$?

        if [ $SETUP_EXIT -ne 0 ]; then
            ralph_error "Setup phase failed with code $SETUP_EXIT"
            echo "  Check log: $SETUP_LOG_FILE"
            exit 1
        else
            ralph_success "Setup phase completed"
        fi
    fi

    # Stage cross-iteration memory files and push setup changes
    stage_ralph_memory
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }

    ralph_header "Setup Complete — Starting Review Loop"
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
            UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
            if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                echo ""
                echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
                echo -e "${C_SUCCESS}  All tasks complete! No unchecked items remaining.${C_RESET}"
                echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
                echo ""
                break
            fi
            ralph_info "$UNCHECKED_COUNT unchecked items remaining"
        fi
    elif [ "$MODE" = "review" ]; then
        CHECKLIST_FILE="./.ralph/review_checklist.md"
        if [ -f "$CHECKLIST_FILE" ]; then
            UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$CHECKLIST_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
            if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                echo ""
                echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
                echo -e "${C_SUCCESS}  Review complete! All items have been reviewed.${C_RESET}"
                echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
                echo ""
                break
            fi

            # Count items by specialist type
            SEC_COUNT=$(grep -c '^\- \[ \].*\[SEC' "$CHECKLIST_FILE" 2>/dev/null) || SEC_COUNT=0
            UX_COUNT=$(grep -c '^\- \[ \].*\[UX\]' "$CHECKLIST_FILE" 2>/dev/null) || UX_COUNT=0
            DB_COUNT=$(grep -c '^\- \[ \].*\[DB\]' "$CHECKLIST_FILE" 2>/dev/null) || DB_COUNT=0
            PERF_COUNT=$(grep -c '^\- \[ \].*\[PERF\]' "$CHECKLIST_FILE" 2>/dev/null) || PERF_COUNT=0
            API_COUNT=$(grep -c '^\- \[ \].*\[API\]' "$CHECKLIST_FILE" 2>/dev/null) || API_COUNT=0
            QA_COUNT=$((UNCHECKED_COUNT - SEC_COUNT - UX_COUNT - DB_COUNT - PERF_COUNT - API_COUNT))
            echo -e "  ${C_API}ℹ${C_RESET}  $UNCHECKED_COUNT items remaining: ${C_SEC}SEC:$SEC_COUNT${C_RESET} ${C_UX}UX:$UX_COUNT${C_RESET} ${C_DB}DB:$DB_COUNT${C_RESET} ${C_PERF}PERF:$PERF_COUNT${C_RESET} ${C_API}API:$API_COUNT${C_RESET} ${C_QA}QA:$QA_COUNT${C_RESET}"

            # Determine which specialist should handle the next item
            SPECIALIST=$(get_next_review_specialist)
            case $SPECIALIST in
                security)
                    PROMPT_FILE="./.ralph/prompts/review/security.md"
                    echo -e "  ${C_SEC}🔍 Specialist: Security Expert${C_RESET}"
                    ;;
                ux)
                    PROMPT_FILE="./.ralph/prompts/review/ux.md"
                    echo -e "  ${C_UX}🔍 Specialist: UX Expert${C_RESET}"
                    ;;
                db)
                    PROMPT_FILE="./.ralph/prompts/review/db.md"
                    echo -e "  ${C_DB}🔍 Specialist: DB Expert${C_RESET}"
                    ;;
                perf)
                    PROMPT_FILE="./.ralph/prompts/review/perf.md"
                    echo -e "  ${C_PERF}🔍 Specialist: Performance Expert${C_RESET}"
                    ;;
                api)
                    PROMPT_FILE="./.ralph/prompts/review/api.md"
                    echo -e "  ${C_API}🔍 Specialist: API Expert${C_RESET}"
                    ;;
                *)
                    PROMPT_FILE="./.ralph/prompts/review/qa.md"
                    echo -e "  ${C_QA}🔍 Specialist: QA Expert${C_RESET}"
                    ;;
            esac

            # Fallback to generic review.md if specialist prompt doesn't exist
            if [ ! -f "$PROMPT_FILE" ]; then
                PROMPT_FILE="./.ralph/prompts/review/general.md"
                echo -e "  ${C_HIGHLIGHT}🔍 Specialist: General${C_RESET}"
            fi
        else
            ralph_error "Review checklist not found. Run setup first."
            break
        fi
    elif [ "$MODE" = "review-fix" ]; then
        REVIEW_FILE="./.ralph/review.md"
        if [ -f "$REVIEW_FILE" ]; then
            BLOCKING_COUNT=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null) || BLOCKING_COUNT=0
            ATTENTION_COUNT=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$REVIEW_FILE" 2>/dev/null) || ATTENTION_COUNT=0
            if [ "$BLOCKING_COUNT" -eq 0 ] && [ "$ATTENTION_COUNT" -eq 0 ]; then
                echo ""
                echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
                echo -e "${C_SUCCESS}  All review issues resolved!${C_RESET}"
                echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
                echo ""
                break
            fi
            echo -e "  ${C_API}ℹ${C_RESET}  Issues remaining: ${C_ERROR}❌ Blocking: $BLOCKING_COUNT${C_RESET}  ${C_WARNING}⚠️ Attention: $ATTENTION_COUNT${C_RESET}"
        else
            ralph_error "Review file not found. Run review mode first."
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
        cat "$PROMPT_FILE" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose > "$LOG_FILE" 2>&1 &

        CLAUDE_PID=$!
        spin $CLAUDE_PID "Running Claude iteration $ITERATION..."
        wait $CLAUDE_PID
        CLAUDE_EXIT=$?
    fi

    if [ $CLAUDE_EXIT -ne 0 ]; then
        ralph_error "Claude exited with code $CLAUDE_EXIT"
        echo "  Check log: $LOG_FILE"
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        ERROR_COUNT=$((ERROR_COUNT + 1))
        append_progress "iteration_failure" "phase=$MODE iter=$ITERATION exit_code=$CLAUDE_EXIT"
    else
        ralph_success "Claude iteration completed"
        CONSECUTIVE_FAILURES=0  # Reset on success
        append_progress "iteration_success" "phase=$MODE iter=$ITERATION"
    fi

    # Generate and display summary
    generate_summary "$LOG_FILE" "$ITERATION" "$TURN_START_TIME"

    # Skip commit/push in debug mode
    if [ "${NO_COMMIT:-false}" = true ]; then
        ralph_warn "DEBUG MODE - Skipping commit and push"
        break
    fi

    # Stage cross-iteration memory files
    stage_ralph_memory

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

append_progress "session_end" "result=complete iters=$COMPLETED_ITERATIONS errors=$ERROR_COUNT"
stage_ralph_memory

echo ""
echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_SUCCESS}  Ralph completed $COMPLETED_ITERATIONS iteration(s) in $FINAL_FORMATTED${C_RESET}"
echo -e "${C_SUCCESS}  Errors: $ERROR_COUNT${C_RESET}"
echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
echo ""
