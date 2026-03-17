/**
 * Simple in-memory app state for the example. In a real app this would live
 * in Redux, Zustand, Context, etc.
 */
export class ExampleState {
  private static _instance: ExampleState | null = null;

  static get instance(): ExampleState {
    if (!ExampleState._instance) {
      ExampleState._instance = new ExampleState();
    }
    return ExampleState._instance;
  }

  isLoggedIn = false;
  userEmail = '';
  userName = '';
  userBio = '';
  notificationsEnabled = true;
  darkMode = false;
  selectedTab = 'Orders';
  cartItemCount = 0;
  cartItems: Array<{ id: string; name: string; price: number; qty: number }> = [];

  snapshot(): Record<string, unknown> {
    return {
      isLoggedIn: this.isLoggedIn,
      userEmail: this.userEmail,
      userName: this.userName,
      selectedTab: this.selectedTab,
      cartItemCount: this.cartItemCount,
      notificationsEnabled: this.notificationsEnabled,
      darkMode: this.darkMode,
    };
  }

  featureFlags(): Record<string, unknown> {
    return {
      new_checkout: true,
      dark_mode_beta: false,
      loyalty_points: true,
      express_delivery: false,
      product_reviews: true,
      push_notifications: this.notificationsEnabled,
      analytics_v2: true,
      webview_demo: true,
    };
  }
}
