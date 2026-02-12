#!/bin/bash
# Ralph Wiggum - Full Mode Execution
# Sourced by loop.sh — do not run directly.
#
# Full mode runs complete cycles: plan → build → review → review-fix → check
# Supports decomposed specs (auto-cycles through sub-specs).

run_full_mode() {
    TOTAL_ITERATIONS=0
    CYCLE=0
    MAX_CYCLES=$MAX_ITERATIONS  # In full mode, iterations = cycles
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

        # Check max cycles
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
                fi
            elif [ $SPEC_SELECT_RESULT -eq 2 ]; then
                # Blocked
                echo -e "\033[1;31m  ✗ All remaining sub-specs are blocked. Human intervention required.\033[0m"
                create_paused_state "All remaining sub-specs are blocked by unmet dependencies"
                break
            fi
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
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
                echo -e "  \033[1;34mℹ\033[0m  Implementation plan has $UNCHECKED_COUNT items"
            fi
        done

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
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
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
                QA_COUNT=$((UNCHECKED_COUNT - SEC_COUNT - UX_COUNT - DB_COUNT - PERF_COUNT - API_COUNT))
                echo -e "  \033[1;34mℹ\033[0m  $UNCHECKED_COUNT items remaining: \033[1;31mSEC:$SEC_COUNT\033[0m \033[1;35mUX:$UX_COUNT\033[0m \033[1;36mDB:$DB_COUNT\033[0m \033[1;32mPERF:$PERF_COUNT\033[0m \033[1;34mAPI:$API_COUNT\033[0m \033[1;33mQA:$QA_COUNT\033[0m"
            fi

            # Determine which specialist should handle the next item
            SPECIALIST=$(get_next_review_specialist)
            case $SPECIALIST in
                security)
                    REVIEW_PROMPT="./.ralph/prompts/review/security.md"
                    SPECIALIST_NAME="Security"
                    SPECIALIST_COLOR="\033[1;31m"
                    ;;
                ux)
                    REVIEW_PROMPT="./.ralph/prompts/review/ux.md"
                    SPECIALIST_NAME="UX"
                    SPECIALIST_COLOR="\033[1;35m"
                    ;;
                db)
                    REVIEW_PROMPT="./.ralph/prompts/review/db.md"
                    SPECIALIST_NAME="DB"
                    SPECIALIST_COLOR="\033[1;36m"
                    ;;
                perf)
                    REVIEW_PROMPT="./.ralph/prompts/review/perf.md"
                    SPECIALIST_NAME="Performance"
                    SPECIALIST_COLOR="\033[1;32m"
                    ;;
                api)
                    REVIEW_PROMPT="./.ralph/prompts/review/api.md"
                    SPECIALIST_NAME="API"
                    SPECIALIST_COLOR="\033[1;34m"
                    ;;
                *)
                    REVIEW_PROMPT="./.ralph/prompts/review/qa.md"
                    SPECIALIST_NAME="QA"
                    SPECIALIST_COLOR="\033[1;33m"
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

                if ! run_single_iteration "./.ralph/prompts/review/fix.md" $TOTAL_ITERATIONS "REVIEW-FIX ($REVIEWFIX_ITERATION/$FULL_REVIEWFIX_ITERS)"; then
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

            echo -e "  \033[1;32m✓\033[0m Review-fix phase complete"
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

            if ! run_single_iteration "./.ralph/prompts/distill.md" $TOTAL_ITERATIONS "DISTILL ($DISTILL_ITERATION/$FULL_DISTILL_ITERS)"; then
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

        # ─────────────────────────────────────────────────────────────────────
        # COMPLETION CHECK
        # ─────────────────────────────────────────────────────────────────────
        if run_completion_check; then
            if [ "$IS_DECOMPOSED" = true ]; then
                mark_subspec_complete
                echo -e "  \033[1;35m→\033[0m Sub-spec complete. Selecting next sub-spec..."
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
}
