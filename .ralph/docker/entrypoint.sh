#!/bin/bash
# Configure git credentials if GIT_TOKEN is set
if [ -n "$GIT_TOKEN" ]; then
    echo "https://${GIT_USER:-git}:${GIT_TOKEN}@github.com" > ~/.git-credentials
    echo "Git credentials configured."
fi

# Background mode: clone repo instead of using mounted volume
if [ -n "$RALPH_REPO_URL" ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  🔄 BACKGROUND MODE - Cloning repository"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    
    # Clone to /home/ralph/repo (not /workspace which may be mounted)
    CLONE_DIR="/home/ralph/repo"
    
    if [ -d "$CLONE_DIR" ]; then
        echo "Removing existing clone..."
        rm -rf "$CLONE_DIR"
    fi
    
    echo "Cloning $RALPH_REPO_URL..."
    git clone "$RALPH_REPO_URL" "$CLONE_DIR"
    
    if [ $? -ne 0 ]; then
        echo "Failed to clone repository!"
        exit 1
    fi
    
    cd "$CLONE_DIR"
    
    # Handle branch setup
    if [ -n "$RALPH_BRANCH" ]; then
        echo "Setting up branch: $RALPH_BRANCH"
        
        # Check if branch exists on remote
        if git ls-remote --exit-code --heads origin "$RALPH_BRANCH" >/dev/null 2>&1; then
            echo "Checking out existing remote branch..."
            git checkout -b "$RALPH_BRANCH" "origin/$RALPH_BRANCH"
        else
            # Check if there's a base branch to start from
            if [ -n "$RALPH_BASE_BRANCH" ]; then
                echo "Creating new branch from $RALPH_BASE_BRANCH..."
                git checkout "$RALPH_BASE_BRANCH"
                git pull origin "$RALPH_BASE_BRANCH"
            fi
            echo "Creating new branch: $RALPH_BRANCH"
            git checkout -b "$RALPH_BRANCH"
        fi
    fi
    
    echo ""
    echo "Working directory: $(pwd)"
    echo "Branch: $(git branch --show-current)"
    echo ""
    
    # Change to clone directory for command execution
    export RALPH_WORKDIR="$CLONE_DIR"
    cd "$CLONE_DIR"
fi

# Execute the command passed to docker run
exec "$@"
