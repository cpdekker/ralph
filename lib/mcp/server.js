#!/usr/bin/env node

const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { registerLoopTools } = require('./tools/loop');
const { registerStateTools } = require('./tools/state');

// Parse --repo-dir argument to set the working directory
const repoDirIdx = process.argv.indexOf('--repo-dir');
if (repoDirIdx !== -1 && process.argv[repoDirIdx + 1]) {
  process.chdir(process.argv[repoDirIdx + 1]);
}

async function main() {
  const server = new McpServer({
    name: 'ralph',
    version: '0.2.0',
  });

  // Register all tools
  registerLoopTools(server);
  registerStateTools(server);

  // Start listening on stdio
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error('Ralph MCP server error:', err);
  process.exit(1);
});
