import type { ResolvedTarget } from './mcp.js';
import { callTool } from './mcp.js';

export interface FanOutResult<T> {
  target: ResolvedTarget;
  ok: boolean;
  result?: T;
  error?: string;
}

export interface SnapshotResult {
  launchContext: Record<string, unknown>;
  screen: Record<string, unknown>;
  elementCount: number;
  elements: ElementRecord[];
}

export interface FindResult {
  screen: Record<string, unknown>;
  query: string;
  field: ElementSearchField;
  matches: MatchedElement[];
}

export interface TapResult {
  screen: Record<string, unknown>;
  matched: MatchedElement;
  response: unknown;
}

export interface TypeResult {
  screen?: Record<string, unknown>;
  matched?: MatchedElement;
  response: unknown;
}

export type ElementSearchField = 'any' | 'id' | 'label' | 'value' | 'type' | 'actions';

export interface ElementRecord {
  id?: string;
  type?: string;
  label?: string;
  value?: string;
  enabled?: string;
  visible?: string;
  tappable?: string;
  frame?: string;
  actions?: string;
  source?: string;
  [key: string]: unknown;
}

export interface MatchedElement {
  score: number;
  matchField: ElementSearchField;
  element: ElementRecord;
}

export async function fanOutTargets<T>(
  targets: ResolvedTarget[],
  work: (target: ResolvedTarget) => Promise<T>,
): Promise<Array<FanOutResult<T>>> {
  return await Promise.all(targets.map(async (target) => {
    try {
      return {
        target,
        ok: true,
        result: await work(target),
      };
    } catch (error) {
      return {
        target,
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      };
    }
  }));
}

export async function snapshotTargets(
  targets: ResolvedTarget[],
  options: { elementLimit: number },
): Promise<Array<FanOutResult<SnapshotResult>>> {
  return await fanOutTargets(targets, async (target) => {
    const batch = await callTool(target.url, 'batch', {
      actions: [
        { tool: 'launch_context' },
        { tool: 'get_screen' },
        { tool: 'get_elements' },
        { tool: 'get_view_tree', arguments: { max_depth: 12 } },
      ],
    });

    const byTool = parseBatchToolResults(batch.decoded);
    const elements = mergeInteractiveTargets(
      extractElements(byTool.get('get_elements')),
      extractInteractiveViewNodes(byTool.get('get_view_tree')),
    );

    return {
      launchContext: toRecord(byTool.get('launch_context')),
      screen: toRecord(byTool.get('get_screen')),
      elementCount: elements.length,
      elements: elements.slice(0, options.elementLimit),
    };
  });
}

export async function findElementsOnTargets(
  targets: ResolvedTarget[],
  query: string,
  options: { field: ElementSearchField; limit: number },
): Promise<Array<FanOutResult<FindResult>>> {
  return await fanOutTargets(targets, async (target) => {
    const context = await fetchScreenAndElements(target);
    const matches = rankElements(context.elements, query, options.field).slice(0, options.limit);

    return {
      screen: context.screen,
      query,
      field: options.field,
      matches,
    };
  });
}

export async function tapOnTargets(
  targets: ResolvedTarget[],
  query: string,
  options: { field: ElementSearchField; exact: boolean },
): Promise<Array<FanOutResult<TapResult>>> {
  return await fanOutTargets(targets, async (target) => {
    const context = await fetchScreenAndElements(target);
    const matched = selectSingleElement(context.elements, query, options.field, options.exact);
    const elementId = matched.element.id;
    if (elementId && matched.element.source !== 'view_tree') {
      const response = await callTool(target.url, 'tap_element', {
        element_id: elementId,
      });

      return {
        screen: context.screen,
        matched,
        response: response.decoded,
      };
    }

    const point = centerPointFromFrame(matched.element.frame);
    if (!point) {
      throw new Error('Matched element has neither an id nor a tappable frame.');
    }

    const response = await callTool(target.url, 'tap_point', {
      x: point.x,
      y: point.y,
    });

    return {
      screen: context.screen,
      matched,
      response: response.decoded,
    };
  });
}

