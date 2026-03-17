#!/bin/bash
# Ralph Wiggum - Review & Completion Check Functions
# Sourced by loop.sh — do not run directly.

# Determine which review specialist should handle the next item.
# Reads review_checklist.md and returns the specialist type based on tags.
# Returns: security, ux, db, perf, api, or qa (default)
get_next_review_specialist() {
    local checklist_file="./.ralph/review_checklist.md"

    if [ ! -f "$checklist_file" ]; then
        echo "qa"
        return
    fi

    # Find the first unchecked item and check its tag
    local next_item=$(grep -m1 '^\- \[ \]' "$checklist_file" 2>/dev/null || echo "")

    if echo "$next_item" | grep -qi '\[SEC'; then
        echo "security"
    elif echo "$next_item" | grep -qi '\[UX\]'; then
        echo "ux"
    elif echo "$next_item" | grep -qi '\[DB\]'; then
        echo "db"
    elif echo "$next_item" | grep -qi '\[PERF\]'; then
        echo "perf"
    elif echo "$next_item" | grep -qi '\[API\]'; then
        echo "api"
    else
        echo "qa"
    fi
}

# Run the Socratic cross-examination debate phase for code review.
# Called after specialist reviews are complete, before review-fix.
# Reads review.md findings, plans pairings, runs cross-examination rounds, synthesizes.
run_review_debate_phase() {
    local debate_dir="./.ralph/review_debate"
    local max_rounds=${REVIEW_DEBATE_ROUNDS:-3}

    # Guard: only run if review.md exists and has findings
    local review_file="./.ralph/review.md"
    if [ ! -f "$review_file" ]; then
        echo -e "  ${C_PRIMARY}ℹ${C_RESET}  No review.md found — skipping debate"
        return
    fi

    local total_findings=$(grep -c '❌\|⚠️\|💡' "$review_file" 2>/dev/null) || total_findings=0
    if [ "$total_findings" -eq 0 ]; then
        echo -e "  ${C_SUCCESS}✓${C_RESET} No review findings to debate — skipping"
        return
    fi

    # Calculate iteration count for display: setup(1) + rounds(N) + synthesize(1)
    local debate_total=$((2 + max_rounds))
    print_phase_banner "REVIEW DEBATE" $debate_total

    # Clean up previous debate state
    rm -rf "$debate_dir"
    mkdir -p "$debate_dir"

    echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Review has $total_findings findings — planning cross-examination"
    echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Max pairing rounds: $max_rounds"

    # ── SUB-PHASE: SETUP (moderator plans pairings) ──
    echo ""
    echo -e "  ${C_ACCENT}── Debate Setup ──${C_RESET}"
    TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

    if ! run_single_iteration "./.ralph/prompts/review/debate/setup.md" $TOTAL_ITERATIONS "DEBATE SETUP"; then
        echo -e "  ${C_ERROR}✗${C_RESET} Debate setup failed"
        if check_circuit_breaker; then
            return
        fi
    fi

    # Parse pairings from debate_plan.md
    local pairings_line=""
    if [ -f "$debate_dir/debate_plan.md" ]; then
        pairings_line=$(grep '^## PAIRINGS=' "$debate_dir/debate_plan.md" 2>/dev/null | sed 's/^## PAIRINGS=//')
    fi

    if [ -z "$pairings_line" ]; then
        echo -e "  ${C_ERROR}✗${C_RESET} Could not parse pairings from debate_plan.md — falling back to security:api,qa:antagonist,db:perf"
        pairings_line="security:api,qa:antagonist,db:perf"
    fi

    # Split into array of pairings
    IFS=',' read -ra DEBATE_PAIRINGS <<< "$pairings_line"
    local num_pairings=${#DEBATE_PAIRINGS[@]}

    # Cap at max_rounds
    if [ "$num_pairings" -gt "$max_rounds" ]; then
        num_pairings=$max_rounds
        echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Capping at $max_rounds rounds (${#DEBATE_PAIRINGS[@]} planned)"
    fi

    echo -e "  ${C_SUCCESS}✓${C_RESET} Debate setup complete — $num_pairings pairing rounds planned"

    # ── SUB-PHASE: CROSS-EXAMINATION ROUNDS ──
    echo ""
    echo -e "  ${C_ACCENT}── Cross-Examination ──${C_RESET}"

    local round=0
    while [ "$round" -lt "$num_pairings" ]; do
        round=$((round + 1))
        local pairing="${DEBATE_PAIRINGS[$((round - 1))]}"
        local specialist_a="${pairing%%:*}"
        local specialist_b="${pairing##*:}"

        TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))
        echo -e "  ${C_PRIMARY}ℹ${C_RESET}  Round $round/$num_pairings: $specialist_a vs $specialist_b"

        if ! run_single_iteration "./.ralph/prompts/review/debate/cross_examine.md" $TOTAL_ITERATIONS "CROSS-EXAMINE (round $round: $specialist_a vs $specialist_b)"; then
            echo -e "  ${C_ERROR}✗${C_RESET} Cross-examination round $round failed"
            if check_circuit_breaker; then
                return
            fi
        fi
    done

    echo -e "  ${C_SUCCESS}✓${C_RESET} Cross-examination complete ($num_pairings rounds)"

    # ── SUB-PHASE: SYNTHESIZE (merge debate findings into review.md) ──
    echo ""
    echo -e "  ${C_ACCENT}── Synthesis ──${C_RESET}"
    TOTAL_ITERATIONS=$((TOTAL_ITERATIONS + 1))

    if ! run_single_iteration "./.ralph/prompts/review/debate/synthesize.md" $TOTAL_ITERATIONS "DEBATE SYNTHESIZE"; then
        echo -e "  ${C_ERROR}✗${C_RESET} Synthesis failed"
        if check_circuit_breaker; then
            return
        fi
    fi

    echo -e "  ${C_SUCCESS}✓${C_RESET} Review debate complete — review.md updated with debate findings"
}

# Run completion check to determine if the spec is fully implemented.
# Invokes completion_check.md prompt and parses the JSON response.
# Returns: 0 if complete, 1 if not complete, 2 if blocked on user
run_completion_check() {
    echo ""
    echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_WARNING}  🔍 COMPLETION CHECK - Is the spec fully implemented?${C_RESET}"
    echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo ""

    local check_log="$TEMP_DIR/completion_check.log"
    local check_result

    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "./.ralph/prompts/completion_check.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  ${C_PRIMARY}⏳${C_RESET} Checking if implementation is complete..."

        check_result=$(cat "./.ralph/prompts/completion_check.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi

    # Parse Claude's JSON response using jq
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi

    # Strip markdown code fences if Claude wrapped the JSON in ```json ... ```
    json_text=$(echo "$json_text" | sed '/^```/d')

    local is_complete=$(echo "$json_text" | jq -r '.complete // false' 2>/dev/null)

    # Fallback: if jq failed to extract, try grep for "complete": true
    if [ -z "$is_complete" ] || [ "$is_complete" = "null" ]; then
        if echo "$json_text" | grep -q '"complete"[[:space:]]*:[[:space:]]*true'; then
            is_complete="true"
        else
            is_complete="false"
        fi
    fi
    local confidence=$(echo "$json_text" | jq -r '.confidence // empty' 2>/dev/null)
    local reason=$(echo "$json_text" | jq -r '.reason // empty' 2>/dev/null)

    # Check for blocked_on_user
    local blocked_on_user=$(echo "$json_text" | jq -r '.blocked_on_user // false' 2>/dev/null)
    if [ -z "$blocked_on_user" ] || [ "$blocked_on_user" = "null" ]; then
        if echo "$json_text" | grep -q '"blocked_on_user"[[:space:]]*:[[:space:]]*true'; then
            blocked_on_user="true"
        else
            blocked_on_user="false"
        fi
    fi

    if [ "$is_complete" = "true" ]; then
        echo ""
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_SUCCESS}  ✅ IMPLEMENTATION COMPLETE!${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_SUCCESS}  Confidence: ${confidence}${C_RESET}"
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        [ -n "$reason" ] && echo -e "  ${C_PRIMARY}$reason${C_RESET}"
        echo ""
        return 0  # Complete
    elif [ "$blocked_on_user" = "true" ]; then
        echo ""
        echo -e "${C_ACCENT}════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_ACCENT}  🛑 BLOCKED ON USER — All agent work complete${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_ACCENT}  Confidence: ${confidence}${C_RESET}"
        echo -e "${C_ACCENT}════════════════════════════════════════════════════════════${C_RESET}"
        [ -n "$reason" ] && echo -e "  ${C_PRIMARY}$reason${C_RESET}"
        echo ""

        # Generate user-intervention.md from the completion check response
        create_user_intervention_file "$json_text"

        return 2  # Blocked on user
    else
        echo ""
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "${C_WARNING}  ⚠ Implementation not yet complete${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_WARNING}  Confidence: ${confidence}${C_RESET}"
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        [ -n "$reason" ] && echo -e "  ${C_PRIMARY}$reason${C_RESET}"
        echo ""
        return 1  # Not complete
    fi
}

