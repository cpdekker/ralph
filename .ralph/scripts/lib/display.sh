#!/bin/bash
# Ralph Wiggum - Display & Formatting Utilities
# Sourced by loop.sh — do not run directly.

# ═══════════════════════════════════════════════════════════════════════════════
# SIMPSONS COLOR PALETTE — Semantic color variables
# ═══════════════════════════════════════════════════════════════════════════════

C_RESET='\033[0m'
C_BRIGHT='\033[1m'
C_BRAND='\033[1;33m'       # Simpsons Yellow — branding, turn banners
C_PRIMARY='\033[1;36m'     # Marge Blue/Cyan — info, prompts, progress
C_SUCCESS='\033[1;32m'     # Springfield Green — checkmarks, success
C_ERROR='\033[1;31m'       # Bart Red — errors, failures
C_WARNING='\033[1;33m'     # Homer Yellow — warnings, caution
C_ACCENT='\033[1;35m'      # Krusty Magenta — headers, phase banners
C_MUTED='\033[2m'          # Dim — secondary text, separators
C_HIGHLIGHT='\033[1;37m'   # Bright White — emphasis

# Specialist review colors
C_SEC='\033[1;31m'         # Security — red
C_UX='\033[1;35m'          # UX — magenta
C_DB='\033[1;36m'          # DB — cyan
C_PERF='\033[1;32m'        # Performance — green
C_API='\033[1;34m'         # API — blue
C_QA='\033[1;33m'          # QA — yellow

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

ralph_success() { echo -e "  ${C_SUCCESS}\u2713${C_RESET} $1"; }
ralph_error()   { echo -e "  ${C_ERROR}\u2717${C_RESET} $1"; }
ralph_warn()    { echo -e "  ${C_WARNING}\u26A0${C_RESET} $1"; }
ralph_info()    { echo -e "  ${C_PRIMARY}\u2139${C_RESET}  $1"; }
ralph_hint()    { echo -e "  ${C_MUTED}Tip: $1${C_RESET}"; }
ralph_separator() { echo -e "  ${C_MUTED}$(printf '─%.0s' {1..50})${C_RESET}"; }

ralph_header() {
    local msg=$1
    echo ""
    echo -e "  ${C_ACCENT}${msg}${C_RESET}"
    echo -e "  ${C_MUTED}$(printf '─%.0s' {1..50})${C_RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# STARTUP INFO BLOCK (for loop.sh startup section)
# ═══════════════════════════════════════════════════════════════════════════════

ralph_startup_info() {
    local spec=$1
    local mode=$2
    local branch=$3
    local verbose=$4

    echo -e "${C_MUTED}$(printf '━%.0s' {1..40})${C_RESET}"
    echo -e "${C_MUTED}  spec${C_RESET}      $spec"
    echo -e "${C_MUTED}  mode${C_RESET}      $mode"
    echo -e "${C_MUTED}  branch${C_RESET}    $branch"
    echo -e "${C_MUTED}  verbose${C_RESET}   $verbose"
}

# Compact Simpsons-themed turn banner
print_turn_banner() {
    local num=$1
    echo ""
    echo -e "${C_BRAND}  ━━━━━━━━━━━━━━━━━━━━ TURN ${num} ━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo ""
}

# Print a donut-eating spinner while waiting for a background process
# Homer's donut — Simpsons-themed animation
spin() {
    local pid=$1
    local msg=${2:-"Working..."}
    local delay=0.2
    local frames=('(O)' '(O)' '(C)' '(c)' '(.)' '( )' '( )' '(o)')
    local num_frames=${#frames[@]}
    local i=0
    while ps -p $pid > /dev/null 2>&1; do
        printf "\r  ${C_BRAND}${frames[$i]}${C_RESET} ${msg} "
        i=$(( (i + 1) % num_frames ))
        sleep $delay
    done
    printf "\r$(printf ' %.0s' {1..80})\r"
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

    ralph_header "Turn $iteration Summary"

    echo -e "  ${C_ACCENT}⏱${C_RESET}  Turn duration:  $turn_formatted"
    echo -e "  ${C_ACCENT}⏱${C_RESET}  Total elapsed:  $total_formatted"
    echo ""

    # Count files modified (look for write/edit operations)
    local files_changed=$(grep -o '"tool":"write"\|"tool":"str_replace_editor"\|"tool":"create"\|"tool":"edit"' "$log_file" 2>/dev/null | wc -l)

    # Look for git commits
    local commits=$(grep -o 'git commit' "$log_file" 2>/dev/null | wc -l)

    # Look for test runs
    local tests=$(grep -o 'npm test\|npm run test\|npx nx test\|jest\|vitest' "$log_file" 2>/dev/null | wc -l)

    echo -e "  ${C_SUCCESS}✓${C_RESET} Files touched: ~$files_changed"
    echo -e "  ${C_SUCCESS}✓${C_RESET} Git commits: $commits"
    echo -e "  ${C_SUCCESS}✓${C_RESET} Test runs: $tests"
    echo ""

    # Show recent git log if there were commits
    if [ $commits -gt 0 ]; then
        echo -e "  ${C_WARNING}Recent commits:${C_RESET}"
        git log --oneline -3 2>/dev/null | sed 's/^/    /'
        echo ""
    fi

    # Show changed files from git status
    local changed_files=$(git diff --name-only HEAD~1 2>/dev/null | head -10)
    if [ -n "$changed_files" ]; then
        echo -e "  ${C_WARNING}Changed files:${C_RESET}"
        echo "$changed_files" | sed 's/^/    /'
        echo ""
    fi

    ralph_separator
    echo ""
}

# Print cycle banner (full mode)
print_cycle_banner() {
    local cycle_num=$1
    echo ""
    echo -e "${C_BRAND}  ━━━━━━━━━━━━━━━━━━ CYCLE ${cycle_num} ━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_MUTED}  plan(${FULL_PLAN_ITERS}) → build(${FULL_BUILD_ITERS}) → review(${FULL_REVIEW_ITERS}) → fix(${FULL_REVIEWFIX_ITERS}) → distill(${FULL_DISTILL_ITERS}) → check${C_RESET}"
    echo ""
}

# Print phase banner
print_phase_banner() {
    local phase_name=$1
    local phase_iters=$2
    echo ""
    echo -e "  ${C_ACCENT}▸ ${phase_name} PHASE${C_RESET} ${C_MUTED}(${phase_iters} iterations)${C_RESET}"
    echo ""
}
