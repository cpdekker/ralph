# Ralph Wiggum - Isolated Claude Code Loop Environment
FROM node:20-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    bash \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user (Claude Code refuses --dangerously-skip-permissions as root)
RUN useradd -m -s /bin/bash ralph

# Configure git defaults for ralph user
USER ralph
RUN git config --global user.email "ralph@docker.local" && \
    git config --global user.name "Ralph Wiggum (Docker)" && \
    git config --global --add safe.directory /workspace && \
    git config --global credential.helper store

# Switch back to root for entrypoint setup
USER root

# Copy entrypoint from build context
# The CLI builds with the lib/docker/ directory as context
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace

# Run as non-root user
USER ralph

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
