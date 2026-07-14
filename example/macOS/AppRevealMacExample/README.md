# AppReveal Mac Example

Example AppKit app demonstrating AppReveal on macOS.

## Setup

From the repository root, use the shared build/run entrypoint. It regenerates the Xcode project,
stops an existing example process, builds, launches, and verifies the fresh app:

```bash
brew install xcodegen  # if needed
./script/build_and_run.sh --verify
```

The Codex Run action calls the same script. You can also open the generated Xcode project and run the
`AppRevealMacExample` scheme. The app starts AppReveal in `#if DEBUG` from `App/AppDelegate.swift`.

## Verify with curl

Once the app is running:

```bash
# Discover the advertised service
dns-sd -B _appreveal._tcp local.

# Copy the token from the printed AppReveal.sessionURL.
TOKEN="<session-token>"

# Initialize MCP
curl -X POST http://localhost:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# List windows
curl -X POST http://localhost:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_windows","arguments":{}}}'

# Read the menu bar
curl -X POST http://localhost:<port>/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_menu_bar","arguments":{}}}'
```

Or verify health and authentication together with the repository script:

```bash
../../../scripts/verify-macos-lan-mcp.sh \
  'http://127.0.0.1:<port>/?appreveal_session_token=<token>' [<lan-host-or-ip>]
```

Expected results:

- `initialize` returns the server capabilities
- `list_windows` returns at least one window ID
- `get_menu_bar` returns the app menu hierarchy