# Create .ralph/user-intervention.md from completion check JSON.
# Parses the user_intervention field and writes a structured file
# that the user can fill in and Ralph will process on next run.
create_user_intervention_file() {
    local json_text=$1
    local intervention_file="./.ralph/user-intervention.md"

    local summary=$(echo "$json_text" | jq -r '.user_intervention.summary // "User intervention required to continue."' 2>/dev/null)
    local reason=$(echo "$json_text" | jq -r '.reason // ""' 2>/dev/null)

    cat > "$intervention_file" << INTERVENTIONEOF
# User Intervention Required

Ralph has completed all work it can do independently and is now blocked.

**Status:** $reason

**Summary:** $summary

---

## Action Items

INTERVENTIONEOF

    # Extract each intervention item from the JSON array
    local item_count=$(echo "$json_text" | jq -r '.user_intervention.items | length // 0' 2>/dev/null)

    if [ -n "$item_count" ] && [ "$item_count" -gt 0 ]; then
        local i=0
        while [ $i -lt $item_count ]; do
            local item_id=$(echo "$json_text" | jq -r ".user_intervention.items[$i].id // \"item-$i\"" 2>/dev/null)
            local item_type=$(echo "$json_text" | jq -r ".user_intervention.items[$i].type // \"question\"" 2>/dev/null)
            local item_question=$(echo "$json_text" | jq -r ".user_intervention.items[$i].question // \"\"" 2>/dev/null)
            local item_context=$(echo "$json_text" | jq -r ".user_intervention.items[$i].context // \"\"" 2>/dev/null)
            local item_blocks=$(echo "$json_text" | jq -r ".user_intervention.items[$i].blocks // [] | join(\", \")" 2>/dev/null)

            cat >> "$intervention_file" << ITEMEOF

### $((i + 1)). [$item_type] $item_id

**Question:** $item_question

**Context:** $item_context

**Blocks:** $item_blocks

**Your Response:**
<!-- Write your answer below, or place files in .ralph/references/ and reference them here -->


ITEMEOF
            i=$((i + 1))
        done
    else
        # Fallback: extract remaining items from the completion check
        local remaining=$(echo "$json_text" | jq -r '.remaining // [] | .[]' 2>/dev/null)
        if [ -n "$remaining" ]; then
            echo "$remaining" | while IFS= read -r item; do
                echo "- $item" >> "$intervention_file"
            done
            echo "" >> "$intervention_file"
            echo "**Please provide guidance on how to unblock these items.**" >> "$intervention_file"
        fi
    fi

    cat >> "$intervention_file" << 'FOOTEREOF'

---

## How to Respond

1. **Answer inline** — Fill in the "Your Response" sections above
2. **Provide files** — Drop reference data into `.ralph/references/` (e.g., database exports, API responses, config files)
3. **Restart Ralph** — Run Ralph again after providing your answers. The planning phase will incorporate your responses.

**Tip:** Name reference files descriptively (e.g., `metric-mappings.json`, `source-tables.csv`) so Ralph can match them to the questions above.

---

_This file was auto-generated by Ralph's completion check. It will be cleared after your responses are incorporated into the next planning cycle._
FOOTEREOF

    # Stage and commit the intervention file
    git add "$intervention_file"
    git commit -m "ralph: blocked on user — intervention required" 2>/dev/null || true
    git push origin "$(git branch --show-current)" 2>/dev/null || true

    echo -e "  ${C_ACCENT}📋${C_RESET} Created ${C_HIGHLIGHT}.ralph/user-intervention.md${C_RESET} — review and provide answers to unblock"
}

