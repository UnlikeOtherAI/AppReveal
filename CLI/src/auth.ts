import { normalizeUrl } from './discovery.js';

const sessionTokens = new Map<string, string>();
const secrets = new Set<string>();
const TOKEN_QUERY = 'appreveal_session_token';

/** Keep credentials out of target records, output, and request URLs. */
export function registerSessionUrl(raw: string): string {
  const url = new URL(normalizeUrl(raw));
  if (url.username || url.password) {
    throw new Error('URL userinfo is not supported. Use an AppReveal session URL.');
  }
  const tokens = url.searchParams.getAll(TOKEN_QUERY);
  if (tokens.length > 1 || (tokens.length === 1 && !tokens[0].trim())) {
    throw new Error('Session URL must contain one non-empty session token.');
  }
  url.searchParams.delete(TOKEN_QUERY);
  url.hash = '';
  const endpoint = url.toString();
  if (tokens[0]) {
    secrets.add(tokens[0]);
    secrets.add(encodeURIComponent(tokens[0]));
    sessionTokens.set(endpoint, tokens[0]);
  }
  return endpoint;
}

export function requestCredentials(raw: string): { url: string; headers: Record<string, string> } {
  // Environment credentials are scoped to their exact endpoint, never to a fleet.
  const url = registerSessionUrl(raw);
  if (!sessionTokens.has(url) && process.env.APPREVEAL_SESSION_URL) registerSessionUrl(process.env.APPREVEAL_SESSION_URL);
  const token = sessionTokens.get(url);
  return { url, headers: token ? { Authorization: `Bearer ${token}` } : {} };
}

export function redactSecrets(text: string): string {
  let safe = text.replace(/(appreveal_session_token=)[^&\s"'<>\\]+/gi, '$1[REDACTED]');
  for (const secret of secrets) safe = safe.split(secret).join('[REDACTED]');
  return safe;
}
