import { registerSessionUrl, requestCredentials, redactSecrets } from './auth.js';
import { discoverServices, extractCodes, matchDiscoveryRecord, type DiscoveryRecord } from './discovery.js';

export interface RequestOptions {
  method: string;
  params?: Record<string, unknown>;
  id?: string | number;
  timeoutMs?: number;
}

export interface ToolCallResult {
  request: JsonRpcRequest;
  response: JsonRpcResponse;
  decoded: unknown;
}

export interface InspectionResult {
  target: ResolvedTarget;
  initialize: JsonRpcResponse;
  launchContext?: ToolCallResult;
  deviceInfo?: ToolCallResult;
  tools: JsonRpcResponse;
}

export interface ResolvedTarget {
  selector: string;
  url: string;
  discovery?: DiscoveryRecord;
}

export interface JsonRpcRequest {
  jsonrpc: '2.0';
  id: string | number;
  method: string;
  params?: Record<string, unknown>;
}

export interface JsonRpcResponse {
  jsonrpc?: string;
  id?: string | number | null;
  result?: unknown;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
}

export interface ResolveTargetOptions {
  timeoutMs: number;
}

export interface ResolveTargetsOptions {
  selectors: string[];
  all: boolean;
  timeoutMs: number;
  platformFilters?: string[];
  probeDiscovery?: boolean;
}

let nextRequestId = 1;
const DEFAULT_REQUEST_TIMEOUT_MS = 15_000;
const DISCOVERY_PROBE_TIMEOUT_MS = 2_500;

export async function resolveTarget(selector: string, options: ResolveTargetOptions): Promise<ResolvedTarget> {
  const resolved = await resolveTargets({
    selectors: [selector],
    all: false,
    timeoutMs: options.timeoutMs,
  });
  return resolved[0];
}