# Run research completion check to determine if research is sufficient.
# Returns: 0 if complete, 1 if not complete
run_research_completion_check() {
    echo ""
    echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_WARNING}  🔍 RESEARCH COMPLETION CHECK - Is research sufficient?${C_RESET}"
    echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo ""

    local check_log="$TEMP_DIR/research_completion.log"
    local check_result

    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "./.ralph/prompts/research/completion.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  ${C_PRIMARY}⏳${C_RESET} Checking if research is complete..."

        check_result=$(cat "./.ralph/prompts/research/completion.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi

    # Parse Claude's JSON response using jq
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi

    # Strip markdown code fences if present
    json_text=$(echo "$json_text" | sed '/^```/d')

    # Save the full JSON for the research_mode.sh to inspect
    echo "$json_text" > "./.ralph/research_completion.json"

    local is_complete=$(echo "$json_text" | jq -r '.complete // false' 2>/dev/null)

    # Fallback: if jq failed to extract, try grep
    if [ -z "$is_complete" ] || [ "$is_complete" = "null" ]; then
        if echo "$json_text" | grep -q '"complete"[[:space:]]*:[[:space:]]*true'; then
            is_complete="true"
        else
            is_complete="false"
        fi
    fi

    local confidence=$(echo "$json_text" | jq -r '.confidence // empty' 2>/dev/null)
    local recommendation=$(echo "$json_text" | jq -r '.recommendation // empty' 2>/dev/null)
    local quality_score=$(echo "$json_text" | jq -r '.quality_score // empty' 2>/dev/null)
    local blocking_gaps=$(echo "$json_text" | jq -r '.blocking_gaps // empty' 2>/dev/null)
    local docs_count=$(echo "$json_text" | jq -r '.documents_count // empty' 2>/dev/null)

    if [ "$is_complete" = "true" ]; then
        echo ""
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_SUCCESS}  ✅ RESEARCH COMPLETE!${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_SUCCESS}  Confidence: ${confidence}${C_RESET}"
        [ -n "$quality_score" ] && echo -e "${C_SUCCESS}  Quality: ${quality_score}/5${C_RESET}"
        [ -n "$docs_count" ] && echo -e "${C_SUCCESS}  Documents: ${docs_count}${C_RESET}"
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        [ -n "$recommendation" ] && echo -e "  ${C_PRIMARY}$recommendation${C_RESET}"
        echo ""

        # Stage the completion result
        git add .ralph/research_completion.json 2>/dev/null
        return 0  # Complete
    else
        echo ""
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "${C_WARNING}  ⚠ Research not yet complete${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_WARNING}  Confidence: ${confidence}${C_RESET}"
        [ -n "$blocking_gaps" ] && echo -e "${C_WARNING}  Blocking gaps: ${blocking_gaps}${C_RESET}"
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        [ -n "$recommendation" ] && echo -e "  ${C_PRIMARY}$recommendation${C_RESET}"
        echo ""

        # Stage the completion result
        git add .ralph/research_completion.json 2>/dev/null
        return 1  # Not complete
    fi
}

