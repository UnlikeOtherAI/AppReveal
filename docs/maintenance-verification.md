# Maintenance verification and capability boundaries

Use the running target's `tools/list` as the contract. A tool name shared by
several platforms does not imply every host framework implements it. Failed
operations return MCP `isError`; batches also report `success: false` if any
action fails. Empty or whitespace-only diagnostic `error` strings are not failures.
Missing DOM roots fail instead of silently inspecting the whole page.

| Target | Repeatable verification | Boundary |
| --- | --- | --- |
| iOS/macOS | [Apple instructions](../example/iOS/scripts/APPLE_VERIFICATION.md) | Simulator and AppKit examples; macOS positive WebView coverage uses real WKWebView tests. Physical devices, older runtimes and signing are separate checks. |
| Android/Compose | [HTTP walkthrough](../example/Android/verification/verify_mcp.py) | Activity decor hierarchy; separate Dialog windows are not covered. Compose direction scrolling is supported; `scroll_to_element` currently requires a native View target. |
| React Native | [Native and JS checks](../ReactNative/VERIFICATION.md) | The example lacks Android/iOS host projects. Library compilation and contract tests do not prove JS-controlled input, touch dispatch or navigation in a native host. |
| Flutter | [Example verification](../Flutter/example/README.md) | Windows app interactions and Chrome DOM scripts are separate checks. Windows has no `webview_flutter` backend, so native WebView transport needs a supported mobile/macOS host. |
| Windows .NET | [Fixtures](../Windows/verification/README.md) | WinForms/UIA is exercised; WPF, WinUI, Avalonia and custom WebView providers need their own hosts. Navigation reports shortcut delivery; the host owns routing. |
| Tauri | [Fixtures and limits](../Windows/verification/RESULTS.md) | Windows/WebView2 is exercised. Scrolling, screenshots, history/evaluation and menu activation need host providers and are not advertised by the generic bridge. |
| CLI | [HTTP/live probe](cli-verification.md) | Authenticated direct URLs work independently of mDNS discovery. |

The maintenance run's PR records source revisions, environments, actual outcomes
and unverified paths. Keep session URLs and launch logs private; they contain
credentials. Sanitized evidence may be retained separately from disposable builds.
