import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';

import * as setupTool from './tools/setup.js';
import * as startTool from './tools/start.js';
import * as statusTool from './tools/status.js';
import * as logsTool from './tools/logs.js';
import * as steerTool from './tools/steer.js';
import * as controlTool from './tools/control.js';
import * as resultTool from './tools/result.js';

const tools = [setupTool, startTool, statusTool, logsTool, steerTool, controlTool, resultTool];
const toolMap = new Map(tools.map(t => [t.definition.name, t]));

const server = new Server(
  { name: 'ralph', version: '0.1.0' },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: tools.map(t => ({
    name: t.definition.name,
    description: t.definition.description,
    inputSchema: t.definition.inputSchema
  }))
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const tool = toolMap.get(request.params.name);
  if (!tool) {
    return { content: [{ type: 'text', text: `Unknown tool: ${request.params.name}` }], isError: true };
  }
  try {
    return await tool.handler(request.params.arguments || {});
  } catch (err) {
    return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
