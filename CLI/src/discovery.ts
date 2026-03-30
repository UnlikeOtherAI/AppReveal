import { Bonjour, type Service } from 'bonjour-service';

export interface DiscoveryOptions {
  timeoutMs: number;
}

export interface DiscoveryRecord {
  name: string;
  fqdn: string;
  host: string;
  port: number;
  url: string;
  addresses: string[];
  txt: Record<string, string>;
  bundleId?: string;
  version?: string;
  transport?: string;
  codes: Record<string, string>;
  launchContext?: Record<string, unknown>;
  deviceName?: string;
  appName?: string;
  platform?: string;
}

interface BonjourServiceLike {
  name?: string;
  fqdn?: string;
  host?: string;
  port?: number;
  addresses?: string[];
  txt?: Record<string, unknown>;
}

export function extractCodes(
  txt: Record<string, string>,
  probe: Record<string, unknown> = {},
): Record<string, string> {
  const codes: Record<string, string> = {};

  for (const [key, value] of Object.entries(txt)) {
    if (/(code|pin|token|pair)/i.test(key) && value !== '') {
      codes[key] = value;
    }
  }

  const probeMappings: Array<[string, string]> = [
    ['build', 'build'],
    ['versionCode', 'versionCode'],
    ['versionName', 'versionName'],
  ];

  for (const [outputKey, inputKey] of probeMappings) {
    const value = probe[inputKey];
    if (value !== undefined && value !== null && String(value).trim() !== '') {
      codes[outputKey] = String(value);
    }
  }

  return codes;
}

export async function discoverServices(options: DiscoveryOptions): Promise<DiscoveryRecord[]> {
  const bonjour = new Bonjour();
  const services = new Map<string, DiscoveryRecord>();

  return await new Promise<DiscoveryRecord[]>((resolve) => {
    const browser = bonjour.find({ type: 'appreveal', protocol: 'tcp' }, (service: Service) => {
      const record = toDiscoveryRecord(service);
      services.set(discoveryKey(record), record);
    });

    const finish = () => {
      browser.stop();
      bonjour.destroy();
      resolve([...services.values()].sort(compareDiscoveryRecords));
    };

    setTimeout(finish, options.timeoutMs);
  });
}

export function normalizeUrl(raw: string): string {
  if (/^https?:\/\//i.test(raw)) {
    const url = new URL(raw);
    if (url.pathname === '') {
      url.pathname = '/';
    }
    return url.toString();
  }

  return `http://${raw.replace(/\/+$/, '')}/`;
}

export function matchDiscoveryRecord(record: DiscoveryRecord, selector: string): boolean {
  const normalizedSelector = selector.trim().toLowerCase();
  if (normalizedSelector === '') {
    return false;
  }

  const candidates = new Set<string>([
    record.name,
    record.fqdn,
    record.host,
    record.url,
    record.bundleId ?? '',
    ...record.addresses,
  ]);

  for (const candidate of candidates) {
    if (candidate.toLowerCase() === normalizedSelector) {
      return true;
    }

    if (candidate.toLowerCase().includes(normalizedSelector)) {
      return true;
    }
  }

  return false;
}

function toDiscoveryRecord(service: BonjourServiceLike): DiscoveryRecord {
  const txt = toStringRecord(service.txt ?? {});
  const host = (service.host ?? service.name ?? 'unknown').replace(/\.$/, '');
  const port = service.port ?? 80;
  const addresses = [...new Set((service.addresses ?? []).filter(Boolean))];
  const bestHost = selectBestHost(addresses, host);

  return {
    name: service.name ?? 'unknown',
    fqdn: service.fqdn ?? service.name ?? 'unknown',
    host,
    port,
    url: `http://${formatHostForUrl(bestHost)}:${port}/`,
    addresses,
    txt,
    bundleId: txt.bundleId,
    version: txt.version,
    transport: txt.transport,
    codes: extractCodes(txt),
  };
}

function toStringRecord(record: Record<string, unknown>): Record<string, string> {
  const stringRecord: Record<string, string> = {};

  for (const [key, value] of Object.entries(record)) {
    if (Buffer.isBuffer(value)) {
      stringRecord[key] = value.toString('utf8');
      continue;
    }

    if (value === undefined || value === null) {
      continue;
    }

    stringRecord[key] = String(value);
  }

  return stringRecord;
}

function discoveryKey(record: DiscoveryRecord): string {
  return `${record.fqdn}|${record.port}|${record.host}`;
}

function compareDiscoveryRecords(left: DiscoveryRecord, right: DiscoveryRecord): number {
  return left.name.localeCompare(right.name) || left.url.localeCompare(right.url);
}

function selectBestHost(addresses: string[], fallbackHost: string): string {
  const ipv4 = addresses.find((address) => isIpv4(address));
  if (ipv4) {
    return ipv4;
  }

  const globalIpv6 = addresses.find((address) => isIpv6(address) && !address.startsWith('fe80:'));
  if (globalIpv6) {
    return globalIpv6;
  }

  return addresses[0] ?? fallbackHost;
}

function formatHostForUrl(host: string): string {
  return isIpv6(host) && !host.startsWith('[') ? `[${host}]` : host;
}

function isIpv4(value: string): boolean {
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(value);
}

function isIpv6(value: string): boolean {
  return value.includes(':');
}
