# React Native maintenance verification

## Repeatable checks

Run portable checks on Maxis, from `ReactNative/appreveal`:

```powershell
pnpm.cmd install --frozen-lockfile
pnpm.cmd typecheck
pnpm.cmd lint
pnpm.cmd test
```

The four Node tests execute the compiled TypeScript module and check successful
fetch responses, original network errors, bridge failures, request headers and
timing, port bounds, and restored partial navigation state. React Native is
substituted in these focused tests; they do not establish native UI coverage.

From `ReactNative/example`, run `pnpm.cmd install --lockfile=false` and
`pnpm.cmd typecheck`. The example now includes its previously missing calibration
screen, uses the listener returned by `createNavigationListener`, and resolves
types from its own React Native version.

On an Android build host, from the repository root:

```bash
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=/path/to/Android/Sdk
./Android/gradlew -p ReactNative/appreveal/android testDebugUnitTest assembleDebug lintDebug --max-workers=2 --console=plain
```

This builds the native Android library against React Native 0.81.4 by default.
Override with `-PappRevealReactNativeVersion=<host-version>` when checking a
specific host. SDK platform 35 and build tools 36.0.0 are required. Unit tests
cover MCP error/batch semantics, the `reactnative` launch-context hint, JS network
timestamp/header/body-size ingestion, redaction and bounded retrieval.

On the Apple reviewer's verification host, the Foundation-only regression harness
can be compiled independently of a React Native host:

```bash
mkdir -p ReactNative/appreveal/build
swiftc -swift-version 5 \
  ReactNative/appreveal/ios/AnyCodable.swift \
  ReactNative/appreveal/ios/CapturedRequest.swift \
  ReactNative/appreveal/ios/NetworkObserver.swift \
  ReactNative/appreveal/ios/ToolResult.swift \
  ReactNative/appreveal/tests/NativeContractChecks.swift \
  -o ReactNative/appreveal/build/native-contract-checks
ReactNative/appreveal/build/native-contract-checks
```

The Android/RN implementation reviewer did not run Apple builds. The harness
checks error-result classification and network timestamps/redaction; it does not
exercise the UIKit router or native React Native startup.

## Runtime limits

The repository still lacks the example's `android/` and `ios/` host projects.
Native RN touch dispatch, JS-controlled TextInput updates, navigation callbacks,
WebViews and screen capture must be exercised in a real linked host. The Android
AAR and TypeScript checks must not be reported as that verification.

The independent Android example has an authenticated MCP walkthrough at
`example/Android/verification/verify_mcp.py`. Its evidence applies to the native
Android/Compose implementation, not to the RN JS/native event boundary.
