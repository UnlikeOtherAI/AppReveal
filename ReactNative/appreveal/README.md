# react-native-appreveal

Debug-only AppReveal MCP framework for React Native iOS and Android apps.

```sh
npm install react-native-appreveal
```

```ts
import { AppReveal } from 'react-native-appreveal';

if (__DEV__) {
  AppReveal.start();
}
```

The package exposes native iOS and Android MCP servers in debug builds, including native UI inspection, screenshots, interactions, state/navigation snapshots, network capture, and WKWebView/Android WebView DOM tools. React Native Windows is intentionally not autolinked until a real Windows MCP bridge is available.

See the React Native guide in the repository for setup notes:
https://github.com/UnlikeOtherAI/AppReveal/blob/main/ReactNative/README.md
