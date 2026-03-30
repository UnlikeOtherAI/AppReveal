import { discoverServices, extractCodes, matchDiscoveryRecord, normalizeUrl, type DiscoveryRecord } from './discovery.js';

export interface RequestOptions {
  method: string;
  params?: Record<string, unknown>;
  id?: string | number;
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

export async function resolveTarget(selector: string, options: ResolveTargetOptions): Promise<ResolvedTarget> {
  const resolved = await resolveTargets({
    selectors: [selector],
    all: false,
    timeoutMs: options.timeoutMs,
  });
  return resolved[0];
}

export async function resolveTargets(options: ResolveTargetsOptions): Promise<ResolvedTarget[]> {
  const selectors = [...new Set(options.selectors.map((selector) => selector.trim()).filter(Boolean))];
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
      const url = normalizeUrl(selector);
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
    throw new Error(`No AppReveal targets matched platform filter: ${(options.platformFilters ?? []).join(', ')}`);
  }

  return resolved;
}

export async function inspectTarget(
  selector: string,
  options: { timeoutMs: number; includeDeviceInfo: boolean },
): Promise<InspectionResult> {
  const target = await resolveTarget(selector, { timeoutMs: options.timeoutMs });
  const initialize = await sendRequest(target.url, { method: 'initialize' });
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
      const launchContext = await callTool(record.url, 'launch_context');
      const decoded = plainObjectFromUnknown(launchContext.decoded);

      return {
        ...record,
        launchContext: decoded,
        deviceName: stringFromKnownKey(decoded, ['deviceName']),
        appName: stringFromKnownKey(decoded, ['appName']),
        platform: stringFromKnownKey(decoded, ['platform']),
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

    if (!platform) {
      try {
        const launchContext = await callTool(target.url, 'launch_context');
        const decoded = plainObjectFromUnknown(launchContext.decoded);
        platform = stringFromKnownKey(decoded, ['platform']);

        if (target.discovery) {
          target.discovery.launchContext = decoded;
          target.discovery.platform = platform;
          target.discovery.deviceName = target.discovery.deviceName ?? stringFromKnownKey(decoded, ['deviceName']);
          target.discovery.appName = target.discovery.appName ?? stringFromKnownKey(decoded, ['appName']);
          target.discovery.codes = extractCodes(target.discovery.txt, decoded);
        }
      } catch {
        return;
      }
    }

    if (platform && normalizedFilters.has(normalizePlatform(platform))) {
      kept.push(target);
    }
  }));

  return kept.sort((left, right) => left.url.localeCompare(right.url));
}

export async function callTool(
  targetUrl: string,
  toolName: string,
  argumentsObject: Record<string, unknown> = {},
): Promise<ToolCallResult> {
  const request = buildRequest('tools/call', {
    name: toolName,
    arguments: argumentsObject,
  });
  const response = await postRequest(targetUrl, request);

  return {
    request,
    response,
    decoded: decodeToolResult(response.result),
  };
}

export async function sendRequest(targetUrl: string, options: RequestOptions): Promise<JsonRpcResponse> {
  return await postRequest(targetUrl, buildRequest(options.method, options.params, options.id));
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

    base[key] = parseLooseValue(rawValue);
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

async function postRequest(targetUrl: string, payload: JsonRpcRequest): Promise<JsonRpcResponse> {
  const response = await fetch(normalizeUrl(targetUrl), {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(15_000),
  });

  const responseText = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} from ${targetUrl}: ${responseText}`);
  }

  const json = JSON.parse(responseText) as JsonRpcResponse;
  if (json.error) {
    throw new Error(`MCP error ${json.error.code}: ${json.error.message}`);
  }

  return json;
}

function decodeToolResult(result: unknown): unknown {
  if (!isPlainObject(result)) {
    return result;
  }

  const content = result.content;
  if (!Array.isArray(content)) {
    return result;
  }

  const textItem = content.find((item) => isPlainObject(item) && item.type === 'text' && typeof item.text === 'string');
  if (!textItem || typeof textItem.text !== 'string') {
    return result;
  }

  try {
    return JSON.parse(textItem.text);
  } catch {
    return textItem.text;
  }
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
