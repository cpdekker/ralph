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

# Run completion check to determine if the spec is fully implemented.
# Invokes completion_check.md prompt and parses the JSON response.
# Returns: 0 if complete, 1 if not complete
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

    if [ "$is_complete" = "true" ]; then
        echo ""
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_SUCCESS}  ✅ IMPLEMENTATION COMPLETE!${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_SUCCESS}  Confidence: ${confidence}${C_RESET}"
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        [ -n "$reason" ] && echo -e "  ${C_PRIMARY}$reason${C_RESET}"
        echo ""
        return 0  # Complete
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
