import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  start(port: number): void;
  stop(): void;
  setScreen(key: string, title: string, confidence: number): void;
  setNavigationStack(routes: string[], current: string, modals: string[]): void;
  setFeatureFlags(flags: Object): void;
  captureNetworkCall(call: Object): void;
  captureError(domain: string, message: string, stackTrace: string): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('AppReveal');