export async function typeOnTargets(
  targets: ResolvedTarget[],
  text: string,
  options: { elementQuery?: string; field: ElementSearchField; exact: boolean },
): Promise<Array<FanOutResult<TypeResult>>> {
  return await fanOutTargets(targets, async (target) => {
    if (!options.elementQuery) {
      const response = await callTool(target.url, 'type_text', { text });
      return { response: response.decoded };
    }

    const context = await fetchScreenAndElements(target);
    const matched = selectSingleElement(context.elements, options.elementQuery, options.field, options.exact);
    const elementId = matched.element.id;
    if (elementId && matched.element.source !== 'view_tree') {
      const response = await callTool(target.url, 'type_text', {
        text,
        element_id: elementId,
      });

      return {
        screen: context.screen,
        matched,
        response: response.decoded,
      };
    }

    const point = centerPointFromFrame(matched.element.frame);
    if (!point) {
      throw new Error('Matched element has neither an id nor a tappable frame.');
    }

    await callTool(target.url, 'tap_point', {
      x: point.x,
      y: point.y,
    });
    const response = await callTool(target.url, 'type_text', { text });

    return {
      screen: context.screen,
      matched,
      response: response.decoded,
    };
  });
}

async function fetchScreenAndElements(target: ResolvedTarget): Promise<{
  screen: Record<string, unknown>;
  elements: ElementRecord[];
}> {
  const batch = await callTool(target.url, 'batch', {
    actions: [
      { tool: 'get_screen' },
      { tool: 'get_elements' },
      { tool: 'get_view_tree', arguments: { max_depth: 12 } },
    ],
  });
  const byTool = parseBatchToolResults(batch.decoded);

  return {
    screen: toRecord(byTool.get('get_screen')),
    elements: mergeInteractiveTargets(
      extractElements(byTool.get('get_elements')),
      extractInteractiveViewNodes(byTool.get('get_view_tree')),
    ),
  };
}

function parseBatchToolResults(decoded: unknown): Map<string, unknown> {
  const result = new Map<string, unknown>();
  const record = toRecord(decoded);
  const items = Array.isArray(record.results) ? record.results : [];

  for (const item of items) {
    if (!isRecord(item)) {
      continue;
    }

    const tool = typeof item.tool === 'string' ? item.tool : undefined;
    if (!tool) {
      continue;
    }

    const rawResult = typeof item.result === 'string' ? item.result : undefined;
    if (!rawResult) {
      result.set(tool, item);
      continue;
    }

    try {
      result.set(tool, JSON.parse(rawResult));
    } catch {
      result.set(tool, rawResult);
    }
  }

  return result;
}

function extractElements(value: unknown): ElementRecord[] {
  const record = toRecord(value);
  const elements = Array.isArray(record.elements) ? record.elements : [];
  return elements.filter(isRecord).map((element) => ({ ...element, source: 'elements' }));
}

function extractInteractiveViewNodes(value: unknown): ElementRecord[] {
  const record = toRecord(value);
  const views = Array.isArray(record.views) ? record.views : [];

  return views
    .filter(isRecord)
    .map((view) => toViewNodeElement(view))
    .filter((element): element is ElementRecord => Boolean(element));
}

function toViewNodeElement(view: Record<string, unknown>): ElementRecord | undefined {
  const accessibilityLabel = typeof view.accessibilityLabel === 'string' ? view.accessibilityLabel.trim() : '';
  const frame = typeof view.frame === 'string' ? view.frame : undefined;
  const userInteraction = view.userInteraction === true;
  const hidden = view.hidden === true;

  if (!accessibilityLabel || hidden || !userInteraction || !frame) {
    return undefined;
  }

  const labels = accessibilityLabel.split(/\s+/).filter(Boolean);
  const primaryLabel = labels[0] ?? accessibilityLabel;
  const className = typeof view.class === 'string' ? view.class : 'view';

  return {
    id: primaryLabel,
    label: accessibilityLabel,
    type: className.replace(/^RCT/, '').toLowerCase(),
    value: '',
    enabled: 'true',
    visible: 'true',
    tappable: 'true',
    frame,
    actions: 'tap',
    source: 'view_tree',
    class: className,
  };
}

