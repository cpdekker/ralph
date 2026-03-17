#!/bin/bash
# Ralph Wiggum - Research Mode Execution
# Sourced by loop.sh — do not run directly.
#
# Research mode flow: codebase → web → review → completion check
# If completion check finds blocking gaps, loops back to targeted research.

run_research_mode() {
    TOTAL_ITERATIONS=0
    RESEARCH_COMPLETE=false
    RESEARCH_CYCLE=0
    MAX_RESEARCH_CYCLES=${MAX_RESEARCH_CYCLES:-3}

    echo ""
    echo -e "${C_ACCENT}╔════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_ACCENT}║              RESEARCH MODE                                 ║${C_RESET}"
    echo -e "${C_ACCENT}╠════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_ACCENT}║  codebase → web → review → completion check               ║${C_RESET}"
    echo -e "${C_ACCENT}╚════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""

    while [ "$RESEARCH_COMPLETE" = false ] && [ $RESEARCH_CYCLE -lt $MAX_RESEARCH_CYCLES ]; do
        RESEARCH_CYCLE=$((RESEARCH_CYCLE + 1))

        if [ $RESEARCH_CYCLE -gt 1 ]; then
            echo ""
            echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
            echo -e "${C_WARNING}  🔄 RESEARCH CYCLE $RESEARCH_CYCLE — Filling identified gaps${C_RESET}"
            echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
            echo ""
        fi

        # ─────────────────────────────────────────────────────────────────────
        # PHASE: CODEBASE RESEARCH
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "CODEBASE RESEARCH" $RESEARCH_CODEBASE_ITERS

        CODEBASE_ITERATION=0
        while [ $CODEBASE_ITERATION -lt $RESEARCH_CODEBASE_ITERS ]; do
            CODEBASE_ITERATION=$((CODEBASE_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

            if ! run_single_iteration "./.ralph/prompts/research/codebase.md" $TOTAL_ITERATIONS "CODEBASE ($CODEBASE_ITERATION/$RESEARCH_CODEBASE_ITERS)"; then
                echo -e "  ${C_ERROR}✗${C_RESET} Codebase research phase failed"
                if check_circuit_breaker; then
                    break 2
                fi
            fi
        done

        echo -e "  ${C_SUCCESS}✓${C_RESET} Codebase research phase complete"

        # ─────────────────────────────────────────────────────────────────────
        # PHASE: WEB RESEARCH
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "WEB RESEARCH" $RESEARCH_WEB_ITERS

        WEB_ITERATION=0
        while [ $WEB_ITERATION -lt $RESEARCH_WEB_ITERS ]; do
            WEB_ITERATION=$((WEB_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

            if ! run_single_iteration "./.ralph/prompts/research/web.md" $TOTAL_ITERATIONS "WEB ($WEB_ITERATION/$RESEARCH_WEB_ITERS)"; then
                echo -e "  ${C_ERROR}✗${C_RESET} Web research phase failed"
                if check_circuit_breaker; then
                    break 2
                fi
            fi
        done

        echo -e "  ${C_SUCCESS}✓${C_RESET} Web research phase complete"

        # ─────────────────────────────────────────────────────────────────────
        # PHASE: REVIEW
        # ─────────────────────────────────────────────────────────────────────
        print_phase_banner "RESEARCH REVIEW" $RESEARCH_REVIEW_ITERS

        REVIEW_ITERATION=0
        while [ $REVIEW_ITERATION -lt $RESEARCH_REVIEW_ITERS ]; do
            REVIEW_ITERATION=$((REVIEW_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

            if ! run_single_iteration "./.ralph/prompts/research/review.md" $TOTAL_ITERATIONS "REVIEW ($REVIEW_ITERATION/$RESEARCH_REVIEW_ITERS)"; then
                echo -e "  ${C_ERROR}✗${C_RESET} Review phase failed"
                if check_circuit_breaker; then
                    break 2
                fi
            fi
        done

        echo -e "  ${C_SUCCESS}✓${C_RESET} Review phase complete"

        # ─────────────────────────────────────────────────────────────────────
        # COMPLETION CHECK
        # ─────────────────────────────────────────────────────────────────────
        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
        if run_research_completion_check; then
            RESEARCH_COMPLETE=true
        else
            # Check if the completion check said we need user input
            if [ -f "./.ralph/research_completion.json" ]; then
                local next_step
                next_step=$(cat "./.ralph/research_completion.json" | jq -r '.next_step // "research"' 2>/dev/null)
                if [ "$next_step" = "user_input" ]; then
                    echo -e "  ${C_WARNING}⚠${C_RESET}  Research paused — user input needed"
                    echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Edit .ralph/research_gaps.md to answer decision questions"
                    break
                fi
            fi

            if [ $RESEARCH_CYCLE -lt $MAX_RESEARCH_CYCLES ]; then
                echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Blocking gaps remain — starting targeted research cycle"
                # Reduce iterations for follow-up cycles (targeted, not broad)
                RESEARCH_CODEBASE_ITERS=1
                RESEARCH_WEB_ITERS=1
            else
                echo -e "  ${C_WARNING}⚠${C_RESET}  Max research cycles reached ($MAX_RESEARCH_CYCLES)"
            fi
        fi
    done

    # Calculate final total elapsed time
    FINAL_ELAPSED=$(($(date +%s) - LOOP_START_TIME))
    FINAL_FORMATTED=$(format_duration $FINAL_ELAPSED)

    # Clean up state file on completion
    rm -f "$STATE_FILE"

    echo ""
    echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
    if [ "$RESEARCH_COMPLETE" = true ]; then
        echo -e "${C_SUCCESS}  🎉 Research complete in $TOTAL_ITERATIONS iteration(s) ($RESEARCH_CYCLE cycle(s))${C_RESET}"
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "${C_PRIMARY}  📋 WHAT TO DO NEXT:${C_RESET}"
        echo ""
        echo -e "  ${C_SUCCESS}✓${C_RESET} Research documents are in ${C_HIGHLIGHT}.ralph/references/${C_RESET}"
        echo -e "  ${C_SUCCESS}✓${C_RESET} Review summary in ${C_HIGHLIGHT}.ralph/research_review.md${C_RESET}"
        echo ""
        echo -e "  ${C_PRIMARY}▶ Create a spec:${C_RESET}"
        echo -e "     ${C_HIGHLIGHT}node .ralph/run.js $SPEC_NAME spec${C_RESET}"
        echo ""
        echo -e "  ${C_PRIMARY}▶ Or plan directly:${C_RESET}"
        echo -e "     ${C_HIGHLIGHT}node .ralph/run.js $SPEC_NAME plan${C_RESET}"
    else
        echo -e "${C_WARNING}  ⚠ Research needs your input before it can complete${C_RESET}"
        echo -e "${C_WARNING}════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "${C_PRIMARY}  📋 WHAT TO DO NEXT:${C_RESET}"
        echo ""

        # Check for knowledge gaps requiring user input
        GAPS_FILE="./.ralph/research_gaps.md"
        if [ -f "$GAPS_FILE" ]; then
            USER_GAPS=$(grep -c '## Decision Gaps' "$GAPS_FILE" 2>/dev/null) || USER_GAPS=0
            if [ "$USER_GAPS" -gt 0 ]; then
                echo -e "  ${C_WARNING}1. Review and answer decision questions in:${C_RESET}"
                echo -e "     ${C_HIGHLIGHT}.ralph/research_gaps.md${C_RESET}"
                echo -e "     ${C_MUTED}(Look for the 'Decision Gaps' section)${C_RESET}"
                echo ""
            fi
        fi

        echo -e "  ${C_PRIMARY}2. Review research findings in:${C_RESET}"
        echo -e "     ${C_HIGHLIGHT}.ralph/references/${C_RESET}"
        echo ""

        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "  ${C_PRIMARY}▶ When ready, re-run:${C_RESET}"
        echo -e "     ${C_HIGHLIGHT}node .ralph/run.js $SPEC_NAME research${C_RESET}"
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
    fi
    echo ""
    echo -e "  ${C_MUTED}Total time: $FINAL_FORMATTED | Cycles: $RESEARCH_CYCLE | Errors: $ERROR_COUNT${C_RESET}"
    echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
}
