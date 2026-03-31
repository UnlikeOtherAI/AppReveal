#!/usr/bin/env node

import { Command } from 'commander';
import { CLI_OVERVIEW, HELP_EXAMPLES } from './help.js';
import { discoverServices } from './discovery.js';
import {
  buildArguments,
  callTool,
  inspectTarget,
  probeDiscoveryRecords,
  resolveTargets,
  sendRequest,
  type ResolveTargetsOptions,
  type ResolvedTarget,
} from './mcp.js';
import {
  printDiscovery,
  printFanOutResults,
  printInspection,
  printJson,
} from './output.js';
import {
  fanOutTargets,
  findElementsOnTargets,
  snapshotTargets,
  tapOnTargets,
  typeOnTargets,
  type ElementSearchField,
} from './workflows.js';

const DEFAULT_DISCOVERY_TIMEOUT_MS = 5000;
const DEFAULT_ELEMENT_LIMIT = 8;

const program = new Command();

program
  .name('appreveal')
  .description('Discover and query AppReveal MCP servers on the local network.')
  .showHelpAfterError()
  .addHelpText('beforeAll', `${CLI_OVERVIEW}\n`)
  .addHelpText('afterAll', `\n${HELP_EXAMPLES}`);

program
  .command('discover')
  .description('Browse the local network for AppReveal MCP servers.')
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--no-probe', 'skip launch_context probing after mDNS discovery')
  .option('--json', 'emit machine-readable JSON')
  .action(async (options) => {
    let records = await discoverServices({ timeoutMs: options.timeout });
    if (options.probe || options.platform) {
      records = await probeDiscoveryRecords(records);
    }

    const platformFilters = parsePlatformList(options.platform);
    if (platformFilters.length > 0) {
      const wanted = new Set(platformFilters.map(normalizePlatform));
      records = records.filter((record) => record.platform && wanted.has(normalizePlatform(record.platform)));
    }

    if (options.json) {
      printJson(records);
      return;
    }
    printDiscovery(records);
  });

program
  .command('inspect')
  .description('Inspect one or more targets: initialize MCP, fetch launch context, and list tools.')
  .argument('[target]', 'optional target selector for single-target mode')
  .option('--target <selector>', 'repeatable target selector', collectRepeatedOption, [])
  .option('--all', 'select all discovered targets')
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--device-info', 'also call device_info for a full runtime snapshot')
  .option('--json', 'emit machine-readable JSON')
  .action(async (positionalTarget, options) => {
    if (!options.all && options.target.length === 0 && positionalTarget) {
      const result = await inspectTarget(positionalTarget, {
        timeoutMs: options.timeout,
        includeDeviceInfo: Boolean(options.deviceInfo),
      });

      if (options.json) {
        printJson(result);
        return;
      }

      printInspection(result);
      return;
    }

    const targets = await resolveTargetsFromCommand({
      positionalTarget,
      optionTargets: options.target,
      all: options.all,
      timeoutMs: options.timeout,
      platform: options.platform,
      probeDiscovery: true,
    });

    const results = await fanOutTargets(targets, async (target) => {
      const initialize = await sendRequest(target.url, { method: 'initialize' });
      const launchContext = await callTool(target.url, 'launch_context');
      const tools = await sendRequest(target.url, { method: 'tools/list' });
      const deviceInfo = options.deviceInfo ? await callTool(target.url, 'device_info') : undefined;

      return {
        initialize: initialize.result ?? {},
        launchContext: launchContext.decoded,
        deviceInfo: deviceInfo?.decoded,
        tools: tools.result ?? {},
      };
    });

    if (options.json) {
      printJson(results);
      return;
    }

    printFanOutResults(results, (result) => JSON.stringify(result, null, 2));
  });

program
  .command('tools')
  .description('List the MCP tools exposed by one or more targets.')
  .argument('[target]', 'optional target selector for single-target mode')
  .option('--target <selector>', 'repeatable target selector', collectRepeatedOption, [])
  .option('--all', 'select all discovered targets')
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--json', 'emit machine-readable JSON')
  .action(async (positionalTarget, options) => {
    const targets = await resolveTargetsFromCommand({
      positionalTarget,
      optionTargets: options.target,
      all: options.all,
      timeoutMs: options.timeout,
      platform: options.platform,
      probeDiscovery: true,
    });

    const results = await fanOutTargets(targets, async (target) => {
      const response = await sendRequest(target.url, { method: 'tools/list' });
      return response.result ?? {};
    });

    if (options.json) {
      printJson(results);
      return;
    }

    printFanOutResults(results, (result) => JSON.stringify(result, null, 2));
  });