# Run spec signoff check to determine if a spec is ready for implementation.
# Returns: 0 if ready, 1 if not ready
run_spec_signoff_check() {
    echo ""
    echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_WARNING}  🔍 SPEC SIGN-OFF CHECK - Is the spec ready for implementation?${C_RESET}"
    echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo ""

    local check_log="$TEMP_DIR/spec_signoff.log"
    local check_result

    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "./.ralph/prompts/spec/signoff.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  ${C_PRIMARY}⏳${C_RESET} Checking if spec is ready for implementation..."

        check_result=$(cat "./.ralph/prompts/spec/signoff.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi

    # Parse Claude's JSON response using jq
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi

    local is_ready=$(echo "$json_text" | jq -r '.ready // false' 2>/dev/null)
    local confidence=$(echo "$json_text" | jq -r '.confidence // empty' 2>/dev/null)
    local recommendation=$(echo "$json_text" | jq -r '.recommendation // empty' 2>/dev/null)
    local sections_complete=$(echo "$json_text" | jq -r '.sections_complete // empty' 2>/dev/null)
    local sections_total=$(echo "$json_text" | jq -r '.sections_total // empty' 2>/dev/null)
    local blocking=$(echo "$json_text" | jq -r '.blocking_issues // empty' 2>/dev/null)
    local unanswered=$(echo "$json_text" | jq -r '.unanswered_questions // empty' 2>/dev/null)

    if [ "$is_ready" = "true" ]; then
        echo ""
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_SUCCESS}  ✅ SPEC APPROVED!${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_SUCCESS}  Confidence: ${confidence}${C_RESET}"
        [ -n "$sections_complete" ] && [ -n "$sections_total" ] && echo -e "${C_SUCCESS}  Sections: ${sections_complete}/${sections_total}${C_RESET}"
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        [ -n "$recommendation" ] && echo -e "  ${C_PRIMARY}$recommendation${C_RESET}"
        echo ""
        return 0  # Ready
    else
        echo ""
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "${C_WARNING}  ⚠ Spec not yet ready for implementation${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_WARNING}  Confidence: ${confidence}${C_RESET}"
        [ -n "$blocking" ] && echo -e "${C_WARNING}  Blocking issues: ${blocking}${C_RESET}"
        [ -n "$unanswered" ] && echo -e "${C_WARNING}  Unanswered questions: ${unanswered}${C_RESET}"
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        [ -n "$recommendation" ] && echo -e "  ${C_PRIMARY}$recommendation${C_RESET}"
        echo ""
        return 1  # Not ready
    fi
}
