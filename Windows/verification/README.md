# Windows maintenance verification

Run from the repository root on a Windows desktop with .NET 8+, Rust/MSVC,
PowerShell 7 and WebView2 installed. Keep build output on the C: SSD. These hosts
are verification fixtures; they do not change an existing example or product UI.

```powershell
dotnet run --project Windows/verification/dotnet -- --protocol
cargo test --manifest-path Windows/appreveal-tauri/Cargo.toml -j 2
cargo test --manifest-path Windows/appreveal-tauri/Cargo.toml --features tauri -j 2
cargo build --manifest-path Windows/verification/tauri/Cargo.toml --target-dir Windows/appreveal-tauri/target -j 2
pwsh -File Windows/verification/run-desktop.ps1 -Target dotnet
pwsh -File Windows/verification/run-desktop.ps1 -Target tauri
```

The desktop launcher schedules only the selected fixture in the current user's
existing interactive session and waits up to 55 seconds for cleanup. Read `Windows/artifacts/<target>-live/checks.log`
and `exit-code.txt` (0 means passed) after the worker finishes. The launcher removes
its own completed scheduled task. If the bounded wait expires, run the same
command with `-Cleanup` after completion; this removes only completed tasks for
this script and target. The worker removes its private session URL and stops only
its own Tauri fixture. The evidence directory has owner-only permissions. Never print the
session file while a run is active. Do not run two copies of the same target at
once. A logged-in desktop is required; SSH/session 0 alone cannot prove UIA or
WebView behavior.

The .NET runner starts a real HttpListener with a random token. Protocol mode
checks authentication, JSON-RPC rejection, tool schemas, provider availability,
batch errors, log filtering, diagnostics and body limits. UI mode starts a real
WinForms window and makes authenticated HTTP calls from a worker while the UI
thread runs normally. It reads actual app state after taps, typing, clearing,
tab selection, scrolling, menus and shortcut delivery, rejects invalid interactions, decodes a screenshot
in memory, and checks recovery. No screenshot files are captured or attached.

The Tauri fixture embeds a real WebView2 document. Its HTTP checks verify stable
IDs after DOM insertion, window labels, literal text matching, Unicode,
whitespace, contenteditable, select, checkbox activation, disabled/read-only and
missing targets, batch stopping, screen coordinates and recovery. The core Rust
suite alone does **not** verify the optional Tauri feature or live WebView calls.
The fixture does not prove React integration, other WebView engines, trusted
native input events, shadow DOM, or host-specific navigation/screenshots.

For CI, run the first three commands for library/protocol coverage. Run the
fixture build and desktop commands on an interactive Windows worker for actual
UI verification. Parent integration must retain both classes of evidence.
