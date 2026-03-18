#!/bin/bash
# Ralph Wiggum - Spec Mode Execution
# Sourced by loop.sh — do not run directly.
#
# Spec mode flow: research → draft → refine → debate → fix → signoff

# Run the Socratic multi-agent debate phase.
# Sub-phases: SETUP → CRITIQUE (per persona) → CHALLENGE (per persona, optional) → SYNTHESIZE
# Produces .ralph/spec_review.md in the same format as the old single-reviewer REVIEW.
run_debate_phase() {
    local debate_dir="./.ralph/spec_debate"
    local challenge_enabled="${SPEC_DEBATE_CHALLENGE:-true}"

    # Calculate total iterations for display
    local debate_total=5  # setup(1) + critique(3) + synthesize(1)
    if [ "$challenge_enabled" = "true" ]; then
        debate_total=8  # + challenge(3)
    fi

    print_phase_banner "SPEC DEBATE" $debate_total

    # Clean up previous debate state
    rm -rf "$debate_dir"
    mkdir -p "$debate_dir"

    echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Challenge round: $challenge_enabled"

    # ── SUB-PHASE: SETUP (moderator selects personas) ──
    echo ""
    echo -e "  ${C_ACCENT}── Debate Setup ──${C_RESET}"
    TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

    if ! run_single_iteration "./.ralph/prompts/spec/debate/setup.md" $TOTAL_ITERATIONS "DEBATE SETUP"; then
        echo -e "  ${C_ERROR}✗${C_RESET} Debate setup failed"
        if check_circuit_breaker; then
            return
        fi
    fi

    # Parse selected personas from debate_plan.md
    local personas_line=""
    if [ -f "$debate_dir/debate_plan.md" ]; then
        personas_line=$(grep '^## PERSONAS=' "$debate_dir/debate_plan.md" 2>/dev/null | sed 's/^## PERSONAS=//')
    fi

    if [ -z "$personas_line" ]; then
        echo -e "  ${C_ERROR}✗${C_RESET} Could not parse personas from debate_plan.md — falling back to skeptic,architect,qa"
        personas_line="skeptic,architect,qa"
    fi

    # Split into array
    IFS=',' read -ra DEBATE_PERSONAS <<< "$personas_line"
    echo -e "  ${C_SUCCESS}✓${C_RESET} Debate setup complete — personas: ${DEBATE_PERSONAS[*]}"

    # ── SUB-PHASE: CRITIQUE (each persona independently) ──
    echo ""
    echo -e "  ${C_ACCENT}── Independent Critiques ──${C_RESET}"

    for persona in "${DEBATE_PERSONAS[@]}"; do
        local prompt_file="./.ralph/prompts/spec/debate/${persona}.md"
        if [ ! -f "$prompt_file" ]; then
            echo -e "  ${C_WARNING}⚠️${C_RESET}  No prompt file for persona '$persona' — skipping"
            continue
        fi

        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
        echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Running critique: $persona"

        if ! run_single_iteration "$prompt_file" $TOTAL_ITERATIONS "CRITIQUE ($persona)"; then
            echo -e "  ${C_ERROR}✗${C_RESET} $persona critique failed"
            if check_circuit_breaker; then
                return
            fi
        fi
    done

    echo -e "  ${C_SUCCESS}✓${C_RESET} All critiques complete"

    # ── SUB-PHASE: CHALLENGE (cross-examination, optional) ──
    if [ "$challenge_enabled" = "true" ]; then
        echo ""
        echo -e "  ${C_ACCENT}── Cross-Examination ──${C_RESET}"

        for persona in "${DEBATE_PERSONAS[@]}"; do
            local prompt_file="./.ralph/prompts/spec/debate/${persona}.md"
            if [ ! -f "$prompt_file" ]; then
                continue
            fi

            # Only run challenge if the persona produced a critique
            if [ ! -f "$debate_dir/${persona}_critique.md" ]; then
                echo -e "  ${C_WARNING}⚠️${C_RESET}  No critique from '$persona' — skipping challenge"
                continue
            fi

            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
            echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Running challenge: $persona"

            if ! run_single_iteration "$prompt_file" $TOTAL_ITERATIONS "CHALLENGE ($persona)"; then
                echo -e "  ${C_ERROR}✗${C_RESET} $persona challenge failed"
                if check_circuit_breaker; then
                    return
                fi
            fi
        done

        echo -e "  ${C_SUCCESS}✓${C_RESET} Cross-examination complete"
    else
        echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Challenge round disabled — skipping"
    fi

    # ── SUB-PHASE: SYNTHESIZE (moderator produces spec_review.md) ──
    echo ""
    echo -e "  ${C_ACCENT}── Synthesis ──${C_RESET}"
    TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

    if ! run_single_iteration "./.ralph/prompts/spec/debate/synthesize.md" $TOTAL_ITERATIONS "DEBATE SYNTHESIZE"; then
        echo -e "  ${C_ERROR}✗${C_RESET} Synthesis failed"
        if check_circuit_breaker; then
            return
        fi
    fi

    echo -e "  ${C_SUCCESS}✓${C_RESET} Debate phase complete — spec_review.md produced"
}

