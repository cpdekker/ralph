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

# Check if circuit breaker should trip (too many consecutive failures)
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
