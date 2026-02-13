#!/bin/bash
# Ralph Wiggum - Core Iteration Engine
# Sourced by loop.sh — do not run directly.

# Run a single iteration with a given prompt file.
# This is the central execution engine used by ALL modes.
#
# Args:
#   $1 - prompt_file: path to the prompt markdown file
#   $2 - iteration_num: current iteration number (for display)
#   $3 - phase_name: name of the current phase (for display/checkpoint)
#
# Returns: 0 on success, 1 on failure
run_single_iteration() {
    local prompt_file=$1
    local iteration_num=$2
    local phase_name=$3

    TURN_START_TIME=$(date +%s)

    # Display turn banner
    print_turn_banner $iteration_num
    echo -e "  ${C_ACCENT}Phase:${C_RESET} $phase_name"
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
            echo -e "  ${C_ERROR}✗${C_RESET} Claude exited with code $CLAUDE_EXIT"
            echo "  Check log: $LOG_FILE"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            ERROR_COUNT=$((ERROR_COUNT + 1))
            append_progress "iteration_failure" "phase=$phase_name iter=$iteration_num exit_code=$CLAUDE_EXIT"
            return 1
        else
            CONSECUTIVE_FAILURES=0  # Reset on success
            append_progress "iteration_success" "phase=$phase_name iter=$iteration_num"
        fi
    else
        cat "$prompt_file" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --verbose > "$LOG_FILE" 2>&1 &

        CLAUDE_PID=$!
        spin $CLAUDE_PID "Running Claude iteration $iteration_num..."
        wait $CLAUDE_PID
        CLAUDE_EXIT=$?

        if [ $CLAUDE_EXIT -ne 0 ]; then
            echo -e "  ${C_ERROR}✗${C_RESET} Claude exited with code $CLAUDE_EXIT"
            echo "  Check log: $LOG_FILE"
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            ERROR_COUNT=$((ERROR_COUNT + 1))
            append_progress "iteration_failure" "phase=$phase_name iter=$iteration_num exit_code=$CLAUDE_EXIT"
            return 1
        else
            echo -e "  ${C_SUCCESS}✓${C_RESET} Claude iteration completed"
            CONSECUTIVE_FAILURES=0  # Reset on success
            append_progress "iteration_success" "phase=$phase_name iter=$iteration_num"
        fi
    fi

    # Generate and display summary
    generate_summary "$LOG_FILE" "$iteration_num" "$TURN_START_TIME"

    # Skip commit/push in debug mode
    if [ "${NO_COMMIT:-false}" = true ]; then
        echo -e "  ${C_WARNING}⚠️  DEBUG MODE - Skipping commit and push${C_RESET}"
        return 0
    fi

    # Stage cross-iteration memory files
    stage_ralph_memory

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }

    # Update checkpoint after successful iteration
    save_state "$phase_name" "$iteration_num" "Completed successfully"

    return 0
}

# Check if circuit breaker should trip (too many consecutive failures)
check_circuit_breaker() {
    if [ $CONSECUTIVE_FAILURES -ge $MAX_CONSECUTIVE_FAILURES ]; then
        ralph_header "Circuit Breaker Tripped"
        ralph_error "$CONSECUTIVE_FAILURES consecutive failures detected"
        ralph_warn "Ralph has paused to prevent further issues."
        ralph_hint "Human intervention required."
        echo ""

        append_progress "circuit_breaker" "$CONSECUTIVE_FAILURES consecutive failures"
        append_guardrail "Known Issues" "Circuit breaker tripped in $MODE phase after $CONSECUTIVE_FAILURES failures"
        stage_ralph_memory

        create_paused_state "Circuit breaker tripped after $CONSECUTIVE_FAILURES consecutive failures"

        return 0  # Circuit breaker tripped
    fi
    return 1  # Circuit breaker not tripped
}