run_spec_mode() {
    TOTAL_ITERATIONS=0
    SPEC_READY=false

    echo ""
    echo -e "${C_ACCENT}╔════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_ACCENT}║              SPEC CREATION MODE                            ║${C_RESET}"
    echo -e "${C_ACCENT}╠════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_ACCENT}║  research → draft → refine → debate → fix → signoff       ║${C_RESET}"
    echo -e "${C_ACCENT}╚════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""

    # ─────────────────────────────────────────────────────────────────────
    # PHASE: RESEARCH
    # ─────────────────────────────────────────────────────────────────────
    print_phase_banner "RESEARCH" $SPEC_RESEARCH_ITERS

    RESEARCH_ITERATION=0
    while [ $RESEARCH_ITERATION -lt $SPEC_RESEARCH_ITERS ]; do
        RESEARCH_ITERATION=$((RESEARCH_ITERATION + 1))
        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

        if ! run_single_iteration "./.ralph/prompts/spec/research.md" $TOTAL_ITERATIONS "RESEARCH ($RESEARCH_ITERATION/$SPEC_RESEARCH_ITERS)"; then
            echo -e "  ${C_ERROR}✗${C_RESET} Research phase failed"
            if check_circuit_breaker; then
                break
            fi
        fi
    done

    echo -e "  ${C_SUCCESS}✓${C_RESET} Research phase complete"

    # ─────────────────────────────────────────────────────────────────────
    # PHASE: DRAFT
    # ─────────────────────────────────────────────────────────────────────
    print_phase_banner "DRAFT" $SPEC_DRAFT_ITERS

    DRAFT_ITERATION=0
    while [ $DRAFT_ITERATION -lt $SPEC_DRAFT_ITERS ]; do
        DRAFT_ITERATION=$((DRAFT_ITERATION + 1))
        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

        if ! run_single_iteration "./.ralph/prompts/spec/draft.md" $TOTAL_ITERATIONS "DRAFT ($DRAFT_ITERATION/$SPEC_DRAFT_ITERS)"; then
            echo -e "  ${C_ERROR}✗${C_RESET} Draft phase failed"
            if check_circuit_breaker; then
                break
            fi
        fi
    done

    # Copy new spec to active.md if it was created
    if [ -f "$SPEC_FILE" ]; then
        echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Copying spec to active.md"
        cp "$SPEC_FILE" "$ACTIVE_SPEC"
        git add "$ACTIVE_SPEC"
        git commit -m "spec: copy to active.md" 2>/dev/null || true
        git push origin "$CURRENT_BRANCH" 2>/dev/null || true
    fi

    echo -e "  ${C_SUCCESS}✓${C_RESET} Draft phase complete"

    # ─────────────────────────────────────────────────────────────────────
    # PHASE: REFINE (with early exit)
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
                echo -e "  ${C_SUCCESS}✓${C_RESET} Refinement complete — all questions answered, no feedback pending"
                REFINEMENT_DONE=true
                break
            fi

            # Show unanswered question count
            UNANSWERED=$(grep -c '^A:$\|^A: *$' "./.ralph/spec_questions.md" 2>/dev/null) || UNANSWERED=0
            if [ "$UNANSWERED" -gt 0 ]; then
                echo -e "  ${C_PRIMARY}ℹ${C_RESET}  $UNANSWERED unanswered questions remaining"
                echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Edit .ralph/spec_questions.md to answer them, then this phase will incorporate them"
            fi
        fi

        # Check for user-review.md feedback
        if [ -f "./.ralph/user-review.md" ]; then
            REVIEW_LINES=$(wc -l < "./.ralph/user-review.md" 2>/dev/null || echo "0")
            if [ "$REVIEW_LINES" -gt 1 ]; then
                echo -e "  ${C_PRIMARY}ℹ${C_RESET}  User review feedback detected ($REVIEW_LINES lines)"
            fi
        fi

        if ! run_single_iteration "./.ralph/prompts/spec/refine.md" $TOTAL_ITERATIONS "REFINE ($REFINE_ITERATION/$SPEC_REFINE_ITERS)"; then
            echo -e "  ${C_ERROR}✗${C_RESET} Refine iteration failed"
            if check_circuit_breaker; then
                break
            fi
        fi
    done

    echo -e "  ${C_SUCCESS}✓${C_RESET} Refine phase complete ($REFINE_ITERATION iterations)"

    # ─────────────────────────────────────────────────────────────────────
    # PHASE: DEBATE (replaces single-reviewer REVIEW)
    # ─────────────────────────────────────────────────────────────────────
    run_debate_phase

    # ─────────────────────────────────────────────────────────────────────
    # PHASE: REVIEW-FIX (conditional)
    # ─────────────────────────────────────────────────────────────────────
    SPEC_REVIEW_FILE="./.ralph/spec_review.md"
    SHOULD_RUN_SPEC_FIX=false
    if [ -f "$SPEC_REVIEW_FILE" ]; then
        SPEC_FIX_BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$SPEC_REVIEW_FILE" 2>/dev/null) || SPEC_FIX_BLOCKING=0
        SPEC_FIX_ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$SPEC_REVIEW_FILE" 2>/dev/null) || SPEC_FIX_ATTENTION=0
        if [ "$SPEC_FIX_BLOCKING" -gt 0 ] || [ "$SPEC_FIX_ATTENTION" -gt 0 ]; then
            SHOULD_RUN_SPEC_FIX=true
        fi
    fi

    if [ "$SHOULD_RUN_SPEC_FIX" = true ]; then
        print_phase_banner "SPEC REVIEW-FIX" $SPEC_REVIEWFIX_ITERS
        echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Issues to fix: ${C_ERROR}❌ Blocking: $SPEC_FIX_BLOCKING${C_RESET}  ${C_WARNING}⚠️ Attention: $SPEC_FIX_ATTENTION${C_RESET}"

        REVIEWFIX_ITERATION=0
        while [ $REVIEWFIX_ITERATION -lt $SPEC_REVIEWFIX_ITERS ]; do
            REVIEWFIX_ITERATION=$((REVIEWFIX_ITERATION + 1))
            TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

            if ! run_single_iteration "./.ralph/prompts/spec/review_fix.md" $TOTAL_ITERATIONS "SPEC REVIEW-FIX ($REVIEWFIX_ITERATION/$SPEC_REVIEWFIX_ITERS)"; then
                echo -e "  ${C_ERROR}✗${C_RESET} Review-fix iteration failed"
                if check_circuit_breaker; then
                    break
                fi
            fi
        done

        echo -e "  ${C_SUCCESS}✓${C_RESET} Review-fix phase complete"
    else
        echo -e "  ${C_SUCCESS}✓${C_RESET} No blocking/attention issues — skipping review-fix"
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
    echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
    if [ "$SPEC_READY" = true ]; then
        echo -e "${C_SUCCESS}  🎉 Spec created and approved in $TOTAL_ITERATIONS iteration(s)${C_RESET}"
        echo -e "${C_SUCCESS}  Next: node .ralph/run.js $SPEC_NAME plan${C_RESET}"
    else
        echo -e "${C_WARNING}  ⚠ Spec needs your input before it can be approved${C_RESET}"
        echo -e "${C_WARNING}════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "${C_PRIMARY}  📋 WHAT TO DO NEXT:${C_RESET}"
        echo ""

        # Check for unanswered questions
        QUESTIONS_FILE="./.ralph/spec_questions.md"
        if [ -f "$QUESTIONS_FILE" ]; then
            UNANSWERED=$(grep -c '^A:$\|^A: *$' "$QUESTIONS_FILE" 2>/dev/null) || UNANSWERED=0
            if [ "$UNANSWERED" -gt 0 ]; then
                echo -e "  ${C_WARNING}1. Answer $UNANSWERED question(s) in:${C_RESET}"
                echo -e "     ${C_HIGHLIGHT}.ralph/spec_questions.md${C_RESET}"
                echo -e "     ${C_MUTED}(Find lines starting with 'A:' and add your answers)${C_RESET}"
                echo ""
            else
                echo -e "  ${C_SUCCESS}✓ All questions answered in .ralph/spec_questions.md${C_RESET}"
                echo ""
            fi
        fi

        # Check for review issues
        SPEC_REVIEW_FILE="./.ralph/spec_review.md"
        if [ -f "$SPEC_REVIEW_FILE" ]; then
            BLOCKING=$(grep -c '❌.*BLOCKING\|BLOCKING.*❌' "$SPEC_REVIEW_FILE" 2>/dev/null) || BLOCKING=0
            ATTENTION=$(grep -c '⚠️.*NEEDS ATTENTION\|NEEDS ATTENTION.*⚠️' "$SPEC_REVIEW_FILE" 2>/dev/null) || ATTENTION=0
            if [ "$BLOCKING" -gt 0 ] || [ "$ATTENTION" -gt 0 ]; then
                echo -e "  ${C_WARNING}2. Review issues found:${C_RESET}"
                echo -e "     ${C_HIGHLIGHT}.ralph/spec_review.md${C_RESET}"
                [ "$BLOCKING" -gt 0 ] && echo -e "     ${C_ERROR}❌ $BLOCKING blocking issue(s)${C_RESET}"
                [ "$ATTENTION" -gt 0 ] && echo -e "     ${C_WARNING}⚠️  $ATTENTION item(s) need attention${C_RESET}"
                echo ""
            fi
        fi

        # Optional feedback file
        echo -e "  ${C_PRIMARY}3. (Optional) Add general feedback in:${C_RESET}"
        echo -e "     ${C_HIGHLIGHT}.ralph/user-review.md${C_RESET}"
        echo ""

        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "  ${C_PRIMARY}▶ When ready, re-run:${C_RESET}"
        echo -e "     ${C_HIGHLIGHT}node .ralph/run.js $SPEC_NAME spec${C_RESET}"
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
    fi
    echo ""
    echo -e "  ${C_MUTED}Total time: $FINAL_FORMATTED | Errors: $ERROR_COUNT${C_RESET}"
    echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
}
