import type { DiscoveryRecord } from './discovery.js';
import type { InspectionResult, ToolCallResult } from './mcp.js';
import type { FanOutResult } from './workflows.js';

export function printJson(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

export function printDiscovery(records: DiscoveryRecord[]): void {
  if (records.length === 0) {
    process.stdout.write('No AppReveal targets discovered.\n');
    return;
  }

  for (const [index, record] of records.entries()) {
    if (index > 0) {
      process.stdout.write('\n');
    }

    printLine('Name', record.name);
    printLine('URL', record.url);
    printLine('Host', `${record.host}:${record.port}`);
    printLine('Addresses', record.addresses.length > 0 ? record.addresses.join(', ') : 'none');
    printLine('Bundle ID', record.bundleId ?? 'unknown');
    printLine('Device', record.deviceName ?? 'unknown');
    printLine('App', record.appName ?? 'unknown');
    printLine('Platform', record.platform ?? 'unknown');
    printLine('Version', record.version ?? 'unknown');
    printLine('Transport', record.transport ?? 'unknown');
    printLine('Codes', formatRecord(record.codes));
    printLine('TXT', formatRecord(record.txt));
  }
}

export function printInspection(result: InspectionResult): void {
  printLine('Target', result.target.selector);
  printLine('URL', result.target.url);

  if (result.target.discovery) {
    printLine('Resolved Service', result.target.discovery.name);
    printLine('Addresses', result.target.discovery.addresses.join(', ') || 'none');
    printLine('Codes', formatRecord(result.target.discovery.codes));
  }

  process.stdout.write('\nLaunch Context\n');
  process.stdout.write(`${formatValue(result.launchContext?.decoded ?? {})}\n`);

  if (result.deviceInfo) {
    process.stdout.write('\nDevice Info\n');
    process.stdout.write(`${formatValue(result.deviceInfo.decoded)}\n`);
  }

  process.stdout.write('\nInitialize\n');
  process.stdout.write(`${formatValue(result.initialize.result ?? {})}\n`);

  process.stdout.write('\nTools\n');
  process.stdout.write(`${formatValue(result.tools.result ?? {})}\n`);
}

export function printToolResult(result: ToolCallResult): void {
  process.stdout.write(`${formatValue(result.decoded)}\n`);
}

export function printFanOutResults<T>(
  results: Array<FanOutResult<T>>,
  formatter: (result: T) => string,
): void {
  if (results.length === 0) {
    process.stdout.write('No targets selected.\n');
    return;
  }

  for (const [index, item] of results.entries()) {
    if (index > 0) {
      process.stdout.write('\n');
    }

    printLine('Target', item.target.discovery?.name ?? item.target.selector);
    printLine('URL', item.target.url);
    if (item.target.discovery?.deviceName) {
      printLine('Device', item.target.discovery.deviceName);
    }
    if (item.target.discovery?.platform) {
      printLine('Platform', item.target.discovery.platform);
    }

    if (!item.ok) {
      printLine('Status', 'error');
      process.stdout.write(`${item.error}\n`);
      continue;
    }

    printLine('Status', 'ok');
    process.stdout.write(`${formatter(item.result as T)}\n`);
  }
}

function printLine(label: string, value: string): void {
  process.stdout.write(`${label.padEnd(12)} ${value}\n`);
}

function formatRecord(record: Record<string, string>): string {
  const entries = Object.entries(record);
  if (entries.length === 0) {
    return 'none';
  }

  return entries.map(([key, value]) => `${key}=${value}`).join(', ');
}

function formatValue(value: unknown): string {
  if (typeof value === 'string') {
    return value;
  }

  return JSON.stringify(value, null, 2);
}
