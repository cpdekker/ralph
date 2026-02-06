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
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;33m  🔍 COMPLETION CHECK - Is the spec fully implemented?\033[0m"
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    local check_log="$TEMP_DIR/completion_check.log"
    local check_result

    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "./.ralph/prompts/completion_check.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Checking if implementation is complete..."

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

    local is_complete=$(echo "$json_text" | jq -r '.complete // false' 2>/dev/null)
    local confidence=$(echo "$json_text" | jq -r '.confidence // empty' 2>/dev/null)
    local reason=$(echo "$json_text" | jq -r '.reason // empty' 2>/dev/null)

    if [ "$is_complete" = "true" ]; then
        echo ""
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        echo -e "\033[1;32m  ✅ IMPLEMENTATION COMPLETE!\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;32m  Confidence: ${confidence}\033[0m"
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        [ -n "$reason" ] && echo -e "  \033[1;36m$reason\033[0m"
        echo ""
        return 0  # Complete
    else
        echo ""
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        echo -e "\033[1;33m  ⚠ Implementation not yet complete\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;33m  Confidence: ${confidence}\033[0m"
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        [ -n "$reason" ] && echo -e "  \033[1;36m$reason\033[0m"
        echo ""
        return 1  # Not complete
    fi
}

# Run spec signoff check to determine if a spec is ready for implementation.
# Returns: 0 if ready, 1 if not ready
run_spec_signoff_check() {
    echo ""
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;33m  🔍 SPEC SIGN-OFF CHECK - Is the spec ready for implementation?\033[0m"
    echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""

    local check_log="$TEMP_DIR/spec_signoff.log"
    local check_result

    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "./.ralph/prompts/spec/signoff.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  \033[1;36m⏳\033[0m Checking if spec is ready for implementation..."

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
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        echo -e "\033[1;32m  ✅ SPEC APPROVED!\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;32m  Confidence: ${confidence}\033[0m"
        [ -n "$sections_complete" ] && [ -n "$sections_total" ] && echo -e "\033[1;32m  Sections: ${sections_complete}/${sections_total}\033[0m"
        echo -e "\033[1;32m════════════════════════════════════════════════════════════\033[0m"
        [ -n "$recommendation" ] && echo -e "  \033[1;36m$recommendation\033[0m"
        echo ""
        return 0  # Ready
    else
        echo ""
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        echo -e "\033[1;33m  ⚠ Spec not yet ready for implementation\033[0m"
        [ -n "$confidence" ] && echo -e "\033[1;33m  Confidence: ${confidence}\033[0m"
        [ -n "$blocking" ] && echo -e "\033[1;33m  Blocking issues: ${blocking}\033[0m"
        [ -n "$unanswered" ] && echo -e "\033[1;33m  Unanswered questions: ${unanswered}\033[0m"
        echo -e "\033[1;33m────────────────────────────────────────────────────────────\033[0m"
        [ -n "$recommendation" ] && echo -e "  \033[1;36m$recommendation\033[0m"
        echo ""
        return 1  # Not ready
    fi
}
