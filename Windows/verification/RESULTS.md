# Windows maintenance results — 12 November 2026

Scope: `Windows/` only, from base
`5d6d16d67a7cd08069f3d69c2d484249e2ed8485`.
Branch: `t3/windows-provider-http-fixes`.
Editing worktree on dictator:
`/Users/dictator/.t3/worktrees/appreveal/t3-0a8c6c3d-73328d554556f0c8`.
Windows verification worktree on Maxis:
`C:\Users\ondre\Projects\AppReveal-windows-maintenance-20261112`.
The coordinator's final report identifies the pushed commit. Verification source
was transferred as Git tree/blob objects before committing; the isolated Maxis
index/worktree matched the staged source, without writing its primary checkout.

## Fixed findings

- **P1 — Windows Rust HTTP connections aborted on fragmented requests.** Winsock
  inherited the nonblocking listener mode. The parser could fail before a later
  TCP packet arrived. Accepted connections now use bounded blocking I/O. The
  authenticated fragmented-body regression failed with Winsock 10053 before the
  fix and passed afterward. This was also reproduced by real WebView HTTP runs.
- **P1 — native commands could send input to an unrelated foreground app.**
  Text editing now uses a writable app-owned UIA ValuePattern and reads it back;
  scrolling uses the target's ScrollPattern and checks movement; points must hit
  the selected app window; navigation shortcuts require that window to be
  foreground. Disabled/read-only/unsupported targets no longer claim success.
- **P1 — DOM indexes could target a different node after insertion; disabled
  controls could report successful interaction.** Tauri now shares one inventory
  and action bridge with stable per-document node IDs, literal text matching,
  editability/visibility checks, native value setters, exact select values,
  preserved text whitespace and specific failures. Password values are omitted.
- **P2 — MCP and batch success did not reflect action failure.** Both transports
  propagate failed results as MCP tool errors and stop batches accordingly.
  Empty and whitespace-only `error` strings remain successful; nonempty error
  strings fail. Regressions cover this distinction, explicit failure flags,
  recursive batches and action limits. .NET tool schemas now expose and validate
  native interaction arguments. Rust invalid arguments return `-32602`.
- **P2 — malformed HTTP/JSON and diagnostics were mishandled.** Fixed .NET
  envelope/UTF-8 validation and body limits, Rust Unicode bearer-prefix slicing,
  bounded HTTP line reads and predictable random-token fallback. Corrected .NET
  absent-provider advertising, log subsystem filtering and physical-memory data;
  Rust default platform metadata and network-header redaction. UIA runtime IDs
  now agree between inventory, tree and interactions.

## Verification

All builds and runtime checks ran on **Maxis**, Windows 11 Pro `10.0.26300`, on
C:. .NET SDK `10.0.404` compiled the `net8.0-windows` fixture; WindowsDesktop
`8.0.34` was installed. Rust was `1.99.0`; the resolved Tauri version was
`2.12.5` with wry `0.57.2`. Installed WebView2 runtime directories were
`157.0.4341.42` and `157.0.4341.46`. Builds used two Cargo workers. Dictator ran
editing, Git, diff checks and rustfmt only.

- .NET authenticated HTTP/provider fixture: **22 checks passed**.
- Real WinForms/UIA fixture through authenticated HTTP: **34 checks passed**.
  Checked resulting state for button taps, Unicode typing, clearing, tabs,
  scrolling, scroll-to-element and menu activation. Verified focus and actual
  back/Escape shortcut delivery, rejected targets, decoded MCP screenshot image
  bytes, and successful interaction after failures.
- Rust default-feature suite: **37 tests passed**.
- Rust `--features tauri` suite: **37 tests passed**.
- Real Tauri/WebView2 fixture through authenticated HTTP: **30 checks passed**.
  Checked launch/device/window/menu inspection, DOM aliases, stable IDs and CSS
  selectors after insertion, text and point taps, Unicode/whitespace typing,
  contenteditable, select, checkbox state, failure classification and recovery.
- Changed Rust files passed rustfmt checks; the DOM bridge passed `node --check`;
  Git diff whitespace checks passed.

Commands are in [README.md](README.md). Evidence stays on Maxis under the
verification worktree's `Windows/artifacts/`:

- `checks/dotnet-protocol.log`
- `checks/rust-default.log`, `checks/rust-tauri.log`
- `checks/tauri-host-build.log`
- `dotnet-live/checks.log`, `dotnet-live/exit-code.txt`
- `tauri-live/checks.log`, `tauri-live/exit-code.txt`

Both desktop exit codes were 0. Session URLs are private runtime files, removed
by the worker; they are not evidence artifacts. Scheduled task cleanup runs with
the launcher's authority because the limited desktop token cannot delete tasks
registered by an elevated SSH session. No screenshots were saved or
attached. Existing product/example UI was not changed; the new UIs are isolated
verification fixtures.

## Limits and coordinator follow-up

- WinForms is a real native UIA host, but WPF, WinUI and Avalonia hosts were not
  run. Successful external URI launch was not exercised; invalid URI rejection
  was. Shortcut delivery was checked with actual app handlers, not a particular
  host's routing or modal lifecycle. Screenshots were decoded, not compared
  visually to golden images. No native packaging, signing or release occurred.
- Tauri was executed on Windows/WebView2 only. macOS/WKWebView, Linux/WebKitGTK,
  React-controlled inputs and other frontend frameworks were not run. The value
  setter fix addresses framework trackers, but is not claimed as a live React
  test. DOM events remain synthetic; closed shadow roots, cross-origin frames,
  trusted-event-only handlers and host-specific extensions remain gaps.
- The generic Tauri bridge does not advertise scrolling, screenshots, view-tree,
  WebView navigation/history/evaluation or menu activation. .NET WebView tools
  require a host-supplied provider; that integration was not exercised. App
  diagnostics are provider hooks, not automatic capture of every framework.
- The existing global workflow only builds .NET and runs default Rust tests on
  Ubuntu. The coordinator should add the .NET HTTP fixture and Windows Tauri
  feature checks from README, and retain interactive Windows verification for
  actual UI flows. No global CI or docs were edited here.
- Reconcile the failure classifier across platforms: `success:false`,
  `isError:true`, or a nonempty trimmed error string fails; `error:""` and
  whitespace alone do not. Review the other platform DOM bridges for stale
  position IDs, whitespace normalization and disabled/read-only success.
- Keep both isolated worktrees and evidence until the coordinator integrates the
  branch and completes final verification; then remove them through the normal
  cleanup workflow. No PR was created or merged by this implementation agent.
