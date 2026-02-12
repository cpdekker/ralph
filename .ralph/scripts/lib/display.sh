#!/bin/bash
# Ralph Wiggum - Display & Formatting Utilities
# Sourced by loop.sh — do not run directly.

# ASCII art digits for turn display
print_turn_banner() {
    local num=$1

    # Define each digit as an array of lines (8 lines tall)
    local d0=(
        "  ██████  "
        " ██    ██ "
        " ██    ██ "
        " ██    ██ "
        " ██    ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d1=(
        "    ██    "
        "   ███    "
        "    ██    "
        "    ██    "
        "    ██    "
        "    ██    "
        "  ██████  "
        "          "
    )
    local d2=(
        "  ██████  "
        " ██    ██ "
        "       ██ "
        "   █████  "
        "  ██      "
        " ██       "
        " ████████ "
        "          "
    )
    local d3=(
        "  ██████  "
        " ██    ██ "
        "       ██ "
        "   █████  "
        "       ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d4=(
        " ██    ██ "
        " ██    ██ "
        " ██    ██ "
        " ████████ "
        "       ██ "
        "       ██ "
        "       ██ "
        "          "
    )
    local d5=(
        " ████████ "
        " ██       "
        " ██       "
        " ███████  "
        "       ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d6=(
        "  ██████  "
        " ██       "
        " ██       "
        " ███████  "
        " ██    ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d7=(
        " ████████ "
        "       ██ "
        "      ██  "
        "     ██   "
        "    ██    "
        "    ██    "
        "    ██    "
        "          "
    )
    local d8=(
        "  ██████  "
        " ██    ██ "
        " ██    ██ "
        "  ██████  "
        " ██    ██ "
        " ██    ██ "
        "  ██████  "
        "          "
    )
    local d9=(
        "  ██████  "
        " ██    ██ "
        " ██    ██ "
        "  ███████ "
        "       ██ "
        "       ██ "
        "  ██████  "
        "          "
    )

    # TURN text (8 lines tall)
    local turn=(
        " ████████ ██    ██ ██████  ███    ██ "
        "    ██    ██    ██ ██   ██ ████   ██ "
        "    ██    ██    ██ ██   ██ ██ ██  ██ "
        "    ██    ██    ██ ██████  ██  ██ ██ "
        "    ██    ██    ██ ██   ██ ██   ████ "
        "    ██    ██    ██ ██   ██ ██    ███ "
        "    ██     ██████  ██   ██ ██     ██ "
        "                                     "
    )

    # Colon (8 lines tall)
    local colon=(
        "    "
        " ██ "
        " ██ "
        "    "
        " ██ "
        " ██ "
        "    "
        "    "
    )

    # Get digits of the number
    local digits=()
    local temp_num=$num
    if [ $temp_num -eq 0 ]; then
        digits=(0)
    else
        while [ $temp_num -gt 0 ]; do
            digits=($((temp_num % 10)) "${digits[@]}")
            temp_num=$((temp_num / 10))
        done
    fi

    echo ""
    echo ""
    echo -e "\033[1;33m" # Bold yellow

    # Print each line
    for line in 0 1 2 3 4 5 6 7; do
        local output="${turn[$line]}${colon[$line]}"

        # Add each digit
        for digit in "${digits[@]}"; do
            case $digit in
                0) output+="${d0[$line]}" ;;
                1) output+="${d1[$line]}" ;;
                2) output+="${d2[$line]}" ;;
                3) output+="${d3[$line]}" ;;
                4) output+="${d4[$line]}" ;;
                5) output+="${d5[$line]}" ;;
                6) output+="${d6[$line]}" ;;
                7) output+="${d7[$line]}" ;;
                8) output+="${d8[$line]}" ;;
                9) output+="${d9[$line]}" ;;
            esac
        done

        echo "    $output"
    done

    echo -e "\033[0m" # Reset color
    echo ""
    echo ""
}

# Print a spinner while waiting for a background process
spin() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while ps -p $pid > /dev/null 2>&1; do
        for i in $(seq 0 9); do
            printf "\r  \033[1;36m${spinstr:$i:1}\033[0m Working... "
            sleep $delay
        done
    done
    printf "\r                      \r"
}

# Format seconds into human-readable time (e.g., "1h 23m 45s")
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# Generate per-iteration summary with timing and git info
generate_summary() {
    local log_file=$1
    local iteration=$2
    local turn_start=$3

    # Calculate timing
    local now=$(date +%s)
    local turn_duration=$((now - turn_start))
    local total_elapsed=$((now - LOOP_START_TIME))
    local turn_formatted=$(format_duration $turn_duration)
    local total_formatted=$(format_duration $total_elapsed)

    echo ""
    echo -e "\033[1;36m┌────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;36m│  TURN $iteration SUMMARY                                            │\033[0m"
    echo -e "\033[1;36m└────────────────────────────────────────────────────────────┘\033[0m"
    echo ""

    echo -e "  \033[1;35m⏱\033[0m  Turn duration:  $turn_formatted"
    echo -e "  \033[1;35m⏱\033[0m  Total elapsed:  $total_formatted"
    echo ""

    # Count files modified (look for write/edit operations)
    local files_changed=$(grep -o '"tool":"write"\|"tool":"str_replace_editor"\|"tool":"create"\|"tool":"edit"' "$log_file" 2>/dev/null | wc -l)

    # Look for git commits
    local commits=$(grep -o 'git commit' "$log_file" 2>/dev/null | wc -l)

    # Look for test runs
    local tests=$(grep -o 'npm test\|npm run test\|npx nx test\|jest\|vitest' "$log_file" 2>/dev/null | wc -l)

    echo -e "  \033[1;32m✓\033[0m Files touched: ~$files_changed"
    echo -e "  \033[1;32m✓\033[0m Git commits: $commits"
    echo -e "  \033[1;32m✓\033[0m Test runs: $tests"
    echo ""

    # Show recent git log if there were commits
    if [ $commits -gt 0 ]; then
        echo -e "  \033[1;33mRecent commits:\033[0m"
        git log --oneline -3 2>/dev/null | sed 's/^/    /'
        echo ""
    fi

    # Show changed files from git status
    local changed_files=$(git diff --name-only HEAD~1 2>/dev/null | head -10)
    if [ -n "$changed_files" ]; then
        echo -e "  \033[1;33mChanged files:\033[0m"
        echo "$changed_files" | sed 's/^/    /'
        echo ""
    fi

    echo -e "\033[1;36m────────────────────────────────────────────────────────────\033[0m"
    echo ""
}

# Print cycle banner (full mode)
print_cycle_banner() {
    local cycle_num=$1
    echo ""
    echo ""
    echo -e "\033[1;35m╔════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║                      CYCLE $cycle_num                              ║\033[0m"
    echo -e "\033[1;35m╠════════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;35m║  plan($FULL_PLAN_ITERS) → build($FULL_BUILD_ITERS) → review($FULL_REVIEW_ITERS) → fix($FULL_REVIEWFIX_ITERS) → distill($FULL_DISTILL_ITERS) → check  ║\033[0m"
    echo -e "\033[1;35m╚════════════════════════════════════════════════════════════╝\033[0m"
    echo ""
}

# Print phase banner
print_phase_banner() {
    local phase_name=$1
    local phase_iters=$2
    echo ""
    echo -e "\033[1;36m┌────────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;36m│  $phase_name PHASE ($phase_iters iterations)                       \033[0m"
    echo -e "\033[1;36m└────────────────────────────────────────────────────────────┘\033[0m"
    echo ""
}
