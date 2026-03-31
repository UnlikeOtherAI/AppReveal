import { useEffect } from 'react';
import NativeAppReveal from './NativeAppReveal';
import type { CapturedRequest } from './types';

// Minimal type for React Navigation state — avoids a hard dep on @react-navigation/native
interface NavigationState {
  index: number;
  routes: Array<{ name: string; state?: NavigationState }>;
}

export type { CapturedRequest };

// ─── AppReveal ───────────────────────────────────────────────────────────────

export class AppReveal {
  private constructor() {}

  static start(port: number = 0): void {
    if (!__DEV__) return;
    NativeAppReveal.start(port);
  }

  static stop(): void {
    if (!__DEV__) return;
    NativeAppReveal.stop();
  }

  static setScreen(key: string, title: string): void {
    if (!__DEV__) return;
    NativeAppReveal.setScreen(key, title, 1.0);
  }

  static setNavigationStack(
    routes: string[],
    current: string,
    modals: string[] = [],
  ): void {
    if (!__DEV__) return;
    NativeAppReveal.setNavigationStack(routes, current, modals);
  }

  static setFeatureFlags(flags: Record<string, unknown>): void {
    if (!__DEV__) return;
    NativeAppReveal.setFeatureFlags(flags);
  }

  static captureNetworkCall(call: CapturedRequest): void {
    if (!__DEV__) return;
    NativeAppReveal.captureNetworkCall(call as unknown as object);
  }

  static captureError(
    domain: string,
    message: string,
    stackTrace: string = '',
  ): void {
    if (!__DEV__) return;
    NativeAppReveal.captureError(domain, message, stackTrace);
  }

  /**
   * Returns a React Navigation compatible listener object.
   *
   * Usage:
   * ```tsx
   * const navListener = AppReveal.createNavigationListener();
   * <NavigationContainer
   *   onStateChange={navListener.onStateChange}
   *   ref={navListener.ref}
   * >
   * ```
   */
  static createNavigationListener(): (state: NavigationState | undefined) => void {
    return createNavigationListener();
  }
}

// ─── Navigation listener ─────────────────────────────────────────────────────

function getActiveRouteName(state: NavigationState | undefined): string {
  if (!state) return '';
  const route = state.routes[state.index];
  if (route.state) {
    return getActiveRouteName(route.state as NavigationState);
  }
  return route.name;
}

function collectRouteNames(
  state: NavigationState | undefined,
  result: string[] = [],
): string[] {
  if (!state) return result;
  for (const route of state.routes) {
    result.push(route.name);
    if (route.state) {
      collectRouteNames(route.state as NavigationState, result);
    }
  }
  return result;
}

/**
 * Returns an `onStateChange` handler for `<NavigationContainer>`.
 *
 * Usage:
 * ```tsx
 * const navRef = useRef<NavigationContainerRef<any>>(null);
 * <NavigationContainer ref={navRef} onStateChange={AppReveal.createNavigationListener()}>
 * ```
 */
export function createNavigationListener(): (
  state: NavigationState | undefined,
) => void {
  return (state: NavigationState | undefined) => {
    if (!__DEV__ || !state) return;
    const current = getActiveRouteName(state);
    const routes = collectRouteNames(state);
    AppReveal.setScreen(current.toLowerCase().replace(/\s+/g, '.'), current);
    AppReveal.setNavigationStack(routes, current);
  };
}

// ─── Hook ─────────────────────────────────────────────────────────────────────

/**
 * Convenience hook — call at the top of any screen component to register it
 * with AppReveal when mounted.
 *
 * ```tsx
 * function OrdersScreen() {
 *   useAppRevealScreen('orders.list', 'Orders');
 *   ...
 * }
 * ```
 */
export function useAppRevealScreen(
  screenKey: string,
  screenTitle: string,
): void {
  useEffect(() => {
    if (!__DEV__) return;
    AppReveal.setScreen(screenKey, screenTitle);
  }, [screenKey, screenTitle]);
}

// ─── Fetch interceptor ────────────────────────────────────────────────────────

let _fetchPatched = false;

export class AppRevealFetchInterceptor {
  private constructor() {}

  /**
   * Monkey-patches global fetch to capture all requests.
   * Safe to call multiple times — only patches once.
   *
   * Call once at app startup:
   * ```ts
   * if (__DEV__) AppRevealFetchInterceptor.install();
   * ```
   */
  static install(): void {
    if (!__DEV__) return;
    if (_fetchPatched) return;
    _fetchPatched = true;

    const originalFetch = global.fetch;

    global.fetch = async function patchedFetch(
      input: RequestInfo | URL,
      init?: RequestInit,
    ): Promise<Response> {
      const url =
        typeof input === 'string'
          ? input
          : input instanceof URL
          ? input.toString()
          : (input as Request).url;

      const method =
        init?.method ??
        (typeof input !== 'string' && !(input instanceof URL)
          ? (input as Request).method
          : 'GET');

      const id = Math.random().toString(36).slice(2);
      const requestTimestamp = Date.now();

      let requestHeaders: Record<string, string> | undefined;
      if (init?.headers) {
        const h = init.headers;
        if (h instanceof Headers) {
          requestHeaders = {};
          h.forEach((v, k) => { requestHeaders![k] = v; });
        } else if (Array.isArray(h)) {
          requestHeaders = Object.fromEntries(h);
        } else {
          requestHeaders = h as Record<string, string>;
        }
      }

      try {
        const response = await originalFetch(input, init);
        const responseTimestamp = Date.now();

        let responseHeaders: Record<string, string> | undefined;
        if (response.headers) {
          responseHeaders = {};
          response.headers.forEach((v: string, k: string) => {
            responseHeaders![k] = v;
          });
        }

        AppReveal.captureNetworkCall({
          id,
          method: method.toUpperCase(),
          url,
          statusCode: response.status,
          requestTimestamp,
          responseTimestamp,
          requestHeaders,
          responseHeaders,
        });

        return response;
      } catch (err: unknown) {
        const message =
          err instanceof Error ? err.message : String(err);
        AppReveal.captureNetworkCall({
          id,
          method: method.toUpperCase(),
          url,
          requestTimestamp,
          error: message,
        });
        throw err;
      }
    };
  }
}