program
  .command('call')
  .alias('query')
  .description('Call a normal MCP tool on one or more targets.')
  .argument('<first>', 'either the tool name or a single-target selector in backward-compatible mode')
  .argument('[second]', 'either the target selector or the tool name in backward-compatible mode')
  .option('--target <selector>', 'repeatable target selector', collectRepeatedOption, [])
  .option('--all', 'select all discovered targets')
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--arg <key=value>', 'single tool argument; repeatable', collectRepeatedOption, [])
  .option('--args <json>', 'JSON object with tool arguments')
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--json', 'emit machine-readable JSON')
  .action(async (first, second, options) => {
    const { tool, positionalTarget } = parseTargetedVerbArguments(first, second, options);
    const targets = await resolveTargetsFromCommand({
      positionalTarget,
      optionTargets: options.target,
      all: options.all,
      timeoutMs: options.timeout,
      platform: options.platform,
      probeDiscovery: true,
    });
    const args = buildArguments(options.args, options.arg);
    const results = await fanOutTargets(targets, async (target) => {
      const result = await callTool(target.url, tool, args);
      return result.decoded;
    });

    if (options.json) {
      printJson(results);
      return;
    }

    if (results.length === 1 && results[0].ok) {
      printJson(results[0].result);
      return;
    }

    printFanOutResults(results, (result) => JSON.stringify(result, null, 2));
  });

program
  .command('request')
  .description('Send a raw MCP JSON-RPC request to one or more targets.')
  .argument('<first>', 'either the raw MCP method or a single-target selector in backward-compatible mode')
  .argument('[second]', 'either the target selector or the raw method in backward-compatible mode')
  .option('--target <selector>', 'repeatable target selector', collectRepeatedOption, [])
  .option('--all', 'select all discovered targets')
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--params <json>', 'JSON object with request params')
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--json', 'emit machine-readable JSON')
  .action(async (first, second, options) => {
    const { tool: method, positionalTarget } = parseTargetedVerbArguments(first, second, options);
    const targets = await resolveTargetsFromCommand({
      positionalTarget,
      optionTargets: options.target,
      all: options.all,
      timeoutMs: options.timeout,
      platform: options.platform,
      probeDiscovery: true,
    });

    const results = await fanOutTargets(targets, async (target) => {
      const response = await sendRequest(target.url, {
        method,
        params: options.params ? JSON.parse(options.params) : undefined,
      });
      return response.result ?? response;
    });

    if (options.json) {
      printJson(results);
      return;
    }

    printFanOutResults(results, (result) => JSON.stringify(result, null, 2));
  });

program
  .command('snapshot')
  .description('Get launch context, current screen, and a compact element list across one or more targets.')
  .argument('[target]', 'optional target selector for single-target mode')
  .option('--target <selector>', 'repeatable target selector', collectRepeatedOption, [])
  .option('--all', 'select all discovered targets')
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--limit <count>', 'max elements to show per target', parseInteger, DEFAULT_ELEMENT_LIMIT)
  .option('--json', 'emit machine-readable JSON')
  .action(async (positionalTarget, options) => {
    const targets = await resolveTargetsFromCommand({
      positionalTarget,
      optionTargets: options.target,
      all: options.all,
      timeoutMs: options.timeout,
      platform: options.platform,
      probeDiscovery: true,
    });
    const results = await snapshotTargets(targets, { elementLimit: options.limit });

    if (options.json) {
      printJson(results);
      return;
    }

    printFanOutResults(results, (result) => JSON.stringify(result, null, 2));
  });

program
  .command('find')
  .description('Search the visible element inventory on one or more targets.')
  .argument('<query>', 'text to match against element id, label, value, type, or actions')
  .argument('[target]', 'optional target selector for single-target mode')
  .option('--target <selector>', 'repeatable target selector', collectRepeatedOption, [])
  .option('--all', 'select all discovered targets')
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--field <field>', 'match field: any, id, label, value, type, actions', 'any')
  .option('--limit <count>', 'max matches to show per target', parseInteger, DEFAULT_ELEMENT_LIMIT)
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--json', 'emit machine-readable JSON')
  .action(async (query, positionalTarget, options) => {
    const targets = await resolveTargetsFromCommand({
      positionalTarget,
      optionTargets: options.target,
      all: options.all,
      timeoutMs: options.timeout,
      platform: options.platform,
      probeDiscovery: true,
    });
    const results = await findElementsOnTargets(targets, query, {
      field: parseElementSearchField(options.field),
      limit: options.limit,
    });

    if (options.json) {
      printJson(results);
      return;
    }

    printFanOutResults(results, (result) => JSON.stringify(result, null, 2));
  });

