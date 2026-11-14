import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createSchedulrMcpServer } from '../mcp/schedulr-server.js';

export const config = {
  maxDuration: 30,
  runtime: 'nodejs'
};

function setCorsHeaders(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Accept, Mcp-Session-Id, MCP-Protocol-Version, Authorization'
  );
  res.setHeader('Access-Control-Max-Age', '86400');
}

function writeJsonRpcError(res, status, code, message) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  setCorsHeaders(res);
  res.end(JSON.stringify({ jsonrpc: '2.0', error: { code, message }, id: null }));
}

function isAuthorized(req) {
  const expected = process.env.MCP_API_KEY;
  if (!expected) return false;
  const header = req.headers.authorization || '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  return match?.[1] === expected;
}

export default async function handler(req, res) {
  setCorsHeaders(res);

  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return;
  }

  if (req.method !== 'POST') {
    writeJsonRpcError(res, 405, -32600, 'Only POST is supported');
    return;
  }

  if (!isAuthorized(req)) {
    writeJsonRpcError(res, 401, -32001, 'Missing or invalid bearer token');
    return;
  }

  const server = createSchedulrMcpServer();
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true
  });

  res.on('close', () => {
    transport.close();
    server.close();
  });

  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (error) {
    if (!res.headersSent) {
      writeJsonRpcError(res, 500, -32603, error instanceof Error ? error.message : 'MCP server error');
    }
  }
}
