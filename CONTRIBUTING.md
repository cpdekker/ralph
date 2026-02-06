# Contributing to Ralph Wiggum

Thank you for your interest in contributing to Ralph! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Issues

- Use [GitHub Issues](https://github.com/cpdekker/ralph/issues) to report bugs or request features
- Search existing issues before creating a new one
- Include steps to reproduce for bug reports
- Include your environment details (OS, Docker version, Node.js version)

### Submitting Changes

1. Fork the repository
2. Create a feature branch from `main` (`git checkout -b feature/my-change`)
3. Make your changes
4. Test your changes (see below)
5. Commit with clear, descriptive messages
6. Push to your fork and open a Pull Request

### Pull Request Guidelines

- Keep PRs focused on a single change
- Include a clear description of what the PR does and why
- Update documentation if your change affects user-facing behavior
- Ensure shell scripts maintain LF line endings (enforced by `.gitattributes`)

### Testing Your Changes

Since Ralph is a framework that orchestrates Docker containers and Claude Code, testing involves:

1. **Script syntax**: Ensure shell scripts pass `bash -n` syntax checks
2. **Node.js scripts**: Verify `run.js`, `setup.js`, and `build.js` run without errors
3. **Docker**: Verify the Docker image builds successfully (`node .ralph/docker/build.js`)
4. **End-to-end**: Run Ralph in debug mode against a sample spec to verify the loop works

### Code Style

- **Shell scripts**: Use `bash`, quote variables, use `set -e` where appropriate
- **JavaScript**: Use `const`/`let` (no `var`), consistent indentation (4 spaces)
- **Markdown**: Follow existing formatting patterns

### What to Contribute

Good first contributions:
- Documentation improvements
- New specialist reviewer prompts
- Bug fixes in the loop script or Node.js entry points
- Support for additional Git hosting platforms (GitLab, Bitbucket)

## Code of Conduct

Be respectful and constructive. We are all here to build something useful.

## Questions?

Open a [Discussion](https://github.com/cpdekker/ralph/discussions) or file an issue.
