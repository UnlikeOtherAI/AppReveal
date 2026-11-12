import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

export const cliPath = fileURLToPath(new URL('../../dist/index.js', import.meta.url));
export const textResult = (value: unknown) => ({ content: [{ type: 'text', text: JSON.stringify(value) }] });
export interface Rpc { id: number; method: string; params?: { name?: string; arguments?: Record<string, unknown> } }
export async function startServer(handler: (rpc: Rpc, req: IncomingMessage, res: ServerResponse) => unknown | Promise<unknown>) {
  const server = createServer(async (req, res) => {
    let body = '';
    for await (const chunk of req) body += chunk;
    const rpc = JSON.parse(body) as Rpc;
    try {
      const result = await handler(rpc, req, res);
      if (res.writableEnded || res.headersSent) return;
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ jsonrpc: '2.0', id: rpc.id, result }));
    } catch {
      res.statusCode = 500;
      res.end('Test server failure');
    }
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('No server port');
  return {
    url: `http://127.0.0.1:${address.port}/`,
    close: async () => { server.closeAllConnections(); server.close(); await once(server, 'close'); },
  };
}

export async function runCli(args: string[], sessionUrl?: string) {
  const env = { ...process.env };
  delete env.APPREVEAL_SESSION_URL;
  if (sessionUrl) env.APPREVEAL_SESSION_URL = sessionUrl;
  try {
    const result = await promisify(execFile)(process.execPath, [cliPath, ...args], { env, timeout: 15_000 });
    return { ...result, code: 0 };
  } catch (error) {
    const result = error as Error & { stdout: string; stderr: string; code: number };
    return { stdout: result.stdout, stderr: result.stderr, code: result.code };
  }
}

export async function startApp(options: { stringBatch?: boolean; batchFailure?: boolean; focusFailure?: boolean } = {}) {
  const token = randomBytes(24).toString('hex');
  const requests: Rpc[] = [];
  const state = { taps: 0, text: '', scroll: 0 };
  const elements = [
    { id: 'form.input', label: 'Name', type: 'textField', value: '', actions: ['type', 'clear'], frame: '0,0,100,30' },
    { id: 'form.submit', label: 'Submit', type: 'button', actions: ['tap'], frame: '0,50,100,30' },
    { id: 'form.disabled', label: 'Disabled', enabled: false, actions: ['tap'] },
    { id: 'form.same1', label: 'Duplicate', actions: ['tap'] },
    { id: 'form.same2', label: 'Duplicate', actions: ['tap'] },
  ];
  function tool(name: string, args: Record<string, unknown> = {}): unknown {
    switch (name) {
      case 'launch_context': return { platform: 'Windows', frameworkType: 'flutter', version: 'test-fixture' };
      case 'get_screen': return { screenKey: 'form.main' };
      case 'get_elements': return { elements, count: elements.length };
      case 'get_view_tree': return { views: [
        { accessibilityLabel: 'Submit', userInteraction: true, frame: '0,50,100,30' },
        { accessibilityLabel: 'Anonymous field', userInteraction: true, frame: '0,100,100,30' },
        { accessibilityLabel: 'Bad frame', userInteraction: true, frame: '0,0,-10,5' },
      ] };
      case 'get_state': return { ...state };
      case 'type_text': state.text += String(args.text); return { success: true };
      case 'tap_element': state.taps++; return { success: true };
      case 'tap_point': return options.focusFailure ? { success: false, error: 'Cannot focus' } : { success: true };
      case 'scroll': state.scroll++; return { success: true };
      case 'fail': return { error: 'Element unavailable', success: false };
      case 'batch': return { results: (args.actions as Array<{ tool: string; arguments?: Record<string, unknown> }>).map((action, index) => ({
        index, tool: action.tool, result: options.stringBatch ? JSON.stringify(tool(action.tool, action.arguments)) : tool(action.tool, action.arguments),
        ...(options.batchFailure && action.tool === 'get_elements' ? { success: false, error: 'Inventory unavailable' } : {}),
      })) };
      default: return { error: `Unknown tool: ${name}` };
    }
  }
  const server = await startServer((rpc, req, res) => {
    requests.push(rpc);
    if (req.headers.authorization !== `Bearer ${token}`) {
      res.statusCode = 401; res.end('Unauthorized'); return;
    }
    if (req.url?.includes('appreveal_session_token')) throw new Error('Token leaked in request URL');
    if (rpc.method === 'initialize') return { protocolVersion: '2025-06-18', serverInfo: { name: 'Fixture' }, capabilities: {} };
    if (rpc.method === 'tools/list') return { tools: [{ name: 'launch_context', inputSchema: { type: 'object' } }, { name: 'get_screen', inputSchema: { type: 'object' } }] };
    return textResult(tool(rpc.params?.name ?? '', rpc.params?.arguments));
  });
  return { ...server, sessionUrl: `${server.url}?appreveal_session_token=${token}`, token, state, requests };
}
