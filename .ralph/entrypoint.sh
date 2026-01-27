#!/bin/bash
# Configure git credentials if GIT_TOKEN is set
if [ -n "$GIT_TOKEN" ]; then
    echo "https://${GIT_USER:-git}:${GIT_TOKEN}@github.com" > ~/.git-credentials
    echo "Git credentials configured."
fi

# Execute the command passed to docker run
exec "$@"