function mergeInteractiveTargets(primary: ElementRecord[], fallback: ElementRecord[]): ElementRecord[] {
  const merged = new Map<string, ElementRecord>();

  for (const element of [...primary, ...fallback]) {
    const key = `${element.source}:${element.id ?? ''}:${element.label ?? ''}:${element.frame ?? ''}`;
    if (!merged.has(key)) {
      merged.set(key, element);
    }
  }

  return [...merged.values()];
}

function selectSingleElement(
  elements: ElementRecord[],
  query: string,
  field: ElementSearchField,
  exact: boolean,
): MatchedElement {
  const ranked = rankElements(elements, query, field, exact);
  if (ranked.length === 0) {
    throw new Error(`No element matched "${query}".`);
  }

  if (ranked.length > 1 && ranked[0].score === ranked[1].score) {
    const preview = ranked
      .slice(0, 3)
      .map((match) => `${match.element.id ?? 'unknown'} (${match.element.label ?? ''})`)
      .join(', ');
    throw new Error(`Element query "${query}" is ambiguous: ${preview}`);
  }

  return ranked[0];
}

function rankElements(
  elements: ElementRecord[],
  query: string,
  field: ElementSearchField,
  exact = false,
): MatchedElement[] {
  const normalizedQuery = normalizeText(query);

  return elements
    .map((element) => {
      const matchField = bestFieldForElement(element, normalizedQuery, field);
      if (!matchField) {
        return undefined;
      }

      const score = scoreElementField(element, normalizedQuery, matchField, exact);
      if (score <= 0) {
        return undefined;
      }

      return {
        score,
        matchField,
        element,
      };
    })
    .filter((match): match is MatchedElement => Boolean(match))
    .sort((left, right) => right.score - left.score || (left.element.id ?? '').localeCompare(right.element.id ?? ''));
}

function bestFieldForElement(
  element: ElementRecord,
  normalizedQuery: string,
  requestedField: ElementSearchField,
): ElementSearchField | undefined {
  const fields: ElementSearchField[] = requestedField === 'any'
    ? ['id', 'label', 'value', 'type', 'actions']
    : [requestedField];

  let bestField: ElementSearchField | undefined;
  let bestScore = 0;

  for (const field of fields) {
    const score = scoreElementField(element, normalizedQuery, field, false);
    if (score > bestScore) {
      bestField = field;
      bestScore = score;
    }
  }

  return bestField;
}

function scoreElementField(
  element: ElementRecord,
  normalizedQuery: string,
  field: ElementSearchField,
  exact: boolean,
): number {
  if (field === 'any') {
    return 0;
  }

  const rawValue = element[field];
  if (typeof rawValue !== 'string' || rawValue.trim() === '') {
    return 0;
  }

  const normalizedValue = normalizeText(rawValue);
  if (normalizedValue === normalizedQuery) {
    return field === 'id' ? 120 : 100;
  }

  if (exact) {
    return 0;
  }

  if (normalizedValue.startsWith(normalizedQuery)) {
    return field === 'id' ? 95 : 80;
  }

  if (normalizedValue.includes(normalizedQuery)) {
    return field === 'id' ? 75 : 60;
  }

  return 0;
}

function normalizeText(value: string): string {
  return value.trim().toLowerCase();
}

function centerPointFromFrame(frame: unknown): { x: number; y: number } | undefined {
  if (typeof frame !== 'string') {
    return undefined;
  }

  const parts = frame.split(',').map((part) => Number.parseFloat(part));
  if (parts.length !== 4 || parts.some((part) => !Number.isFinite(part))) {
    return undefined;
  }

  return {
    x: parts[0] + parts[2] / 2,
    y: parts[1] + parts[3] / 2,
  };
}

function toRecord(value: unknown): Record<string, unknown> {
  return isRecord(value) ? value : {};
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
