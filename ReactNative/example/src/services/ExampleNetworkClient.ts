/**
 * Simulates API calls using the global fetch so the AppRevealFetchInterceptor
 * captures them automatically.
 */
export class ExampleNetworkClient {
  private static _instance: ExampleNetworkClient | null = null;

  static get instance(): ExampleNetworkClient {
    if (!ExampleNetworkClient._instance) {
      ExampleNetworkClient._instance = new ExampleNetworkClient();
    }
    return ExampleNetworkClient._instance;
  }

  async fetchCatalog(): Promise<void> {
    try {
      await fetch('https://api.example.com/catalog?page=1');
    } catch {
      // Simulated — network will fail but the interceptor still fires
    }
  }

  async fetchOrders(): Promise<void> {
    try {
      await fetch('https://api.example.com/orders');
    } catch {}
  }

  async fetchProfile(): Promise<void> {
    try {
      await fetch('https://api.example.com/user/profile');
    } catch {}
  }

  async fetchFeatureFlags(): Promise<void> {
    try {
      await fetch('https://api.example.com/feature-flags');
    } catch {}
  }

  async login(email: string): Promise<void> {
    try {
      await fetch('https://api.example.com/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password: '***' }),
      });
    } catch {}
  }

  async simulateLaunchCalls(): Promise<void> {
    await Promise.all([
      this.fetchProfile(),
      this.fetchFeatureFlags(),
      this.fetchCatalog(),
      this.fetchOrders(),
    ]);
  }
}
