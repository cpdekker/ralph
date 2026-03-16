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
        ralph_header "Decomposed Spec Detected"
        # Show current progress from manifest
        MANIFEST_TOTAL=$(jq -r '.progress.total // 0' "$MANIFEST_PATH" 2>/dev/null)
        MANIFEST_COMPLETE=$(jq -r '.progress.complete // 0' "$MANIFEST_PATH" 2>/dev/null)
        MANIFEST_IN_PROGRESS=$(jq -r '.progress.in_progress // 0' "$MANIFEST_PATH" 2>/dev/null)
        MANIFEST_PENDING=$(jq -r '.progress.pending // 0' "$MANIFEST_PATH" 2>/dev/null)
        echo -e "  Sub-specs: $MANIFEST_TOTAL total, ${C_SUCCESS}$MANIFEST_COMPLETE complete${C_RESET}, ${C_WARNING}$MANIFEST_IN_PROGRESS in progress${C_RESET}, ${C_PRIMARY}$MANIFEST_PENDING pending${C_RESET}"
        echo ""
    else
        # Check if spec is large and suggest decomposition
        SPEC_LINE_COUNT=$(wc -l < "$SPEC_FILE" 2>/dev/null || echo "0")
        if [ "$SPEC_LINE_COUNT" -gt 200 ]; then
            echo ""
            ralph_warn "Large spec detected ($SPEC_LINE_COUNT lines)"
            ralph_hint "Consider running decompose mode first: node .ralph/run.js $SPEC_NAME decompose"
            echo ""
        fi
    fi

    while [ "$IMPLEMENTATION_COMPLETE" = false ]; do
        CYCLE=$((CYCLE + 1))

        # Check max cycles
        if [ $CYCLE -gt $MAX_CYCLES ]; then
            echo -e "${C_WARNING}Reached max cycles: $MAX_CYCLES${C_RESET}"
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
                    echo -e "  ${C_WARNING}⚠ Master check found gaps. Continuing cycles...${C_RESET}"
                fi
            elif [ $SPEC_SELECT_RESULT -eq 2 ]; then
                # Blocked
                echo -e "${C_ERROR}  ✗ All remaining sub-specs are blocked. Human intervention required.${C_RESET}"
                create_paused_state "All remaining sub-specs are blocked by unmet dependencies"
                break
            fi
        fi

        print_cycle_banner $CYCLE

        # ─────────────────────────────────────────────────────────────────────
        # CYCLE RESTART GATE — skip PLAN when plan exists (complete or not)
        # ─────────────────────────────────────────────────────────────────────
        SKIP_PLAN=false
        if [ $CYCLE -gt 1 ]; then
            PLAN_FILE="./.ralph/implementation_plan.md"
            if [ -f "$PLAN_FILE" ]; then
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
                if [ "$UNCHECKED_COUNT" -gt 0 ]; then
                    echo -e "  ${C_API}ℹ${C_RESET}  Plan exists with $UNCHECKED_COUNT unchecked items — skipping PLAN, resuming BUILD"
                else
                    echo -e "  ${C_API}ℹ${C_RESET}  Plan fully checked — skipping PLAN and BUILD"
                fi
                SKIP_PLAN=true
            fi
        fi

        if [ "$SKIP_PLAN" = false ]; then
        # ─────────────────────────────────────────────────────────────────────
        # PLAN PHASE
        # ─────────────────────────────────────────────────────────────────────

        # Cycle-aware scaling: cycle 1 gets full budget, subsequent cycles get 2
        if [ $CYCLE -eq 1 ]; then
            EFFECTIVE_PLAN_ITERS=$FULL_PLAN_ITERS
        else
            EFFECTIVE_PLAN_ITERS=2
        fi

        print_phase_banner "PLAN" $EFFECTIVE_PLAN_ITERS

        PLAN_ITERATION=0
        PLAN_PREV_HASH=""
        PHASE_ERROR=false
        while [ $PLAN_ITERATION -lt $EFFECTIVE_PLAN_ITERS ]; do
            PLAN_ITERATION=$((PLAN_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

            PLAN_FILE="./.ralph/implementation_plan.md"

            if ! run_single_iteration "./.ralph/prompts/plan.md" $TOTAL_ITERATIONS "PLAN ($PLAN_ITERATION/$EFFECTIVE_PLAN_ITERS)"; then
                echo -e "  ${C_ERROR}✗${C_RESET} Claude error - checking circuit breaker"
                if check_circuit_breaker; then
                    PHASE_ERROR=true
                    break
                fi
            fi

            # Plan stability detection: if plan hash unchanged after iteration, exit early
            if [ -f "$PLAN_FILE" ]; then
                PLAN_CURRENT_HASH=$(md5sum "$PLAN_FILE" 2>/dev/null | cut -d' ' -f1)
                if [ -n "$PLAN_PREV_HASH" ] && [ "$PLAN_CURRENT_HASH" = "$PLAN_PREV_HASH" ]; then
                    echo -e "  ${C_API}ℹ${C_RESET}  Plan stabilized (no changes) — exiting PLAN early"
                    break
                fi
                PLAN_PREV_HASH="$PLAN_CURRENT_HASH"
            fi

            # Show progress
            if [ -f "$PLAN_FILE" ]; then
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
                echo -e "  ${C_API}ℹ${C_RESET}  Implementation plan has $UNCHECKED_COUNT items"
            fi
        done

        if [ "$PHASE_ERROR" = true ]; then
            echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
            echo -e "${C_ERROR}  ❌ Full mode stopped due to circuit breaker${C_RESET}"
            echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
            break
        fi

        echo -e "  ${C_SUCCESS}✓${C_RESET} Plan phase complete ($PLAN_ITERATION iterations)"

        # Clear user-intervention.md after plan has incorporated responses
        INTERVENTION_FILE="./.ralph/user-intervention.md"
        if [ -f "$INTERVENTION_FILE" ]; then
            # Check if file has actual user responses (not just the template)
            INTERVENTION_CONTENT_LINES=$(grep -cvE '^(#|---|$|<!--|_|\*\*|- ?$|Ralph|<!--)' "$INTERVENTION_FILE" 2>/dev/null) || INTERVENTION_CONTENT_LINES=0
            if [ "$INTERVENTION_CONTENT_LINES" -gt 0 ]; then
                echo -e "  ${C_API}ℹ${C_RESET}  Clearing user-intervention.md (responses incorporated into plan)"
                > "$INTERVENTION_FILE"
                git add "$INTERVENTION_FILE"
                git commit -m "ralph: clear user-intervention.md after plan incorporation" 2>/dev/null || true
                git push origin "$(git branch --show-current)" 2>/dev/null || true
            fi
        fi

        # Clear user-review.md after plan has incorporated it
        USER_REVIEW_FILE="./.ralph/user-review.md"
        if [ -f "$USER_REVIEW_FILE" ]; then
            USER_CONTENT_LINES=$(grep -cvE '^(#|---|$|<!--|_|\*\*|- ?$)' "$USER_REVIEW_FILE" 2>/dev/null) || USER_CONTENT_LINES=0
            if [ "$USER_CONTENT_LINES" -gt 0 ]; then
                echo -e "  ${C_API}ℹ${C_RESET}  Clearing user-review.md (notes incorporated into plan)"
                cat > "$USER_REVIEW_FILE" << 'USERREVIEWEOF'
# User Review Notes

This file is for YOUR manual review notes, feedback, and guidance for the next planning/build cycle.

**Ralph will prioritize these notes** when running in plan mode.

---

## How to Use

Add your notes in the sections below. After running 1-3 plan iterations, these notes will be formalized into the implementation plan. You can then clear this file for the next review cycle.

---

## 🐛 Bugs Found

<!-- List bugs you discovered during manual testing -->

-

---

## ❌ Implementation Issues

<!-- Things that weren't implemented the way you wanted -->

-

---

## 🎯 Focus Areas for Next Iteration

<!-- What should Ralph prioritize in the next build cycle? -->

-

---

## 💡 Suggestions & Improvements

<!-- Ideas for improvements, refactoring, or enhancements -->

-

---

## 📝 General Notes

<!-- Any other context, clarifications, or guidance -->

-

---

## ⚠️ Do Not Touch

<!-- Files or areas Ralph should avoid modifying -->

-

---

_Clear this file after your notes have been incorporated into the implementation plan._
USERREVIEWEOF
                git add "$USER_REVIEW_FILE"
                git commit -m "ralph: clear user-review.md after plan incorporation" 2>/dev/null || true
                git push origin "$(git branch --show-current)" 2>/dev/null || true
            fi
        fi

        fi  # end SKIP_PLAN

        # ─────────────────────────────────────────────────────────────────────
        # BUILD PHASE (skip if plan fully complete on cycle 2+)
        # ─────────────────────────────────────────────────────────────────────
        SKIP_BUILD=false
        if [ $CYCLE -gt 1 ]; then
            PLAN_FILE="./.ralph/implementation_plan.md"
            if [ -f "$PLAN_FILE" ]; then
                UNCHECKED_COUNT=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || UNCHECKED_COUNT=0
                if [ "$UNCHECKED_COUNT" -eq 0 ]; then
                    SKIP_BUILD=true
                fi
            fi
        fi

        if [ "$SKIP_BUILD" = true ]; then
            echo -e "  ${C_SUCCESS}✓${C_RESET} All build tasks already complete — skipping BUILD"
        else
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
                        echo -e "  ${C_SUCCESS}✓${C_RESET} All build tasks complete!"
                        break
                    fi
                    echo -e "  ${C_API}ℹ${C_RESET}  $UNCHECKED_COUNT unchecked items remaining"
                fi

                if ! run_single_iteration "./.ralph/prompts/build.md" $TOTAL_ITERATIONS "BUILD ($BUILD_ITERATION/$FULL_BUILD_ITERS)"; then
                    echo -e "  ${C_ERROR}✗${C_RESET} Claude error - checking circuit breaker"
                    if check_circuit_breaker; then
                        PHASE_ERROR=true
                        break
                    fi
                fi
            done

            if [ "$PHASE_ERROR" = true ]; then
                echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
                echo -e "${C_ERROR}  ❌ Full mode stopped due to circuit breaker${C_RESET}"
                echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
                break
            fi

            echo -e "  ${C_SUCCESS}✓${C_RESET} Build phase complete"
        fi

        # ─────────────────────────────────────────────────────────────────────
        # BUILD QUALITY GATE (must pass before transitioning to REVIEW)
        # ─────────────────────────────────────────────────────────────────────
        if [ -n "${RALPH_BUILD_GATE:-}" ]; then
            echo -e "  ${C_ACCENT}⚙${C_RESET}  Running build quality gate: $RALPH_BUILD_GATE"
            if eval "$RALPH_BUILD_GATE" > /dev/null 2>&1; then
                echo -e "  ${C_SUCCESS}✓${C_RESET} Build gate passed"
            else
                RALPH_BUILD_GATE_RETRIES=${RALPH_BUILD_GATE_RETRIES:-3}
                echo -e "  ${C_ERROR}✗${C_RESET} Build gate failed — running extra BUILD iterations (max $RALPH_BUILD_GATE_RETRIES)"
                GATE_RETRY=0
                GATE_PASSED=false
                while [ $GATE_RETRY -lt $RALPH_BUILD_GATE_RETRIES ]; do
                    GATE_RETRY=$((GATE_RETRY + 1))
                    TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
                    echo -e "  ${C_API}ℹ${C_RESET}  Gate retry $GATE_RETRY/$RALPH_BUILD_GATE_RETRIES"

                    if ! run_single_iteration "./.ralph/prompts/build.md" $TOTAL_ITERATIONS "BUILD-GATE ($GATE_RETRY/$RALPH_BUILD_GATE_RETRIES)"; then
                        echo -e "  ${C_ERROR}✗${C_RESET} Claude error during gate retry"
                        if check_circuit_breaker; then
                            PHASE_ERROR=true
                            break
                        fi
                    fi

                    if eval "$RALPH_BUILD_GATE" > /dev/null 2>&1; then
                        echo -e "  ${C_SUCCESS}✓${C_RESET} Build gate passed after $GATE_RETRY retry(s)"
                        GATE_PASSED=true
                        break
                    fi
                done

                if [ "$PHASE_ERROR" = true ]; then
                    echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
                    echo -e "${C_ERROR}  ❌ Full mode stopped due to circuit breaker${C_RESET}"
                    echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
                    break
                fi

                if [ "$GATE_PASSED" = false ]; then
                    echo -e "  ${C_WARNING}⚠${C_RESET}  Build gate still failing after $RALPH_BUILD_GATE_RETRIES retries — proceeding to REVIEW"
                fi
            fi
        fi

        # ─────────────────────────────────────────────────────────────────────
        # REVIEW RESET (cycle 2+: clear stale findings from previous cycle)
        # ─────────────────────────────────────────────────────────────────────
        if [ $CYCLE -gt 1 ]; then
            REVIEW_FILE="./.ralph/review.md"
            CHECKLIST_FILE="./.ralph/review_checklist.md"
            if [ -f "$REVIEW_FILE" ]; then
                echo -e "  ${C_API}ℹ${C_RESET}  Clearing previous cycle review findings"
                > "$REVIEW_FILE"
            fi
            if [ -f "$CHECKLIST_FILE" ]; then
                echo -e "  ${C_API}ℹ${C_RESET}  Regenerating review checklist for current cycle"
                rm -f "$CHECKLIST_FILE"
            fi
        fi

        # ─────────────────────────────────────────────────────────────────────
        # REVIEW PHASE (setup only on first cycle or when checklist missing)
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "REVIEW" $FULL_REVIEW_ITERS

        # Only run review setup if checklist doesn't exist yet
        CHECKLIST_FILE="./.ralph/review_checklist.md"
        if [ ! -f "$CHECKLIST_FILE" ] || [ $CYCLE -eq 1 ]; then
            echo -e "  ${C_ACCENT}⚙${C_RESET}  Running review setup..."
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
            SETUP_LOG_FILE="$TEMP_DIR/review_setup_cycle_${CYCLE}.log"
            SETUP_START_TIME=$(date +%s)
            SETUP_START_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")

            if [ "$VERBOSE" = true ]; then
                cat "./.ralph/prompts/review/setup.md" | claude -p \
                    --dangerously-skip-permissions \
                    --output-format=stream-json \
                    --verbose 2>&1 | tee "$SETUP_LOG_FILE"
                SETUP_EXIT=${PIPESTATUS[1]}
            else
                cat "./.ralph/prompts/review/setup.md" | claude -p \
                    --dangerously-skip-permissions \
                    --output-format=stream-json \
                    --verbose > "$SETUP_LOG_FILE" 2>&1 &

                SETUP_PID=$!
                spin $SETUP_PID "Running review setup..."
                wait $SETUP_PID
                SETUP_EXIT=$?
            fi

            # Log the review setup iteration
            persist_iteration_log "$SETUP_LOG_FILE" "$TOTAL_ITERATIONS" "REVIEW-SETUP (1/1)" "${SETUP_EXIT:-0}" "$SETUP_START_TIME" "$SETUP_START_SHA"

            git push origin "$CURRENT_BRANCH" || git push -u origin "$CURRENT_BRANCH"
            echo -e "  ${C_SUCCESS}✓${C_RESET} Review setup complete"
            echo ""
        else
            echo -e "  ${C_API}ℹ${C_RESET}  Review checklist exists — reusing from previous cycle"
            echo ""
        fi

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
                    echo -e "  ${C_SUCCESS}✓${C_RESET} All review items complete!"
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
            fi

            # Determine which specialist should handle the next item
            SPECIALIST=$(get_next_review_specialist)
            case $SPECIALIST in
                security)
                    REVIEW_PROMPT="./.ralph/prompts/review/security.md"
                    SPECIALIST_NAME="Security"
                    SPECIALIST_COLOR="$C_SEC"
                    ;;
                ux)
                    REVIEW_PROMPT="./.ralph/prompts/review/ux.md"
                    SPECIALIST_NAME="UX"
                    SPECIALIST_COLOR="$C_UX"
                    ;;
                db)
                    REVIEW_PROMPT="./.ralph/prompts/review/db.md"
                    SPECIALIST_NAME="DB"
                    SPECIALIST_COLOR="$C_DB"
                    ;;
                perf)
                    REVIEW_PROMPT="./.ralph/prompts/review/perf.md"
                    SPECIALIST_NAME="Performance"
                    SPECIALIST_COLOR="$C_PERF"
                    ;;
                api)
                    REVIEW_PROMPT="./.ralph/prompts/review/api.md"
                    SPECIALIST_NAME="API"
                    SPECIALIST_COLOR="$C_API"
                    ;;
                *)
                    REVIEW_PROMPT="./.ralph/prompts/review/qa.md"
                    SPECIALIST_NAME="QA"
                    SPECIALIST_COLOR="$C_QA"
                    ;;
            esac

            # Fallback to generic review.md if specialist prompt doesn't exist
            if [ ! -f "$REVIEW_PROMPT" ]; then
                REVIEW_PROMPT="./.ralph/prompts/review/general.md"
                SPECIALIST_NAME="General"
                SPECIALIST_COLOR="$C_HIGHLIGHT"
            fi

            echo -e "  ${SPECIALIST_COLOR}🔍 Specialist: $SPECIALIST_NAME${C_RESET}"

            if ! run_single_iteration "$REVIEW_PROMPT" $TOTAL_ITERATIONS "REVIEW-$SPECIALIST_NAME ($REVIEW_ITERATION/$FULL_REVIEW_ITERS)"; then
                echo -e "  ${C_ERROR}✗${C_RESET} Claude error - checking circuit breaker"
                if check_circuit_breaker; then
                    PHASE_ERROR=true
                    break
                fi
            fi
        done

        if [ "$PHASE_ERROR" = true ]; then
            echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
            echo -e "${C_ERROR}  ❌ Full mode stopped due to circuit breaker${C_RESET}"
            echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
            break
        fi

        echo -e "  ${C_SUCCESS}✓${C_RESET} Review phase complete"

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
            echo -e "  ${C_API}ℹ${C_RESET}  Issues to fix: ${C_ERROR}❌ Blocking: $FIX_BLOCKING${C_RESET}  ${C_WARNING}⚠️ Attention: $FIX_ATTENTION${C_RESET}"

            REVIEWFIX_ITERATION=0
            CONSECUTIVE_ZERO_WORK=0
            PHASE_ERROR=false
            while [ $REVIEWFIX_ITERATION -lt $FULL_REVIEWFIX_ITERS ]; do
                REVIEWFIX_ITERATION=$((REVIEWFIX_ITERATION + 1))
                TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

                # Check if all issues are resolved before running
                if [ -f "$REVIEW_FILE" ]; then
                    REMAINING_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null) || REMAINING_BLOCKING=0
                    REMAINING_ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$REVIEW_FILE" 2>/dev/null) || REMAINING_ATTENTION=0
                    if [ "$REMAINING_BLOCKING" -eq 0 ] && [ "$REMAINING_ATTENTION" -eq 0 ]; then
                        echo -e "  ${C_SUCCESS}✓${C_RESET} All review issues resolved!"
                        break
                    fi
                    echo -e "  ${C_API}ℹ${C_RESET}  Remaining: ${C_ERROR}❌ $REMAINING_BLOCKING${C_RESET}  ${C_WARNING}⚠️ $REMAINING_ATTENTION${C_RESET}"
                fi

                # Reset metrics before iteration (set by persist_iteration_log)
                LAST_ITER_FILES_MODIFIED=0
                LAST_ITER_CODE_FILES=0
                LAST_ITER_COMMITS=0

                if ! run_single_iteration "./.ralph/prompts/review/fix.md" $TOTAL_ITERATIONS "REVIEW-FIX ($REVIEWFIX_ITERATION/$FULL_REVIEWFIX_ITERS)"; then
                    echo -e "  ${C_ERROR}✗${C_RESET} Claude error - checking circuit breaker"
                    if check_circuit_breaker; then
                        PHASE_ERROR=true
                        break
                    fi
                fi

                # Zero-work early termination: if iteration produced no file changes and no commits,
                # it's spinning without making progress. Exit after 2 consecutive zero-work iterations.
                if [ "${LAST_ITER_CODE_FILES:-0}" -eq 0 ] && [ "${LAST_ITER_COMMITS:-0}" -le 1 ]; then
                    CONSECUTIVE_ZERO_WORK=$((CONSECUTIVE_ZERO_WORK + 1))
                    if [ $CONSECUTIVE_ZERO_WORK -ge 2 ]; then
                        echo -e "  ${C_WARNING}⚠${C_RESET}  $CONSECUTIVE_ZERO_WORK consecutive zero-work iterations — exiting REVIEW-FIX early"
                        append_progress "zero_work_exit" "REVIEW-FIX exited after $CONSECUTIVE_ZERO_WORK consecutive zero-work iterations"
                        break
                    fi
                else
                    CONSECUTIVE_ZERO_WORK=0
                fi
            done

            if [ "$PHASE_ERROR" = true ]; then
                echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
                echo -e "${C_ERROR}  ❌ Full mode stopped due to circuit breaker${C_RESET}"
                echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
                break
            fi

            echo -e "  ${C_SUCCESS}✓${C_RESET} Review-fix phase complete"
        else
            echo -e "  ${C_SUCCESS}✓${C_RESET} No blocking/attention issues — skipping review-fix"
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
                echo -e "  ${C_ERROR}✗${C_RESET} Claude error - checking circuit breaker"
                if check_circuit_breaker; then
                    PHASE_ERROR=true
                    break
                fi
            fi
        done

        if [ "$PHASE_ERROR" = true ]; then
            echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
            echo -e "${C_ERROR}  ❌ Full mode stopped due to circuit breaker${C_RESET}"
            echo -e "${C_ERROR}════════════════════════════════════════════════════════════${C_RESET}"
            break
        fi

        echo -e "  ${C_SUCCESS}✓${C_RESET} Distill phase complete"

        # ─────────────────────────────────────────────────────────────────────
        # COMPLETION CHECK (fast path + Claude verification)
        # ─────────────────────────────────────────────────────────────────────

        # Fast path: if plan is fully checked and no blocking review issues, complete
        FAST_COMPLETE=false
        PLAN_FILE="./.ralph/implementation_plan.md"
        REVIEW_FILE="./.ralph/review.md"
        if [ -f "$PLAN_FILE" ]; then
            PLAN_UNCHECKED=$(grep -c '\- \[ \]' "$PLAN_FILE" 2>/dev/null) || PLAN_UNCHECKED=0
            PLAN_BLOCKED=$(grep -c '\[BLOCKED\]' "$PLAN_FILE" 2>/dev/null) || PLAN_BLOCKED=0
            REVIEW_BLOCKING=0
            if [ -f "$REVIEW_FILE" ]; then
                REVIEW_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$REVIEW_FILE" 2>/dev/null) || REVIEW_BLOCKING=0
            fi
            if [ "$PLAN_UNCHECKED" -eq 0 ] && [ "$PLAN_BLOCKED" -eq 0 ] && [ "$REVIEW_BLOCKING" -eq 0 ]; then
                # If build gate is set, verify it passes before fast-completing
                if [ -n "${RALPH_BUILD_GATE:-}" ]; then
                    if eval "$RALPH_BUILD_GATE" > /dev/null 2>&1; then
                        FAST_COMPLETE=true
                    else
                        echo -e "  ${C_WARNING}⚠${C_RESET}  Fast-complete blocked: build gate failed — falling through to full completion check"
                    fi
                else
                    FAST_COMPLETE=true
                fi

                if [ "$FAST_COMPLETE" = true ]; then
                    echo ""
                    echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
                    echo -e "${C_SUCCESS}  ✅ FAST COMPLETION — All plan items done, no blocking issues${C_RESET}"
                    echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
                    echo ""
                fi
            fi
        fi

        if [ "$FAST_COMPLETE" = true ]; then
            COMPLETION_RESULT=0
        else
            run_completion_check
            COMPLETION_RESULT=$?
        fi

        if [ $COMPLETION_RESULT -eq 0 ]; then
            if [ "$IS_DECOMPOSED" = true ]; then
                mark_subspec_complete
                echo -e "  ${C_ACCENT}→${C_RESET} Sub-spec complete. Selecting next sub-spec..."
            else
                IMPLEMENTATION_COMPLETE=true
            fi
        elif [ $COMPLETION_RESULT -eq 2 ]; then
            echo -e "  ${C_ACCENT}🛑${C_RESET} Ralph is blocked on user intervention. Stopping iterations."
            echo -e "  ${C_ACCENT}📋${C_RESET} Review ${C_HIGHLIGHT}.ralph/user-intervention.md${C_RESET} and provide answers."
            echo -e "  ${C_ACCENT}💡${C_RESET} Drop reference files in ${C_HIGHLIGHT}.ralph/references/${C_RESET} if needed."
            echo -e "  ${C_ACCENT}→${C_RESET}  Re-run Ralph after responding to resume."
            append_progress "blocked_on_user" "All agent work complete. User intervention required."
            stage_ralph_memory
            break
        else
            echo -e "  ${C_ACCENT}→${C_RESET} Starting next cycle..."
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
    echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
    if [ "$IMPLEMENTATION_COMPLETE" = true ]; then
        echo -e "${C_SUCCESS}  🎉 Ralph completed spec in $CYCLE cycle(s), $TOTAL_ITERATIONS iteration(s)${C_RESET}"
    else
        echo -e "${C_WARNING}  ⚠ Ralph stopped after $CYCLE cycle(s), $TOTAL_ITERATIONS iteration(s)${C_RESET}"
    fi
    echo -e "${C_SUCCESS}  Total time: $FINAL_FORMATTED${C_RESET}"
    echo -e "${C_SUCCESS}  Errors: $ERROR_COUNT${C_RESET}"
    echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
    echo ""

    # Generate final summary for the user
    if [ "$TOTAL_ITERATIONS" -gt 0 ]; then
        local stop_reason="complete"
        if [ "$IMPLEMENTATION_COMPLETE" != true ]; then
            stop_reason="max_iterations"
        fi
        run_final_summary "$stop_reason"
        stage_ralph_memory
        git push origin "$CURRENT_BRANCH" 2>/dev/null || true
    fi
}