program
  .command('tap')
  .description('Find one visible element and tap it across one or more targets.')
  .argument('<query>', 'element query, usually an id or stable label fragment')
  .argument('[target]', 'optional target selector for single-target mode')
  .option('--target <selector>', 'repeatable target selector', collectRepeatedOption, [])
  .option('--all', 'select all discovered targets')
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--field <field>', 'match field: any, id, label, value, type, actions', 'any')
  .option('--exact', 'require exact equality instead of prefix/contains matching')
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--json', 'emit machine-readable JSON')
  .action(async (query, positionalTarget, options) => {
    const targets = await resolveTargetsFromCommand({
      positionalTarget,
      optionTargets: options.target,
      all: options.all,
      timeoutMs: options.timeout,
      platform: options.platform,
      probeDiscovery: true,
    });
    const results = await tapOnTargets(targets, query, {
      field: parseElementSearchField(options.field),
      exact: Boolean(options.exact),
    });

    if (options.json) {
      printJson(results);
      return;
    }

    printFanOutResults(results, (result) => JSON.stringify(result, null, 2));
  });

program
  .command('type')
  .description('Type text into the focused field or into a matched element across one or more targets.')
  .argument('<text>', 'text to type')
  .argument('[target]', 'optional target selector for single-target mode')
  .option('--target <selector>', 'repeatable target selector', collectRepeatedOption, [])
  .option('--all', 'select all discovered targets')
  .option('--platform <list>', 'comma-separated platform filter: ios, macos, android, flutter, reactnative')
  .option('--element <query>', 'match an element before typing; omit to type into the focused field')
  .option('--field <field>', 'match field when --element is used: any, id, label, value, type, actions', 'any')
  .option('--exact', 'require exact equality instead of prefix/contains matching')
  .option('--timeout <ms>', 'discovery timeout in milliseconds', parseInteger, DEFAULT_DISCOVERY_TIMEOUT_MS)
  .option('--json', 'emit machine-readable JSON')
  .action(async (text, positionalTarget, options) => {
    const targets = await resolveTargetsFromCommand({
      positionalTarget,
      optionTargets: options.target,
      all: options.all,
      timeoutMs: options.timeout,
      platform: options.platform,
      probeDiscovery: true,
    });
    const results = await typeOnTargets(targets, text, {
      elementQuery: options.element,
      field: parseElementSearchField(options.field),
      exact: Boolean(options.exact),
    });

    if (options.json) {
      printJson(results);
      return;
    }

    printFanOutResults(results, (result) => JSON.stringify(result, null, 2));
  });

program.parseAsync(process.argv).catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});

function parseInteger(value: string): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`Invalid integer value: ${value}`);
  }
  return parsed;
}

function collectRepeatedOption(value: string, previous: string[]): string[] {
  previous.push(value);
  return previous;
}

function parsePlatformList(value: string | undefined): string[] {
  if (!value) {
    return [];
  }

  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function normalizePlatform(value: string): string {
  return value.trim().toLowerCase().replace(/[\s_-]+/g, '');
}

function parseElementSearchField(value: string): ElementSearchField {
  const allowed: ElementSearchField[] = ['any', 'id', 'label', 'value', 'type', 'actions'];
  if (!allowed.includes(value as ElementSearchField)) {
    throw new Error(`Invalid field "${value}". Use one of: ${allowed.join(', ')}`);
  }
  return value as ElementSearchField;
}

function parseTargetedVerbArguments(
  first: string,
  second: string | undefined,
  options: { all?: boolean; target: string[] },
): { tool: string; positionalTarget?: string } {
  if (second) {
    return { tool: second, positionalTarget: first };
  }

  if (options.all || options.target.length > 0) {
    return { tool: first };
  }

  throw new Error('Select targets with --target or --all, or use the backward-compatible form with <target> <name>.');
}

async function resolveTargetsFromCommand(options: {
  positionalTarget?: string;
  optionTargets: string[];
  all: boolean;
  timeoutMs: number;
  platform?: string;
  probeDiscovery?: boolean;
}): Promise<ResolvedTarget[]> {
  return await resolveTargets({
    selectors: [options.positionalTarget, ...options.optionTargets].filter((value): value is string => Boolean(value)),
    all: options.all,
    timeoutMs: options.timeoutMs,
    platformFilters: parsePlatformList(options.platform),
    probeDiscovery: options.probeDiscovery,
  } satisfies ResolveTargetsOptions);
}
