# CLI verification

Run portable CLI checks on Maxis, in a dedicated checkout on C:. From `CLI`:

```powershell
pnpm.cmd install --frozen-lockfile
pnpm.cmd lint
pnpm.cmd typecheck
pnpm.cmd test
```

`pnpm test` builds the executable before running the unit and HTTP fixture tests.
The fixtures bind ephemeral loopback ports, use generated test credentials, and
launch the same `dist/index.js` entry point shipped to users. They verify state
changes after interactions but do not exercise a platform UI toolkit.

For native verification, start an example app on its appropriate host and save
its authenticated session URL in an owner-only file. Reserve its UI state with
any other reviewer before sending interactions. From the repository root:

```powershell
node scripts/verify-cli-mcp.mjs --session-file <private-file> --host 192.168.1.229 --report CLI/artifacts/live-report.json
```

Omit `--host` when the session URL already names the app's reachable host. The
probe checks HTTP 401 without credentials, authenticated initialization and tool
inventory, a snapshot where supported, unknown-tool failure, and recovery. It
prints only step labels and writes a credential-free report. No screenshot is
captured by default. Record the app revision separately; a CLI fixture revision
or an uncommitted native build is not proof of the integrated release.

Supply `--plan <json-file>` for the example's actual interaction and state checks.
Each step contains CLI `args`, a `label`, optional `expectFailure`, and optional
`expect` assertions with an array `path` into fleet JSON and an `equals` value.
For example, a macOS example flow that returns to Settings:

```json
[
  {"label":"open settings","args":["call","tap_element","--arg","element_id=sidebar.row.settings"]},
  {"label":"settings selected","args":["call","get_state"],"expect":[{"path":[0,"result","selectedSection"],"equals":"settings"}]}
]
```

Choose stable IDs from the current example's `get_elements`. Test an interaction,
read back its resulting state, exercise a missing/invalid target, and verify a
subsequent valid action. Add screenshots only when needed to verify changed UI;
`call screenshot` now retains the MCP image content rather than discarding it.
