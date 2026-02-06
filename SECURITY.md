# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Ralph Wiggum, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please email security concerns to the maintainer or use [GitHub's private vulnerability reporting](https://github.com/cpdekker/ralph/security/advisories/new).

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Assessment**: Within 1 week
- **Fix**: Depends on severity, but we aim for prompt resolution

## Security Considerations

Ralph Wiggum runs AI agents in Docker containers that have access to your codebase and Git credentials. Users should be aware of the following:

### Credentials

- **Never commit `.ralph/.env`** to version control. The `.gitignore` excludes it by default.
- Use **minimal-scope tokens** for Git access (e.g., only the repositories Ralph needs).
- Rotate API keys and Git tokens regularly.
- The Docker entrypoint stores Git credentials in `~/.git-credentials` inside the container. This is isolated to the container's lifecycle and is destroyed when the container exits.

### Docker Isolation

- Ralph runs inside a Docker container, providing process-level isolation from your host system.
- The container has access to your project directory (mounted as `/workspace` in foreground mode, or cloned in background mode).
- Review the `Dockerfile` and `entrypoint.sh` to understand exactly what the container has access to.

### AI Agent Behavior

- Ralph uses `--dangerously-skip-permissions` to allow Claude Code to operate autonomously inside the container. This means the AI agent can read, write, and execute files within the container.
- The circuit breaker limits runaway iterations, but does not limit what the agent can do within a single iteration.
- Always review Ralph's commits before merging to your main branch.

### Best Practices

1. Run Ralph in Docker (not directly on your host machine)
2. Use repository-scoped Git tokens with minimal permissions
3. Review all generated code before merging
4. Keep your Docker image updated for security patches
5. Do not store secrets in spec files or AGENTS.md

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
