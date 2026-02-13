#!/bin/bash
# Ralph Wiggum - Sub-Spec Decomposition Helpers
# Sourced by loop.sh — do not run directly.

# Check if a manifest.json exists for the current spec (decomposed spec)
check_manifest_exists() {
    local manifest_path="./.ralph/specs/${SPEC_NAME}/manifest.json"
    if [ -f "$manifest_path" ]; then
        return 0
    fi
    return 1
}

# Run spec_select.md prompt to pick the next sub-spec to work on.
# Parses the JSON response for action, sub_spec_name, and progress.
# Sets CURRENT_SUBSPEC global on success.
# Returns: 0=selected, 1=all_complete, 2=blocked
run_spec_select() {
    echo ""
    echo -e "${C_ACCENT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_ACCENT}  📋 SUB-SPEC SELECTION - Picking next sub-spec to work on${C_RESET}"
    echo -e "${C_ACCENT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo ""

    local select_log="$TEMP_DIR/spec_select.log"
    local select_result

    if [ "$VERBOSE" = true ]; then
        select_result=$(cat "./.ralph/prompts/spec_select.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$select_log")
    else
        echo -e "  ${C_PRIMARY}⏳${C_RESET} Selecting next sub-spec..."

        select_result=$(cat "./.ralph/prompts/spec_select.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$select_log")
    fi

    # Parse Claude's JSON response
    local json_text
    json_text=$(echo "$select_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$select_result"
    fi
    # Strip markdown code fences if Claude wrapped the JSON in ```json ... ```
    json_text=$(echo "$json_text" | sed '/^```/d')

    local action=$(echo "$json_text" | jq -r '.action // empty' 2>/dev/null)
    local sub_spec_name=$(echo "$json_text" | jq -r '.sub_spec_name // empty' 2>/dev/null)
    local sub_spec_title=$(echo "$json_text" | jq -r '.sub_spec_title // empty' 2>/dev/null)
    local progress_complete=$(echo "$json_text" | jq -r '.progress.complete // 0' 2>/dev/null)
    local progress_total=$(echo "$json_text" | jq -r '.progress.total // 0' 2>/dev/null)

    if [ "$action" = "select" ]; then
        echo ""
        echo -e "${C_SUCCESS}  ✓ Selected: $sub_spec_name — $sub_spec_title${C_RESET}"
        echo -e "${C_PRIMARY}  Progress: $progress_complete/$progress_total sub-specs complete${C_RESET}"
        echo ""
        CURRENT_SUBSPEC="$sub_spec_name"
        return 0  # Selected
    elif [ "$action" = "all_complete" ]; then
        echo ""
        echo -e "${C_SUCCESS}  ✓ All sub-specs complete! ($progress_total/$progress_total)${C_RESET}"
        echo ""
        return 1  # All complete
    elif [ "$action" = "blocked" ]; then
        local reason=$(echo "$json_text" | jq -r '.reason // "Unknown"' 2>/dev/null)
        echo ""
        echo -e "${C_ERROR}  ✗ Blocked: $reason${C_RESET}"
        echo ""
        return 2  # Blocked
    else
        echo ""
        echo -e "${C_ERROR}  ✗ Unexpected spec_select response: $action${C_RESET}"
        echo -e "${C_ERROR}  Raw result: $json_text${C_RESET}"
        echo ""
        return 2  # Treat as blocked
    fi
}

# Mark current sub-spec as complete in manifest.json
mark_subspec_complete() {
    local manifest_path="./.ralph/specs/${SPEC_NAME}/manifest.json"

    if [ ! -f "$manifest_path" ]; then
        echo -e "${C_ERROR}  ✗ Manifest not found: $manifest_path${C_RESET}"
        return 1
    fi

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local subspec_name="${CURRENT_SUBSPEC}"

    # Use jq to update the manifest
    local updated
    updated=$(jq --arg name "$subspec_name" --arg now "$now" '
        .updated_at = $now |
        (.sub_specs |= map(
            if .name == $name then
                .status = "complete" | .completed_at = $now
            else . end
        )) |
        .progress.complete = ([.sub_specs[] | select(.status == "complete")] | length) |
        .progress.in_progress = ([.sub_specs[] | select(.status == "in_progress")] | length) |
        .progress.pending = ([.sub_specs[] | select(.status == "pending")] | length)
    ' "$manifest_path" 2>/dev/null)
    local jq_exit=$?

    if [ $jq_exit -eq 0 ] && [ -n "$updated" ]; then
        echo "$updated" > "$manifest_path"
        echo -e "${C_SUCCESS}  ✓ Marked $subspec_name as complete${C_RESET}"

        git add "$manifest_path"
        git commit -m "Complete sub-spec: $subspec_name"
        git push origin "$CURRENT_BRANCH" 2>/dev/null || true
    else
        echo -e "${C_ERROR}  ✗ Failed to update manifest${C_RESET}"
        return 1
    fi
}

# Run master completion check for decomposed specs.
# Verifies that all sub-specs together cover the full master spec.
# Returns: 0 if complete, 1 if gaps remain
run_master_completion_check() {
    echo ""
    echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_WARNING}  🔍 MASTER COMPLETION CHECK - Verifying all sub-specs cover the full spec${C_RESET}"
    echo -e "${C_WARNING}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo ""

    local check_log="$TEMP_DIR/master_completion_check.log"
    local check_result

    if [ "$VERBOSE" = true ]; then
        check_result=$(cat "./.ralph/prompts/master_completion_check.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>&1 | tee "$check_log")
    else
        echo -e "  ${C_PRIMARY}⏳${C_RESET} Running master completion check..."

        check_result=$(cat "./.ralph/prompts/master_completion_check.md" | claude -p \
            --dangerously-skip-permissions \
            --output-format=json 2>"$check_log")
    fi

    # Parse Claude's JSON response
    local json_text
    json_text=$(echo "$check_result" | jq -r '.result // empty' 2>/dev/null)
    if [ -z "$json_text" ]; then
        json_text="$check_result"
    fi
    # Strip markdown code fences if Claude wrapped the JSON in ```json ... ```
    json_text=$(echo "$json_text" | sed '/^```/d')

    local is_complete=$(echo "$json_text" | jq -r '.complete // false' 2>/dev/null)
    local confidence=$(echo "$json_text" | jq -r '.confidence // empty' 2>/dev/null)
    local reason=$(echo "$json_text" | jq -r '.reason // empty' 2>/dev/null)

    if [ "$is_complete" = "true" ]; then
        echo ""
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_SUCCESS}  ✅ MASTER SPEC FULLY IMPLEMENTED!${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_SUCCESS}  Confidence: ${confidence}${C_RESET}"
        echo -e "${C_SUCCESS}════════════════════════════════════════════════════════════${C_RESET}"
        [ -n "$reason" ] && echo -e "  ${C_PRIMARY}$reason${C_RESET}"
        echo ""
        return 0  # Complete
    else
        echo ""
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "${C_WARNING}  ⚠ Master spec not yet fully satisfied${C_RESET}"
        [ -n "$confidence" ] && echo -e "${C_WARNING}  Confidence: ${confidence}${C_RESET}"
        echo -e "${C_WARNING}────────────────────────────────────────────────────────────${C_RESET}"
        [ -n "$reason" ] && echo -e "  ${C_PRIMARY}$reason${C_RESET}"

        # Show gaps if present
        local gaps=$(echo "$json_text" | jq -r '.gaps[]? // empty' 2>/dev/null)
        if [ -n "$gaps" ]; then
            echo ""
            echo -e "  ${C_WARNING}Gaps found:${C_RESET}"
            echo "$gaps" | while read -r gap; do
                echo -e "    • $gap"
            done
        fi
        echo ""
        return 1  # Not complete
    fi
}
