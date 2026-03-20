export function ralphError(code, message, suggestion) {
  return {
    isError: true,
    content: [{
      type: 'text',
      text: JSON.stringify({ error: { code, message, suggestion } })
    }]
  };
}

export const errors = {
  dockerNotRunning: () =>
    ralphError('DOCKER_NOT_RUNNING', 'Docker is not running', 'Start Docker Desktop and try again'),
  imageNotFound: (imageName) =>
    ralphError('IMAGE_NOT_FOUND', `Docker image "${imageName}" not found`, 'Run /ralph:setup to build the Docker image'),
  containerNotFound: (id) =>
    ralphError('CONTAINER_NOT_FOUND', `Container "${id}" not found`, 'Use ralph_status to list available containers'),
  containerStopped: (id, exitCode) =>
    ralphError('CONTAINER_STOPPED', `Container "${id}" has stopped (exit code ${exitCode})`, 'Check ralph_logs for details or ralph_result for outputs'),
  execTimeout: (id) =>
    ralphError('EXEC_TIMEOUT', `Command timed out on container "${id}"`, 'Check container health with ralph_status'),
  notInitialized: () =>
    ralphError('NOT_INITIALIZED', '.ralph directory not found in this repository', 'Run /ralph:setup to initialize Ralph'),
  noGitRepo: () =>
    ralphError('NO_GIT_REPO', 'Not a git repository', 'Navigate to a git repository and try again'),
};
