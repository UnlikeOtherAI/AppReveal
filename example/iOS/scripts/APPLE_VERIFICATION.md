# Apple maintenance verification

Run these checks on macOS (`dictator`). They build only the Apple framework and existing examples.
No UI screens are added or redesigned. XcodeGen and SwiftLint must be installed.

From the repository root, choose an **existing** compatible iOS simulator and set `APPLE_SIMULATOR_ID`.
The verified device was `2176C913-0551-42B1-9A1B-D97A25F6CC0A` (iOS 26.5).

```bash
swift test --jobs 4
(cd iOS && swiftlint lint --strict --config .swiftlint.yml)
swift build -c release --jobs 4
xcodebuild -scheme AppReveal -destination "id=$APPLE_SIMULATOR_ID" \
  -derivedDataPath example/iOS/.build/tests -jobs 4 test
xcodegen generate --spec example/iOS/AppRevealExample/project.yml
xcodebuild -project example/iOS/AppRevealExample/AppRevealExample.xcodeproj \
  -scheme AppRevealExample -destination "id=$APPLE_SIMULATOR_ID" \
  -derivedDataPath example/iOS/.build -jobs 4 CODE_SIGNING_ALLOWED=NO test
```

The hosted example tests cover real UIKit text delegates, bounded scrolling, switches, root Back,
text-tracking overlays, SwiftUI text bindings, lazy-grid activation, disabled controls and window scope.
The package's macOS tests exercise real AppKit controls and WKWebView JavaScript, including failures.
These are separate from physical-device or real-network verification.

For authenticated HTTP verification, launch the Debug examples and capture stdout privately.
The macOS example can be built using the existing `script/build_and_run.sh`, or with XcodeGen and
`xcodebuild` into an ignored directory under this worktree. **Raise its window before running the
smoke script**; a hidden macOS window is intentionally excluded from `list_windows`.

Create the evidence directory with mode 0700 and run launch commands under `umask 077`.
Use `open -n -o <private-stdout-log> --stderr <private-stderr-log> --env NSUnbufferedIO=YES <mac-app>`.
For iOS use `xcrun simctl install` and
`SIMCTL_CHILD_NSUnbufferedIO=YES xcrun simctl launch --stdout=<private-log> --stderr=<private-log> <udid> com.appreveal.example`.
Hosted tests terminate the example, so launch it again afterward.
Do not print stdout logs: AppReveal includes its session token in them.

Extract the session URL into a private file, then run the appropriate smoke flow:

```bash
python3 example/iOS/scripts/apple_mcp_client.py \
  --session-from-log <private-stdout-log> --session-file <private-session-file>
PYTHONDONTWRITEBYTECODE=1 python3 example/iOS/scripts/verify_apple_mcp.py \
  --session-file <private-session-file> --platform ios --output <ignored-evidence-dir>
# Repeat with the macOS app's session file and --platform macos.
```

Each run verifies 401 rejection, authenticated initialization, inspection, state, diagnostics,
invalid arguments/window/target failures, recovery and batch stopping. The iOS flow exercises
order navigation and notes, a Settings switch, DOM inspection, typing/clearing, read-only rejection,
selection, toggles, disabled clicks, counters and scrolling. The macOS flow checks sidebar navigation,
text matching, editing, coordinate-based switches, safe Back and menu/WebView failure paths.

The scripts restore the macOS endpoint and notification switch. iOS finishes on Orders and resets
the example web form. They operate on fixture data only. They never print or copy the session URL
into evidence. Use a private session file with mode 0600. Add `--screenshot` only when needed: each
invocation captures exactly one PNG and verifies the actual MCP image block and its metadata.

The macOS example contains no WKWebView, so its positive DOM paths are exercised in the real
WKWebView package tests; the iOS example supplies the authenticated HTTP DOM path. No physical
Apple device, macOS sandbox distribution, older OS or iPad runtime is covered by these commands.
