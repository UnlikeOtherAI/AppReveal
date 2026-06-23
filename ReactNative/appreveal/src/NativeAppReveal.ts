import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  start(port: number): void;
  stop(): void;
  setScreen(key: string, title: string, confidence: number): void;
  setState(state: object): void;
  setNavigationStack(routes: string[], current: string, modals: string[]): void;
  setFeatureFlags(flags: object): void;
  captureNetworkCall(call: object): void;
  captureError(domain: string, message: string, stackTrace: string): void;
}

const createMissingNativeModule = (): Spec => {
  const fail = (): never => {
    throw new Error(
      'react-native-appreveal native module is not installed. Rebuild the app after installing the package.',
    );
  };

  return {
    start: fail,
    stop: fail,
    setScreen: fail,
    setState: fail,
    setNavigationStack: fail,
    setFeatureFlags: fail,
    captureNetworkCall: fail,
    captureError: fail,
  };
};

export default TurboModuleRegistry.get<Spec>('AppReveal') ?? createMissingNativeModule();