export async function resolveTargets(options: ResolveTargetsOptions): Promise<ResolvedTarget[]> {
  const selected = options.selectors.length === 0 && !options.all && process.env.APPREVEAL_SESSION_URL
    ? [process.env.APPREVEAL_SESSION_URL]
    : options.selectors;
  // Register all credentials before discovery probes or platform filtering.
  if (process.env.APPREVEAL_SESSION_URL) registerSessionUrl(process.env.APPREVEAL_SESSION_URL);
  const selectors = [...new Set(selected.map((selector) => selector.trim()).filter(Boolean)
    .map((selector) => /^https?:\/\//i.test(selector) ? registerSessionUrl(selector) : selector))];
  if (!options.all && selectors.length === 0) {
    throw new Error('Select at least one target with a positional selector, --target, or --all.');
  }

  let discovered: DiscoveryRecord[] | undefined;
  const needsDiscovery = options.all || selectors.some((selector) => !/^https?:\/\//i.test(selector));

  if (needsDiscovery) {
    discovered = await discoverServices({ timeoutMs: options.timeoutMs });
    if (options.probeDiscovery || (options.platformFilters?.length ?? 0) > 0) {
      discovered = await probeDiscoveryRecords(discovered);
    }
  }

  const resolvedByUrl = new Map<string, ResolvedTarget>();

  if (options.all && discovered) {
    for (const service of discovered) {
      resolvedByUrl.set(service.url, {
        selector: service.name,
        url: service.url,
        discovery: service,
      });
    }
  }

  for (const selector of selectors) {
    if (/^https?:\/\//i.test(selector)) {
      const url = registerSessionUrl(selector);
      const discoveryMatch = discovered?.find((service) => service.url === url);
      resolvedByUrl.set(url, {
        selector,
        url,
        discovery: discoveryMatch,
      });
      continue;
    }

    const matches = (discovered ?? []).filter((service) => matchDiscoveryRecord(service, selector));

    if (matches.length === 0) {
      throw new Error(`No AppReveal target matched "${selector}" on the local network.`);
    }

    if (matches.length > 1) {
      const details = matches.map((match) => `${match.name} -> ${match.url}`).join('\n');
      throw new Error(`Target "${selector}" is ambiguous.\n${details}`);
    }

    const match = matches[0];
    resolvedByUrl.set(match.url, {
      selector,
      url: match.url,
      discovery: match,
    });
  }

  let resolved = [...resolvedByUrl.values()].sort((left, right) => left.url.localeCompare(right.url));
  if ((options.platformFilters?.length ?? 0) > 0) {
    resolved = await filterTargetsByPlatform(resolved, options.platformFilters ?? []);
  }

  if (resolved.length === 0) {
    throw new Error(options.platformFilters?.length
      ? `No AppReveal targets matched platform filter: ${options.platformFilters.join(', ')}`
      : 'No AppReveal targets discovered.');
  }

  return resolved;
}

export async function inspectTarget(
  selector: string,
  options: { timeoutMs: number; includeDeviceInfo: boolean; platformFilters?: string[] },
): Promise<InspectionResult> {
  const [target] = await resolveTargets({ selectors: [selector], all: false, timeoutMs: options.timeoutMs,
    platformFilters: options.platformFilters, probeDiscovery: true });
  const initialize = await sendRequest(target.url, { method: 'initialize', params: initializeParams() });
  const launchContext = await callTool(target.url, 'launch_context');
  const tools = await sendRequest(target.url, { method: 'tools/list' });
  const deviceInfo = options.includeDeviceInfo ? await callTool(target.url, 'device_info') : undefined;

  if (target.discovery) {
    target.discovery.codes = extractCodes(
      target.discovery.txt,
      plainObjectFromUnknown(launchContext.decoded),
    );
  }

  return {
    target,
    initialize,
    launchContext,
    deviceInfo,
    tools,
  };
}

export async function probeDiscoveryRecords(records: DiscoveryRecord[]): Promise<DiscoveryRecord[]> {
  return await Promise.all(records.map(async (record) => {
    try {
      const { url, launchContext } = await probeDiscoveryRecord(record);
      const decoded = plainObjectFromUnknown(launchContext.decoded);

      return {
        ...record,
        url,
        launchContext: decoded,
        deviceName: stringFromKnownKey(decoded, ['deviceName']),
        appName: stringFromKnownKey(decoded, ['appName']),
        platform: stringFromKnownKey(decoded, ['platform']),
        frameworkType: stringFromKnownKey(decoded, ['frameworkType']),
        codes: extractCodes(record.txt, decoded),
      };
    } catch {
      return record;
    }
  }));
}

export async function filterTargetsByPlatform(
  targets: ResolvedTarget[],
  platformFilters: string[],
): Promise<ResolvedTarget[]> {
  const normalizedFilters = new Set(platformFilters.map(normalizePlatform));
  const kept: ResolvedTarget[] = [];

  await Promise.all(targets.map(async (target) => {
    let platform = target.discovery?.platform;
    let framework = target.discovery?.frameworkType;

    if (!platform) {
      try {
        const launchContext = await callTool(target.url, 'launch_context');
        const decoded = plainObjectFromUnknown(launchContext.decoded);
        platform = stringFromKnownKey(decoded, ['platform']);
        framework = stringFromKnownKey(decoded, ['frameworkType']);

        if (target.discovery) {
          target.discovery.launchContext = decoded;
          target.discovery.platform = platform;
          target.discovery.frameworkType = framework;
          target.discovery.deviceName = target.discovery.deviceName ?? stringFromKnownKey(decoded, ['deviceName']);
          target.discovery.appName = target.discovery.appName ?? stringFromKnownKey(decoded, ['appName']);
          target.discovery.codes = extractCodes(target.discovery.txt, decoded);
        }
      } catch {
        return;
      }
    }

    if ([platform, framework].some((value) => value && normalizedFilters.has(normalizePlatform(value)))) {
      kept.push(target);
    }
  }));

  return kept.sort((left, right) => left.url.localeCompare(right.url));
}

export async function callTool(
  targetUrl: string,
  toolName: string,
  argumentsObject: Record<string, unknown> = {},
  options: { timeoutMs?: number } = {},
): Promise<ToolCallResult> {
  const request = buildRequest('tools/call', {
    name: toolName,
    arguments: argumentsObject,
  });
  const response = await postRequest(targetUrl, request, options);

  return {
    request,
    response,
    decoded: decodeToolResult(response.result),
  };
}

export async function sendRequest(targetUrl: string, options: RequestOptions): Promise<JsonRpcResponse> {
  return await postRequest(targetUrl, buildRequest(options.method, options.params, options.id), {
    timeoutMs: options.timeoutMs,
  });
}

export function buildArguments(
  jsonInput: string | undefined,
  keyValueArgs: string[],
): Record<string, unknown> {
  const base = parseJsonObject(jsonInput);

  for (const entry of keyValueArgs) {
    const separatorIndex = entry.indexOf('=');
    if (separatorIndex === -1) {
      throw new Error(`Invalid --arg "${entry}". Expected key=value.`);
    }

    const key = entry.slice(0, separatorIndex).trim();
    const rawValue = entry.slice(separatorIndex + 1).trim();

    if (key === '') {
      throw new Error(`Invalid --arg "${entry}". Key cannot be empty.`);
    }

    Object.defineProperty(base, key, { value: parseLooseValue(rawValue), enumerable: true, writable: true, configurable: true });
  }

  return base;
}

export function parseJsonObject(input: string | undefined): Record<string, unknown> {
  if (input === undefined || input.trim() === '') {
    return {};
  }

  const parsed = JSON.parse(input) as unknown;
  if (!isPlainObject(parsed)) {
    throw new Error('Expected a JSON object.');
  }

  return { ...parsed };
}

export function parseLooseValue(raw: string): unknown {
  if (raw === '') {
    return '';
  }

  if (raw === 'true') {
    return true;
  }

  if (raw === 'false') {
    return false;
  }

  if (raw === 'null') {
    return null;
  }

  if (/^-?\d+(\.\d+)?$/.test(raw)) {
    return Number(raw);
  }

  if ((raw.startsWith('{') && raw.endsWith('}')) || (raw.startsWith('[') && raw.endsWith(']'))) {
    return JSON.parse(raw);
  }

  return raw;
}

function buildRequest(
  method: string,
  params?: Record<string, unknown>,
  id?: string | number,
): JsonRpcRequest {
  return {
    jsonrpc: '2.0',
    id: id ?? nextRequestId++,
    method,
    params,
  };
}

async function probeDiscoveryRecord(
  record: DiscoveryRecord,
): Promise<{ url: string; launchContext: ToolCallResult }> {
  const urls = record.candidateUrls.length > 0 ? record.candidateUrls : [record.url];
  const attempts = urls.map(async (url) => ({
    url,
    launchContext: await callTool(url, 'launch_context', {}, { timeoutMs: DISCOVERY_PROBE_TIMEOUT_MS }),
  }));

  return await Promise.any(attempts);
}

async function postRequest(
  targetUrl: string,
  payload: JsonRpcRequest,
  options: { timeoutMs?: number } = {},
): Promise<JsonRpcResponse> {
  const timeoutMs = options.timeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
  const { url, headers } = requestCredentials(targetUrl);
  let response: Response;
  let responseText: string;
  try {
    response = await fetch(url, {
      method: 'POST',
      redirect: 'error',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json, text/event-stream',
        ...headers,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeoutMs),
    });
    responseText = await response.text();
  } catch (error) {
    throw new Error(redactSecrets(describeFetchFailure(error, url, payload.method, timeoutMs)));
  }

  if (!response.ok) {
    const hint = response.status === 401 ? ' Supply the app session URL via APPREVEAL_SESSION_URL or --target.' : '';
    throw new Error(redactSecrets(`HTTP ${response.status} from ${url}.${hint} ${redactSecrets(responseText).slice(0, 500)}`));
  }

  let json: unknown;
  try {
    json = JSON.parse(responseText);
  } catch {
    throw new Error(`Invalid JSON response from ${url} for ${payload.method}.`);
  }
  if (!isPlainObject(json) || json.jsonrpc !== '2.0' || json.id !== payload.id
      || (Object.hasOwn(json, 'result') === Object.hasOwn(json, 'error'))) {
    throw new Error(`Invalid JSON-RPC response from ${url} for ${payload.method}: expected version 2.0, matching id, and result or error.`);
  }
  if (Object.hasOwn(json, 'error')) {
    const error = json.error;
    if (!isPlainObject(error) || typeof error.code !== 'number' || typeof error.message !== 'string') {
      throw new Error(`Invalid JSON-RPC error from ${url}.`);
    }
    throw new Error(redactSecrets(`MCP error ${error.code}: ${error.message}`));
  }
  if (payload.method === 'tools/call') {
    const result = json.result;
    if (!isPlainObject(result) || !Array.isArray(result.content)) {
      throw new Error(`Invalid MCP tool result from ${url}: content array required.`);
    }
    const decoded = decodeToolResult(result);
    if (result.isError === true) {
      throw new Error(redactSecrets(`MCP tool failed: ${JSON.stringify(decoded)}`));
    }
    assertToolSuccess(decoded, typeof payload.params?.name === 'string' ? payload.params.name : undefined);
    if (payload.params?.name === 'batch' && isPlainObject(decoded) && Array.isArray(decoded.results)) {
      for (const item of decoded.results) {
        assertToolSuccess(item);
        if (isPlainObject(item)) assertToolSuccess(decodeJsonText(item.result), typeof item.tool === 'string' ? item.tool : undefined);
      }
    }
  }
  return json as JsonRpcResponse;
}

export function initializeParams(): Record<string, unknown> {
  return { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'appreveal-cli', version: '0.10.1' } };
}

export function decodeJsonText(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch { return value; }
}

export function assertToolSuccess(value: unknown, toolName?: string): void {
  if (!isPlainObject(value)) return;
  const hasError = typeof value.error === 'string'
    ? value.error.trim().length > 0
    : value.error !== undefined && value.error !== null && value.error !== false;
  // A successfully retrieved capture can describe a failed network request.
  const capturedRequest = toolName === 'get_network_call_detail'
    && ['id', 'method', 'url'].every((key) => typeof value[key] === 'string');
  if (value.success === false || value.isError === true || (hasError && !capturedRequest)) {
    throw new Error(redactSecrets(`AppReveal tool failed: ${JSON.stringify(value)}`));
  }
}

function describeFetchFailure(
  error: unknown,
  targetUrl: string,
  method: string,
  timeoutMs: number,
): string {
  if (error instanceof Error && error.name === 'TimeoutError') {
    return `Timed out after ${timeoutMs}ms calling ${method} on ${targetUrl}`;
  }

  if (error instanceof Error && error.name === 'AbortError') {
    return `Aborted after ${timeoutMs}ms calling ${method} on ${targetUrl}`;
  }

  if (error instanceof Error) {
    const cause = error.cause instanceof Error ? `: ${error.cause.message}` : '';
    return `Fetch failed calling ${method} on ${targetUrl}: ${error.message}${cause}`;
  }

  return `Fetch failed calling ${method} on ${targetUrl}: ${String(error)}`;
}

function decodeToolResult(result: unknown): unknown {
  if (!isPlainObject(result)) {
    return result;
  }

  const content = result.content;
  // Preserve image/resource/audio blocks and multi-part content verbatim.
  if (!Array.isArray(content) || content.length !== 1 || !isPlainObject(content[0])
      || content[0].type !== 'text' || typeof content[0].text !== 'string') return result;
  return result.structuredContent ?? decodeJsonText(content[0].text);
}

function plainObjectFromUnknown(value: unknown): Record<string, unknown> {
  return isPlainObject(value) ? value : {};
}

function stringFromKnownKey(source: Record<string, unknown>, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = source[key];
    if (typeof value === 'string' && value.trim() !== '') {
      return value;
    }
  }

  return undefined;
}

function normalizePlatform(value: string): string {
  return value.trim().toLowerCase().replace(/[\s_-]+/g, '');
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
