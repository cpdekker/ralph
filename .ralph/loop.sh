#!/bin/bash
# Usage: ./loop.sh <spec-name> [plan|build] [max_iterations]
# Examples:
#   ./loop.sh my-feature              # Build mode, 10 iterations
#   ./loop.sh my-feature plan         # Plan mode, 5 iterations
#   ./loop.sh my-feature build 20     # Build mode, 20 iterations
#   ./loop.sh my-feature plan 10      # Plan mode, 10 iterations

# First argument is required: spec name
SPEC_NAME="$1"
if [ -z "$SPEC_NAME" ]; then
    echo "Error: Spec name is required"
    echo "Usage: ./loop.sh <spec-name> [plan|build] [max_iterations]"
    exit 1
fi

# Verify spec file exists
SPEC_FILE="./.ralph/specs/${SPEC_NAME}.md"
if [ ! -f "$SPEC_FILE" ]; then
    echo "Error: Spec file not found: $SPEC_FILE"
    echo "Available specs:"
    ls -1 ./.ralph/specs/*.md 2>/dev/null | grep -v active.md | xargs -I {} basename {} .md | sed 's/^/  - /'
    exit 1
fi

# Copy spec to active.md
ACTIVE_SPEC="./.ralph/specs/active.md"
echo "Copying $SPEC_FILE to $ACTIVE_SPEC"
cp "$SPEC_FILE" "$ACTIVE_SPEC"

# Parse mode (second argument)
if [ "$2" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="./.ralph/prompts/plan.md"
    MAX_ITERATIONS=${3:-5}
elif [ "$2" = "build" ]; then
    MODE="build"
    PROMPT_FILE="./.ralph/prompts/build.md"
    MAX_ITERATIONS=${3:-10}
elif [[ "$2" =~ ^[0-9]+$ ]]; then
    # Second arg is a number, treat as iterations for build mode
    MODE="build"
    PROMPT_FILE="./.ralph/prompts/build.md"
    MAX_ITERATIONS=$2
else
    # Default to build mode
    MODE="build"
    PROMPT_FILE="./.ralph/prompts/build.md"
    MAX_ITERATIONS=${2:-10}
fi

ITERATION=0

# Set up branch based on spec name
TARGET_BRANCH="ralph/$SPEC_NAME"
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]; then
    echo "Current branch '$CURRENT_BRANCH' does not match target '$TARGET_BRANCH'"

    # Check if target branch exists locally
    if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
        echo "Switching to existing branch: $TARGET_BRANCH"
        git checkout "$TARGET_BRANCH"
    else
        # Check if it exists on remote
        if git ls-remote --exit-code --heads origin "$TARGET_BRANCH" >/dev/null 2>&1; then
            echo "Checking out remote branch: $TARGET_BRANCH"
            git checkout -b "$TARGET_BRANCH" "origin/$TARGET_BRANCH"
        else
            echo "Creating new branch: $TARGET_BRANCH"
            git checkout -b "$TARGET_BRANCH"
        fi
    fi

    CURRENT_BRANCH=$(git branch --show-current)
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Spec:   $SPEC_NAME"
echo "Mode:   $MODE"
echo "Prompt: $PROMPT_FILE"
echo "Branch: $CURRENT_BRANCH"
[ $MAX_ITERATIONS -gt 0 ] && echo "Max:    $MAX_ITERATIONS iterations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verify prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: $PROMPT_FILE not found"
    exit 1
fi

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo "Reached max iterations: $MAX_ITERATIONS"
        break
    fi

    # Run Ralph iteration with selected prompt
    # -p: Headless mode (non-interactive, reads from stdin)
    # --dangerously-skip-permissions: Auto-approve all tool calls (YOLO mode)
    # --output-format=stream-json: Structured output for logging/monitoring
    # --model opus: Primary agent uses Opus for complex reasoning (task selection, prioritization)
    #               Can use 'sonnet' in build mode for speed if plan is clear and tasks well-defined
    # --verbose: Detailed execution logging
    cat "$PROMPT_FILE" | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        --model opus \
        --verbose

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" || {
        echo "Failed to push. Creating remote branch..."
        git push -u origin "$CURRENT_BRANCH"
    }

    ITERATION=$((ITERATION + 1))
    echo -e "\n\n======================== LOOP $ITERATION ========================\n"
done
