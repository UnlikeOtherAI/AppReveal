# AppReveal CLI

AppReveal CLI is a local-network shell interface for AppReveal MCP servers. It exists so humans and LLMs can discover running debug builds, identify devices, inspect the exposed MCP surface, and send either normal tool calls or raw JSON-RPC requests without manually assembling mDNS lookups and `curl` payloads.

It is built around target sets, not just a single device. The same command can fan out across several devices in parallel, and you can narrow the fleet with platform filters such as iOS, macOS, Android, Flutter, or React Native.

## LLM-first workflow

If an LLM is the first thing touching this interface, the operating model should be:

1. Run `appreveal discover --json` to enumerate all reachable AppReveal targets.
2. Pick a target by service name, bundle ID, hostname, IP address, or full URL.
3. Use `--all`, repeated `--target`, or `--platform` when you need several devices at once.
4. Run `appreveal snapshot`, `find`, `tap`, and `type` for common UI-control flows.
5. Use `appreveal inspect`, `call`, or `request` when you need lower-level MCP control.

This CLI is intentionally AppReveal-specific. Discovery is hard-wired to the AppReveal mDNS service type `_appreveal._tcp`.

## What discovery returns

`discover` is designed to answer the practical questions an agent has when choosing a device:

- Service name
- Reachable URL
- Hostname and all resolved IP addresses
- Bundle ID
- Version
- Transport
- `codes`

`codes` is deliberately broad. Today it includes any code-like TXT metadata the service exposes plus app build identifiers such as `build` or `versionCode` when available. If AppReveal later publishes pairing pins or tokens, they will fit in the same field without changing the CLI shape.

## Target selection model

Any target-aware command can work in one of three ways:

- One positional target for simple single-device work
- Repeated `--target <selector>` for an explicit fleet
- `--all` to select everything discovered on the LAN

You can add `--platform ios`, `--platform macos`, `--platform android`, `--platform flutter`, or `--platform reactnative` to narrow the set further.

Selectors can be:

- Service name
- Bundle ID
- Hostname
- IP address
- Full URL

## Install

```bash
cd CLI
pnpm install
pnpm build
```

Install from npm:

```bash
npm install -g @unlikeotherai/appreveal
appreveal --help
```

Run directly from source during development:

```bash
pnpm run start --help
```

Run the built binary:

```bash
node dist/index.js --help
```

If you want a shell command on your machine:

```bash
pnpm link --global
appreveal --help
```

## Commands

### `discover`

Browse the local network for AppReveal servers. By default it probes `launch_context` so the output includes device names and platforms.

```bash
appreveal discover
appreveal discover --json
appreveal discover --platform ios,macos
appreveal discover --timeout 5000
```

### `inspect`

Resolve one or more targets, initialize MCP, call `launch_context`, and list tools. Add `--device-info` for a larger runtime snapshot.

```bash
appreveal inspect AppReveal-com.example.shop
appreveal inspect --all --platform ios --device-info --json
```

### `tools`

List the tools exposed by one or more targets.

```bash
appreveal tools 192.168.1.24
appreveal tools --target 192.168.1.24 --target 192.168.1.25
```

### `snapshot`

Get a compact operational snapshot across one or more targets: launch context, current screen, and a short visible-element list.

```bash
appreveal snapshot com.example.shop
appreveal snapshot --all --platform android,flutter --limit 12
```

### `find`

Search the visible element inventory. This is the fast path for “find the button first, then act on it.”

```bash
appreveal find "login" --all
appreveal find "submit" com.example.shop --field label
```

### `tap`

Find a single visible element and tap it. If several matches tie for best score, the command fails instead of guessing.

```bash
appreveal tap "login.submit" --all
appreveal tap "Continue" --platform ios --field label --exact
```

### `type`

Type into the focused field or resolve an element first with `--element`.

```bash
appreveal type "hello@example.com" com.example.shop
appreveal type "hello@example.com" --element login.email --target com.example.shop --target com.example.shop.android
```

### `call`

Call a normal MCP tool. Supply arguments either as one JSON object with `--args` or as repeatable `--arg key=value`.

Backward-compatible single-target form:

```bash
appreveal call com.example.shop get_screen
```

Fleet form:

```bash
appreveal call get_screen --all
appreveal call batch --platform ios --args '{"actions":[{"tool":"get_screen"},{"tool":"get_elements"}]}'
appreveal call batch --target http://192.168.1.24:49152/ --args '{"actions":[{"tool":"get_screen"},{"tool":"get_elements"}]}'
```

### `request`

Send a raw JSON-RPC request. Use this when the tool wrapper is too restrictive or when you want exact MCP method control.

Backward-compatible single-target form:

```bash
appreveal request com.example.shop tools/list
```

Fleet form:

```bash
appreveal request tools/list --all
appreveal request tools/call --target com.example.shop --params '{"name":"get_logs","arguments":{"limit":20}}'
```

## Target resolution

Every command that accepts a target uses the same resolution logic:

- If the input starts with `http://` or `https://`, it is treated as the full endpoint URL.
- Otherwise the CLI runs discovery and matches against service name, bundle ID, hostname, URL, or any resolved IP address.
- If the selector matches more than one target, the command fails and prints the ambiguous matches.
- Fleet commands dedupe targets by URL before executing work in parallel.

## Development

```bash
cd CLI
pnpm typecheck
pnpm test
pnpm build
```
